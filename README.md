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

1. Create the local configuration and generate an admin secret:

   ```sh
   cp .env.example .env
   openssl rand -base64 48
   chmod 600 .env
   ```

   Each variable is documented directly in [`.env.example`](.env.example), including its origin and safe defaults. Put the generated value in `ADMIN_TOKEN`. Set `RCLONE_REMOTE` to a full destination such as `crypt:vaultwarden-backups`.

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

1. Create a Cloudflare Access application for the hostname and add a restrictive Allow policy for the intended identities. This is strongly recommended before using the server. Verify that your Bitwarden clients can complete your chosen Access authentication flow; use WARP/Access service-auth options where non-browser client support is required.

1. Start the stack:

   ```sh
   docker compose up -d
   docker compose logs -f
   ```

1. Open `https://<VAULTWARDEN_DOMAIN>` after the tunnel reports healthy. Cloudflare provides the browser-trusted certificate; no local CA installation is necessary.

## Operations

```sh
# Confirm service health and view logs
docker compose ps
docker compose logs -f vaultwarden cloudflared backup

# Run each backup tier immediately
docker compose exec backup-watch sh /scripts/backup-local.sh watch
docker compose exec backup-scheduled sh /scripts/backup-local.sh scheduled
docker compose exec backup-sync sh /scripts/backup-sync.sh

# Inspect local backup and service logs
ls -lh backups
docker compose logs -f backup-watch backup-scheduled backup-sync

# Upgrade images
docker compose pull
docker compose up -d
```

## Backup Strategy

This follows the reference deployment's three-tier backup strategy:

- `backup-watch` watches `db.sqlite3`. After `BACKUP_WATCH_DEBOUNCE` seconds without another write, it creates a local archive. It limits watch archives to `BACKUP_WATCH_RETENTION` and never creates more than one per hour.
- `backup-scheduled` creates a second local archive on `BACKUP_SCHEDULE` (weekly at 02:00 UTC by default). It limits these to `BACKUP_SCHEDULED_RETENTION`.
- `backup-sync` runs `rclone sync` from the complete local `backups/` directory to `RCLONE_REMOTE` on `BACKUP_SYNC_SCHEDULE` (every ten minutes by default).

Each archive includes a SQLite online-backup copy of `db.sqlite3`, attachments, sends, icon cache, and RSA keys. Unlike a raw copy of an active SQLite database, the online backup API creates a consistent database snapshot. Because `rclone sync` makes its destination match the retained local directory, do not place unrelated files in `RCLONE_REMOTE`.

The backup services follow the reference deployment's Compose-only pattern: `backup-watch` and `backup-scheduled` use Alpine, while `backup-sync` uses the official `rclone/rclone` image. The host-mounted scripts in `backup/` are run directly, so no custom Dockerfile or locally maintained image is required.

## Recovery

1. Stop Vaultwarden: `docker compose stop vaultwarden`.
1. Download the selected archive: `rclone copy <remote>/<watch_or_scheduled>_vaultwarden_<timestamp>.tar.gz ./restore`.
1. Preserve the current `data/` directory before replacing it.
1. Extract the archive into `data/`: `tar -C data -xzf restore/vaultwarden-<timestamp>.tar.gz`.
1. Start Vaultwarden: `docker compose start vaultwarden`.

Test restoration periodically. Backups are only useful when their rclone remote and archive contents can be read.

## Security Notes

- Keep `.env`, `rclone/rclone.conf`, `data/`, `backups/`, and `logs/` private. They are excluded from Git.
- Keep sign-ups disabled unless there is a short, deliberate provisioning window.
- `ADMIN_TOKEN` protects `/admin`; use a unique, high-entropy value.
- A Tunnel prevents direct origin exposure, but the hostname is still internet reachable. Protect it with Cloudflare Access, maintain host updates, and test backups.
