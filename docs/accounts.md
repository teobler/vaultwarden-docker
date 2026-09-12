# Account Provisioning

New registrations are disabled by default because the Vaultwarden hostname is reachable from the Internet through Cloudflare Tunnel.

## Create Initial Accounts

1. Edit `.env` and change `SIGNUPS_ALLOWED=false` to `SIGNUPS_ALLOWED=true`.
1. Apply the setting: `docker compose up -d`.
1. Open `https://<VAULTWARDEN_DOMAIN>` and select **Create account**.
1. After the required accounts exist, change `.env` back to `SIGNUPS_ALLOWED=false` and run `docker compose up -d` again.

## Invite Later Users

Keep registrations disabled and create invitations from Vaultwarden's `/admin` page or through a Vaultwarden organization. Protect the administrator path using [Cloudflare Access and MFA](cloudflare-access.md).
