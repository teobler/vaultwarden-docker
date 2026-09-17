# Recovery and Security

## Restore a Backup

1. Stop Vaultwarden: `docker compose stop vaultwarden`.
1. Download the selected archive: `rclone copy <remote>/<kind>_vaultwarden_<timestamp>.tar.gz ./restore`, where `<kind>` is `watch` or `scheduled`. If the archive is missing remotely, look in `<remote>/previous/` — archives removed by local retention are moved there.
1. Preserve the current `data/` directory, then delete `data/db.sqlite3-wal` and `data/db.sqlite3-shm` so a stale WAL from the old database cannot corrupt the restored one.
1. Extract the archive into `data/`: `tar -C data -xzf restore/<kind>_vaultwarden_<timestamp>.tar.gz`.
1. Verify the database: `sqlite3 data/db.sqlite3 "PRAGMA integrity_check;"` and expect `ok`.
1. Start Vaultwarden: `docker compose start vaultwarden`.

Test restoration periodically. Backups are only useful when their rclone remote and archive contents can be read.

## Security Practices

- Keep `.env`, `rclone/rclone.conf`, `data/`, `backups/`, and `logs/` private. They are excluded from Git.
- Keep sign-ups disabled except during a deliberate account provisioning window.
- `ADMIN_TOKEN` protects `/admin`; store only its Argon2id PHC hash in `.env` and Bitwarden. Generate it using `docker run --rm -it vaultwarden/server:latest /vaultwarden hash` and keep the plaintext password only in your password manager.
- A Tunnel prevents direct origin exposure, but the hostname is still internet reachable. Protect `/admin` with Cloudflare Access and MFA, maintain host updates, and test backups.
