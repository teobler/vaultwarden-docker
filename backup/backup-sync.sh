#!/bin/sh
set -eu

: "${RCLONE_REMOTE:?RCLONE_REMOTE must name an rclone remote and destination path}"
: "${DATA_DIR:=/backup}"
: "${BACKUP_LOG:=/logs/backup_sync.log}"
config=/config/rclone/rclone.conf

log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BACKUP_LOG"
}

[ -f "$config" ] || { log "rclone config not found at $config"; exit 1; }
log "Synchronizing $DATA_DIR to $RCLONE_REMOTE"
rclone sync "$DATA_DIR" "$RCLONE_REMOTE" --config "$config" --transfers 4 --checksum
log "Synchronization completed"
