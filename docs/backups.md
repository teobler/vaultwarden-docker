# Backup Operations

The deployment follows the reference project's three-tier backup strategy.

- `backup-watch` watches `db.sqlite3`. After `BACKUP_WATCH_DEBOUNCE` seconds without another write, it creates a local archive. It limits watch archives to `BACKUP_WATCH_RETENTION` and never creates more than one per hour.
- `backup-scheduled` creates a second local archive on `BACKUP_SCHEDULE` (weekly at 02:00 UTC by default). It limits these to `BACKUP_SCHEDULED_RETENTION`.
- `backup-sync` runs `rclone sync` from the complete local `backups/` directory to `RCLONE_REMOTE` on `BACKUP_SYNC_SCHEDULE` (every ten minutes by default).

Each archive includes a SQLite online-backup copy of `db.sqlite3`, attachments, sends, icon cache, and RSA keys. The SQLite online backup API creates a consistent database snapshot while Vaultwarden is running. Because `rclone sync` makes its destination match the retained local directory, do not place unrelated files in `RCLONE_REMOTE`.

`backup-watch` and `backup-scheduled` use Alpine, while `backup-sync` uses the official `rclone/rclone` image. Host-mounted scripts in `backup/` run directly, so no custom Dockerfile or locally maintained image is required.

## Commands

```sh
docker compose exec backup-watch sh /scripts/backup-local.sh watch
docker compose exec backup-scheduled sh /scripts/backup-local.sh scheduled
docker compose exec backup-sync sh /scripts/backup-sync.sh

ls -lh backups
docker compose logs -f backup-watch backup-scheduled backup-sync
```
