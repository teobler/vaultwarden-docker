# Backup Operations

The deployment follows the reference project's three-tier backup strategy.

- `backup-watch` watches the data directory for writes to `db.sqlite3` or `db.sqlite3-wal`. Vaultwarden runs SQLite in WAL mode, so changes land in the `-wal` file while the main database stays untouched and its file descriptor is never closed; watching the directory for both names is what makes the trigger fire. After `BACKUP_WATCH_DEBOUNCE` seconds without another write it creates a local archive, never more than one per `BACKUP_WATCH_MIN_INTERVAL` (default 3600s; note that logged-in clients refresh tokens about hourly, which counts as a write), and keeps `BACKUP_WATCH_RETENTION` archives.
- `backup-scheduled` creates a baseline archive at container start and then one on `BACKUP_SCHEDULE` (weekly at 02:00 UTC by default), keeping `BACKUP_SCHEDULED_RETENTION` archives.
- `backup-sync` runs `rclone sync` from the local `backups/` directory to `RCLONE_REMOTE` on `BACKUP_SYNC_SCHEDULE` (every ten minutes by default). Archives that local retention removes are moved into `previous/` on the remote and pruned after `RCLONE_BACKUP_DIR_RETENTION` (default 30 days), so the mirror never destroys remote history. Setup and troubleshooting for the Cloudflare R2 + crypt pair live in [offsite R2 backup setup](offsite-r2.md).

Each archive includes a SQLite online-backup copy of `db.sqlite3`, attachments, sends, icon cache, and RSA keys. The SQLite online backup API creates a consistent database snapshot while Vaultwarden runs. Do not place unrelated files in `RCLONE_REMOTE`: the sync makes the destination match `backups/`, `previous/` excepted.

`backup-watch` and `backup-scheduled` use Alpine, while `backup-sync` uses the official `rclone/rclone` image. The scheduled services use Alpine's built-in BusyBox `crond`, which works on Docker Desktop without the `dcron` process-group permission issue. Host-mounted scripts in `backup/` run directly, so no custom Dockerfile or locally maintained image is required.

## Health

Each tier records its most recent success as a dot-file marker: `/backup/.last-watch-success`, `/backup/.last-scheduled-success`, and `/logs/.last-sync-success`. Docker healthchecks mark a tier unhealthy when its marker goes stale beyond `BACKUP_SCHEDULED_HEALTHCHECK_DAYS` (default 8) or `BACKUP_SYNC_HEALTHCHECK_MINUTES` (default 30), or, for `backup-watch`, when the inotify listener process dies. Until `RCLONE_REMOTE` and the rclone config are set up, `backup-sync` reports unhealthy by design.

## Commands

```sh
docker compose exec backup-watch sh /scripts/backup-local.sh watch
docker compose exec backup-scheduled sh /scripts/backup-local.sh scheduled
docker compose exec backup-sync sh /scripts/backup-sync.sh

ls -lh backups
docker compose ps
docker compose logs -f backup-watch backup-scheduled backup-sync
```
