#!/bin/sh
set -eu

: "${DATA_DIR:=/data}"
: "${BACKUP_WATCH_DEBOUNCE:=300}"
: "${BACKUP_LOG:=/logs/backup_watch.log}"
database="$DATA_DIR/db.sqlite3"
last_backup=0

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BACKUP_LOG"
}

until [ -f "$database" ]; do
    log "Waiting for database at $database"
    sleep 5
done

log "Watching database changes; debounce is ${BACKUP_WATCH_DEBOUNCE}s"
while inotifywait -q -e close_write,moved_to "$database"; do
    sleep "$BACKUP_WATCH_DEBOUNCE"
    modified="$(stat -c %Y "$database" 2>/dev/null || stat -f %m "$database")"
    now="$(date +%s)"
    [ $((now - modified)) -lt "$BACKUP_WATCH_DEBOUNCE" ] && continue
    [ $((now - last_backup)) -lt 3600 ] && { log "Skipping backup: last watch backup was under one hour ago"; continue; }
    /usr/local/bin/backup-local watch
    last_backup="$now"
done
