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

1. Configure Cloudflare Access and MFA for the Vaultwarden administration page before using it. The detailed procedure is in [Protect the Admin Page](#protect-the-admin-page).

1. Start the stack:

   ```sh
   docker compose up -d
   docker compose logs -f
   ```

1. Open `https://<VAULTWARDEN_DOMAIN>` after the tunnel reports healthy. Cloudflare provides the browser-trusted certificate; no local CA installation is necessary.

## Protect the Admin Page

Protect only `https://<VAULTWARDEN_DOMAIN>/admin` with interactive Cloudflare Access. Do not put the complete Vaultwarden hostname behind an interactive Access login until every Bitwarden client you use has been tested: desktop and mobile applications may not support Access's browser redirect login for API calls.

Vaultwarden user accounts, Vaultwarden two-step login, and Cloudflare Access are separate controls. This procedure adds two controls to `/admin`: Cloudflare authentication with MFA, then Vaultwarden's `ADMIN_TOKEN`.

### Enable an Access login method

For a personal deployment, Cloudflare One-time PIN is the simplest login method. It sends a code to an email address you explicitly allow.

1. In the Cloudflare dashboard, select **Zero Trust** > **Integrations** > **Identity providers**.
1. In **Your identity providers**, select **Add new identity provider**.
1. Select **One-time PIN** and save it.

Alternatively, add Google, GitHub, Microsoft Entra ID, or another SSO identity provider in the same location. Enforce MFA in that provider if you intend to rely on provider-managed MFA.

### Enable independent MFA

The MFA choices in an Access application remain unavailable until you enable at least one organization-level independent MFA method.

1. Go to **Zero Trust** > **Access controls** > **Access settings**.
1. Under **Allow multi-factor authentication (MFA)**, enable one or more browser-compatible methods:
   - **Authenticator application** for TOTP codes from 1Password, Authy, Google Authenticator, or Microsoft Authenticator.
   - **Security key** for a WebAuthn hardware key, such as a YubiKey.
   - **Biometrics** for Touch ID, Face ID, or Windows Hello.
1. Set the authentication duration. Choose `1 hour` or **Require every login** for the admin page.
1. Leave **Apply global MFA settings by default** disabled to avoid imposing MFA on any other Access application.
1. Save.

Do not select only PIV key or FIDO2 key. Those options apply to SSH infrastructure applications, not browser access to Vaultwarden.

### Create the Admin Access Application

1. Go to **Zero Trust** > **Access controls** > **Applications**.
1. Select **Create new application** > **Self-hosted and private** > **Add public hostname**.
1. Enter the following values:
   - **Application name**: `Vaultwarden Admin`
   - **Domain**: select `<VAULTWARDEN_DOMAIN>`
   - **Path**: `/admin`
   - **Session duration**: `1 hour`
1. In **Access policies**, create an Allow policy named `Allow Vaultwarden administrators`.
1. Add an **Include** rule with selector **Emails** and your exact administrator email address. Add every administrator explicitly; do not use **Everyone** or a broad email-domain rule unless all those users should administer Vaultwarden.
1. Save the policy.
1. Go to the application **Authentication** section and its **MFA** tab.
1. Select **Custom MFA settings**, choose the MFA methods enabled above, set `1 hour` or **Require every login**, and save the application.

Cloudflare Access is deny-by-default: an identity which does not match an Allow policy cannot reach `/admin`.

### Enroll MFA Devices

1. Open `https://<your-team-name>.cloudflareaccess.com`.
1. Sign in using the email or identity provider allowed by the admin policy.
1. Select **Account** > **MFA devices** > **Add an MFA device**.
1. Enroll the authenticator application, security key, or biometric method selected in Access settings.
1. Enroll a second recovery method where possible, such as a TOTP application plus a backup security key.

The direct enrollment address is `https://<your-team-name>.cloudflareaccess.com/AddMfaDevice`.

### Verify the Protection

1. In a private browser window, open `https://<VAULTWARDEN_DOMAIN>/admin`.
1. Confirm Cloudflare only sends a One-time PIN or permits SSO login for the explicitly allowed administrator identity.
1. Confirm Cloudflare requests the configured MFA method.
1. Confirm Vaultwarden then requests `ADMIN_TOKEN`.
1. Open the normal Vaultwarden URL and test the browser vault, desktop client, and mobile client. Keep the normal hostname outside interactive Access if any client fails its normal API authentication.

## Operations

```sh
# Confirm service health and view logs
docker compose ps
docker compose logs -f vaultwarden cloudflared

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
