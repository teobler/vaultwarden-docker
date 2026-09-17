#!/bin/sh
set -eu

: "${DATA_DIR:=/data}"
: "${BACKUP_WATCH_DEBOUNCE:=300}"
: "${BACKUP_WATCH_MIN_INTERVAL:=3600}"
: "${BACKUP_LOG:=/logs/backup_watch.log}"
database="$DATA_DIR/db.sqlite3"
last_backup=0
throttle_logged=0

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BACKUP_LOG"
}

# BusyBox stat uses -c %Y; the -f %m fallback keeps the script runnable on macOS.
mtime_of() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

until [ -f "$database" ]; do
    log "Waiting for database at $database"
    sleep 5
done

log "Watching database changes; debounce is ${BACKUP_WATCH_DEBOUNCE}s, minimum interval ${BACKUP_WATCH_MIN_INTERVAL}s"
# SQLite runs in WAL mode: writes land in db.sqlite3-wal while db.sqlite3 stays
# untouched and Vaultwarden never closes its fd, so watching the main file for
# close_write never fires. Watch the directory and match both file names.
inotifywait -m -q -e modify,close_write,moved_to,create "$DATA_DIR" |
while read -r _directory _event _file; do
    case "$_file" in
        db.sqlite3|db.sqlite3-wal) ;;
        *) continue ;;
    esac
    now="$(date +%s)"
    if [ $((now - last_backup)) -lt "$BACKUP_WATCH_MIN_INTERVAL" ]; then
        if [ "$throttle_logged" -eq 0 ]; then
            log "Skipping backup: last watch backup was less than ${BACKUP_WATCH_MIN_INTERVAL}s ago"
            throttle_logged=1
        fi
        continue
    fi
    sleep "$BACKUP_WATCH_DEBOUNCE"
    # Live writes update the WAL file; the main database mtime stays stale.
    modified="$(mtime_of "$database-wal")"
    [ "$modified" -eq 0 ] && modified="$(mtime_of "$database")"
    now="$(date +%s)"
    [ $((now - modified)) -lt "$BACKUP_WATCH_DEBOUNCE" ] && continue
    if sh /scripts/backup-local.sh watch; then
        throttle_logged=0
    else
        log "Watch backup failed; retrying after the hourly throttle"
    fi
    last_backup="$now"
done
