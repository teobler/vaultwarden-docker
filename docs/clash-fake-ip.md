# Clash fake-ip and the Cloudflare Tunnel

`cloudflared` reaches Cloudflare's edge by dialing `region1.v2.argotunnel.com` and `region2.v2.argotunnel.com` on TCP 7844. When the Docker host runs Clash Verge (or any client on the mihomo/Clash kernels) in TUN mode with fake-ip DNS, every DNS query on the host — including the ones forwarded from Docker containers — is hijacked and answered from the fake-ip pool `198.18.0.0/16`. The tunnel then breaks in a way that survives container restarts and reappears after harmless-looking proxy changes. This page documents the working Clash setup and the errors it fixes.

## Why fake-ip breaks the tunnel

With `enhanced-mode: fake-ip` and `dns-hijack: any:53`, the core hands out fake IPs such as `198.18.0.4` and keeps a domain → fake-ip map. Two properties of that design collide with a long-lived `cloudflared` container:

- The container resolves the edge domains once and keeps the answers in memory for its lifetime.
- Any change to the proxy's DNS configuration reloads the core and reshuffles the map, so the fake IP the container still holds gets reassigned to an unrelated domain.

After such a reload, the core relays cloudflared's edge connections to whichever domain now owns the stale fake IP. In the mihomo service log this reads as the connector dialing the wrong host on the edge port:

```text
[TCP] ... (com.docker.backend) --> github.com:7844 match RuleSet(geolocation-!cn)
```

That is cloudflared's edge handshake, hijacked to the wrong destination — and the container logs:

```text
ERR Connection terminated error="TLS handshake with edge error: read tcp 172.18.0.2:35196->198.18.0.4:7844: i/o timeout" connIndex=0
```

Toggling DNS Override, editing DNS settings, updating a profile, restarting the app — any of these can trigger the reshuffle. The fix below takes the edge domains out of the fake-ip pool entirely, so the container always resolves real addresses and no longer depends on the map.

## Configure Clash Verge

In Clash Verge Rev (tested on 2.4.5):

1. Open **Settings → DNS Override** (DNS 覆写) and switch it **on**. The override replaces the whole `dns:` section of the running config; the defaults it offers are a reasonable starting point.
1. In the override's **fake-ip filter** list, add:

   ```text
   +.argotunnel.com
   ```

   `+.` matches every subdomain, which covers `region1.v2.argotunnel.com`, `region2.v2.argotunnel.com`, and `update.argotunnel.com`.

1. Save — Clash Verge validates the config and reloads the core automatically.

A lighter alternative, if you do not want the whole `dns:` section replaced: leave DNS Override off and append the entry from **Profiles → Global Extend Config → Script** (全局扩展配置 → 编辑脚本):

```js
function main(config, profileName) {
  const dns = config.dns ?? (config.dns = {});
  const filter = dns["fake-ip-filter"] ?? (dns["fake-ip-filter"] = []);
  if (!filter.includes("+.argotunnel.com")) filter.push("+.argotunnel.com");
  return config;
}
```

Either path works; what matters is that `+.argotunnel.com` ends up in the effective `fake-ip-filter`. A `dns:` block in the compose file cannot substitute for it — `dns-hijack: any:53` intercepts container queries to any resolver, including `1.1.1.1`.

## Restart the tunnel after DNS changes

The `cloudflared` container caches edge addresses, and the configuration change itself reloads the core — so restart the connector once the new config is live:

```sh
./bin/vaultwarden-compose restart cloudflared
./bin/vaultwarden-compose logs --tail=50 cloudflared
```

Expect four `Registered tunnel connection` lines and no further `198.18.x` handshake timeouts. The same applies going forward: after any future fake-ip or DNS Override change, restart `cloudflared` once.

## Verify the tunnel

1. The edge domains resolve to real addresses — anything but `198.18.x.x`:

   ```sh
   dig +short region1.v2.argotunnel.com
   ```

1. The public hostname answers through the tunnel:

   ```sh
   curl -sS -o /dev/null -w '%{http_code}\n' https://<VAULTWARDEN_DOMAIN>
   ```

## Symptoms and fixes

Every error below was produced by a real misconfiguration; match the message, apply the fix.

| Error | Cause | Fix |
|---|---|---|
| `TLS handshake with edge error: read tcp ...->198.18.x.x:7844: i/o timeout` | the container holds a fake IP whose mapping was reshuffled by a core reload; the core relays the handshake to an unrelated host | add `+.argotunnel.com` to `fake-ip-filter`, then restart `cloudflared` |
| `dig +short region1.v2.argotunnel.com` returns `198.18.x.x` | `dns-hijack: any:53` answers every port-53 query from the fake-ip pool, and the domain is not in `fake-ip-filter` | add `+.argotunnel.com` in DNS Override (or the extend script) and reload |
| Real IPs resolve, but the handshake still times out | the selected proxy node refuses the non-web port 7844 | add the rule `DST-PORT,7844,DIRECT` ahead of the catch-all — 7844 is Cloudflare Tunnel's dedicated edge port |
| The tunnel worked until Clash DNS settings were touched | expected: DNS config changes reload the core and reshuffle fake-ip mappings | the filter entry removes this failure class; still restart `cloudflared` after core reloads |
