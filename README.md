# Vaultwarden Cloudflare Tunnel Deployment

Docker Compose deployment for [Vaultwarden](https://github.com/dani-garcia/vaultwarden), based on the operational shape of [vaultwarden-docker-deployment](https://github.com/kbyyd24/vaultwarden-docker-deployment), using Cloudflare Tunnel instead of public IP exposure or a locally managed TLS proxy.

Vaultwarden is reachable at a public Cloudflare hostname, such as `https://vault.example.com`, from anywhere. Cloudflare Tunnel creates the DNS route and terminates TLS at Cloudflare's edge. The host has no inbound published port, no router port forwarding, and its origin IP is not exposed by this deployment. `cloudflared` makes only outbound connections to Cloudflare.

## Architecture

```text
Browser or app -- https://vault.example.com -- Cloudflare -- cloudflared -- Vaultwarden
                                               TLS edge     outbound       Docker network

Vaultwarden data -- watch and weekly local archives -- periodic rclone sync -- encrypted remote
```

Vaultwarden has no host port mapping. Only the `cloudflared` container can reach it through Docker's internal network.

## Prerequisites

- Docker Engine with Docker Compose v2.
- A Cloudflare account with a zone containing the hostname to use.
- A configured `rclone` remote. The remote should provide encryption itself, such as `crypt`, or be an encrypted storage service.

## Set Up

1. Create the local configuration and generate an Argon2id hash for the admin password:

   ```sh
   cp .env.example .env
   docker run --rm -it vaultwarden/server:latest /vaultwarden hash
   chmod 600 .env
   ```

   Enter the plaintext admin password only when prompted. Put the resulting `$argon2id$...` PHC string, not the plaintext password, in `ADMIN_TOKEN`. Each variable is documented directly in [`.env.example`](.env.example), including its origin and safe defaults. Set `RCLONE_REMOTE` to a full destination such as `crypt:vaultwarden-backups`. See [Bitwarden CLI secrets](docs/bitwarden-cli-secrets.md) to source deployment secrets from Bitwarden CLI while retaining `.env` for recovery.

1. Configure rclone on the Docker host, then make its configuration available to the container. The default expects `./rclone/rclone.conf`:

   ```sh
   mkdir -p rclone
   rclone config
   cp ~/.config/rclone/rclone.conf rclone/rclone.conf
   chmod 600 rclone/rclone.conf
   ```

   Alternatively, set `RCLONE_CONFIG_HOST` in `.env` to the absolute directory which contains `rclone.conf`.

1. In Cloudflare Zero Trust, create a **remotely-managed** tunnel and copy its token to `CLOUDFLARE_TUNNEL_TOKEN`.

1. Add a **Public Hostname** to that tunnel:

   - Subdomain: for example, `vault`
   - Domain: the Cloudflare zone, for example, `example.com`
   - Service type: `HTTP`
   - URL: `vaultwarden:80`

   Cloudflare creates the required CNAME record automatically. Do not create an A or AAAA record for the host or open an inbound port on the router.

1. Start the stack:

   ```sh
   ./bin/vaultwarden-compose up -d
   ./bin/vaultwarden-compose logs -f
   ```

1. Open `https://<VAULTWARDEN_DOMAIN>` after the tunnel reports healthy. Cloudflare provides the browser-trusted certificate; no local CA installation is necessary.

## Documentation

- [Account provisioning](docs/accounts.md)
- [Cloudflare Access and MFA](docs/cloudflare-access.md)
- [Bitwarden CLI secrets](docs/bitwarden-cli-secrets.md)
- [Backup operations](docs/backups.md)
- [Recovery and security](docs/recovery.md)
