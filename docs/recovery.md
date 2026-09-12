# Recovery and Security

## Restore a Backup

1. Stop Vaultwarden: `docker compose stop vaultwarden`.
1. Download the selected archive: `rclone copy <remote>/<watch_or_scheduled>_vaultwarden_<timestamp>.tar.gz ./restore`.
1. Preserve the current `data/` directory before replacing it.
1. Extract the archive into `data/`: `tar -C data -xzf restore/vaultwarden-<timestamp>.tar.gz`.
1. Start Vaultwarden: `docker compose start vaultwarden`.

Test restoration periodically. Backups are only useful when their rclone remote and archive contents can be read.

## Security Practices

- Keep `.env`, `rclone/rclone.conf`, `data/`, `backups/`, and `logs/` private. They are excluded from Git.
- Keep sign-ups disabled except during a deliberate account provisioning window.
- `ADMIN_TOKEN` protects `/admin`; use a unique, high-entropy value.
- A Tunnel prevents direct origin exposure, but the hostname is still internet reachable. Protect `/admin` with Cloudflare Access and MFA, maintain host updates, and test backups.
