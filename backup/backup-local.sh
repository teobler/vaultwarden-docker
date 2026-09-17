#!/bin/sh
set -eu

kind="${1:?backup type is required}"
: "${DATA_DIR:=/data}"
: "${BACKUP_DIR:=/backup}"
: "${BACKUP_LOG:=/logs/backup.log}"

case "$kind" in
    watch) retention="${BACKUP_WATCH_RETENTION:=15}" ;;
    scheduled) retention="${BACKUP_SCHEDULED_RETENTION:=5}" ;;
    *) printf 'Unknown backup type: %s\n' "$kind" >&2; exit 64 ;;
esac

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BACKUP_LOG"
}

if [ ! -f "$DATA_DIR/db.sqlite3" ]; then
    log "Database not found at $DATA_DIR/db.sqlite3; skipping backup"
    exit 0
fi

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
stage="$(mktemp -d)"
temporary="$BACKUP_DIR/.${kind}_vaultwarden_${timestamp}.tar.gz"
archive="$BACKUP_DIR/${kind}_vaultwarden_${timestamp}.tar.gz"
trap 'rm -rf "$stage" "$temporary"' EXIT INT TERM

# SQLite online backup avoids copying an inconsistent live database.
sqlite3 "$DATA_DIR/db.sqlite3" ".backup '${stage}/db.sqlite3'"
for item in attachments sends icon_cache rsa_key.pem rsa_key.pub; do
    [ -e "$DATA_DIR/$item" ] && cp -a "$DATA_DIR/$item" "$stage/"
done
tar -C "$stage" -czf "$temporary" .
mv "$temporary" "$archive"
# Dot-file marker consumed by the compose healthcheck; retention only globs
# "${kind}_vaultwarden_*.tar.gz", so this survives pruning.
touch "$BACKUP_DIR/.last-$kind-success"
log "Created $archive"

cd "$BACKUP_DIR"
ls -1t "${kind}_vaultwarden_"*.tar.gz 2>/dev/null | tail -n "+$((retention + 1))" | xargs -r rm -f
log "Retention complete; keeping $retention $kind backups"
