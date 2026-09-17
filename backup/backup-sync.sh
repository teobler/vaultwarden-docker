#!/bin/sh
set -eu

: "${RCLONE_REMOTE:?RCLONE_REMOTE must name an rclone remote and destination path}"
: "${DATA_DIR:=/backup}"
: "${BACKUP_LOG:=/logs/backup_sync.log}"
: "${RCLONE_BACKUP_DIR_RETENTION:=30d}"
config=/config/rclone/rclone.conf
marker="$(dirname "$BACKUP_LOG")/.last-sync-success"

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BACKUP_LOG"
}

case "$RCLONE_REMOTE" in
    replace-with-*) log "RCLONE_REMOTE is not configured yet; skipping sync"; exit 1 ;;
esac
[ -f "$config" ] || { log "rclone config not found at $config"; exit 1; }

# Archives removed locally by retention are moved into previous/ on the remote
# instead of being deleted by the mirror sync; the exclude keeps sync from
# touching that subtree. Never add --delete-excluded here. crypt exposes no
# common hash, so comparison is by size only.
rclone sync "$DATA_DIR" "$RCLONE_REMOTE" \
    --config "$config" \
    --transfers 4 \
    --size-only \
    --backup-dir "$RCLONE_REMOTE/previous" \
    --exclude "/previous/**"
log "Synchronization completed"
touch "$marker"

# Prune aged-out versions from previous/ once it exists.
if rclone lsf "$RCLONE_REMOTE/previous" --config "$config" >/dev/null 2>&1; then
    rclone delete "$RCLONE_REMOTE/previous" --config "$config" --min-age "$RCLONE_BACKUP_DIR_RETENTION"
    log "Pruned previous/ older than $RCLONE_BACKUP_DIR_RETENTION"
fi
