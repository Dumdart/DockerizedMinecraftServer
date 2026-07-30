#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

case "$PUID:$PGID" in
    *[!0-9:]*|:*|*:)
        fail "PUID and PGID must be non-negative integers"
        ;;
esac

mkdir -p "$DATA_DIR" "$BACKUP_DIR"

# Check migrated and previously container-owned files match the runtime identity.
chown -R "$PUID:$PGID" "$DATA_DIR" "$BACKUP_DIR"

