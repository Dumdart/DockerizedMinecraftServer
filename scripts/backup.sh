#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-48}"
BACKUP_INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-1800}"
MANAGEMENT_HOST="${MANAGEMENT_HOST:-minecraft}"
MANAGEMENT_PORT="${MANAGEMENT_PORT:-25585}"
MANAGEMENT_SECRET_FILE="${MANAGEMENT_SECRET_FILE:-$DATA_DIR/.management-secret}"

saving_disabled=false
work_dir=
lock_dir=

log() {
    printf '%s\n' "$*"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

manage() {
    MANAGEMENT_HOST="$MANAGEMENT_HOST" \
    MANAGEMENT_PORT="$MANAGEMENT_PORT" \
    MANAGEMENT_SECRET_FILE="$MANAGEMENT_SECRET_FILE" \
        minecraft-manage "$1" "$2" >/dev/null
}

validate_non_negative_integer() {
    name="$1"
    value="$2"

    case "$value" in
        ''|*[!0-9]*)
            fail "$name must be a non-negative integer"
            ;;
    esac
}

cleanup() {
    exit_status=$?
    trap - EXIT HUP INT TERM

    # Check automatic saving is restored after every failure path.
    if [ "$saving_disabled" = true ]; then
        log "Restoring automatic saving after backup failure..."
        if ! manage minecraft:serversettings/autosave/set '{"enable":true}'; then
            printf 'Error: failed to restore automatic saving\n' >&2
            exit_status=1
        fi
    fi

    if [ -n "$work_dir" ] && [ -d "$work_dir" ]; then
        rm -rf -- "$work_dir"
    fi

    if [ -n "$lock_dir" ] && [ -d "$lock_dir" ]; then
        rmdir -- "$lock_dir"
    fi

    exit "$exit_status"
}

create_backup() {
    [ -d "$DATA_DIR" ] || fail "data directory does not exist: $DATA_DIR"

    [ -r "$MANAGEMENT_SECRET_FILE" ] \
        || fail "management secret is not readable: $MANAGEMENT_SECRET_FILE"

    validate_non_negative_integer "BACKUP_RETENTION" "$BACKUP_RETENTION"
    mkdir -p -- "$BACKUP_DIR"
    [ -w "$BACKUP_DIR" ] \
        || fail "backup directory is not writable by uid $(id -u): $BACKUP_DIR"

    requested_lock_dir="$BACKUP_DIR/.backup.lock"
    if ! mkdir -- "$requested_lock_dir" 2>/dev/null; then
        fail "another backup appears to be running ($requested_lock_dir exists)"
    fi
    lock_dir="$requested_lock_dir"

    work_dir="$(mktemp -d "$BACKUP_DIR/.backup-work.XXXXXX")"
    snapshot_dir="$work_dir/data"
    snapshot_tar="$work_dir/snapshot.tar"
    mkdir -- "$snapshot_dir"

    log "Disabling automatic saving..."
    manage minecraft:serversettings/autosave/set '{"enable":false}'
    saving_disabled=true

    log "Flushing Minecraft state to disk..."
    manage minecraft:server/save '{"flush":true}'

    log "Creating a frozen staging snapshot..."
    tar -cf "$snapshot_tar" \
        --exclude='./libraries' \
        --exclude='./logs' \
        --exclude='./server.jar' \
        --exclude='./versions' \
        --exclude='./.management-secret' \
        --exclude='./.server.jar.download' \
        -C "$DATA_DIR" .

    log "Restoring automatic saving..."
    manage minecraft:serversettings/autosave/set '{"enable":true}'
    saving_disabled=false

    tar -xf "$snapshot_tar" -C "$snapshot_dir"
    rm -f -- "$snapshot_tar"
    if [ -f "$snapshot_dir/server.properties" ]; then
        sed -i 's/^management-server-secret=.*/management-server-secret=/' \
            "$snapshot_dir/server.properties"
    fi

    timestamp="$(date -u '+%Y-%m-%dT%H-%M-%SZ')"
    archive_name="minecraft-$timestamp.tar.gz"
    temporary_archive="$work_dir/$archive_name"
    final_archive="$BACKUP_DIR/$archive_name"
    [ ! -e "$final_archive" ] || fail "backup already exists: $final_archive"

    log "Compressing staged data..."
    tar -czf "$temporary_archive" -C "$snapshot_dir" .

    log "Verifying archive..."
    tar -tzf "$temporary_archive" >/dev/null

    # Check the verified archive becomes visible atomically.
    mv -- "$temporary_archive" "$final_archive"

    if [ "$BACKUP_RETENTION" -gt 0 ]; then
        backup_number=0
        find "$BACKUP_DIR" -maxdepth 1 -type f -name 'minecraft-*.tar.gz' -print \
            | sort -r \
            | while IFS= read -r old_archive; do
                backup_number=$((backup_number + 1))
                if [ "$backup_number" -gt "$BACKUP_RETENTION" ]; then
                    rm -f -- "$old_archive"
                fi
            done
    fi

    rm -rf -- "$work_dir"
    work_dir=
    rmdir -- "$lock_dir"
    lock_dir=

    log "Backup created and verified: $final_archive"
}

run_loop() {
    validate_non_negative_integer "BACKUP_INTERVAL_SECONDS" "$BACKUP_INTERVAL_SECONDS"
    [ "$BACKUP_INTERVAL_SECONDS" -gt 0 ] \
        || fail "BACKUP_INTERVAL_SECONDS must be greater than zero"

    log "Backup scheduler started with a ${BACKUP_INTERVAL_SECONDS}-second interval"
    while true; do
        if ! "$0" once; then
            printf 'Error: backup attempt failed; retrying after the configured interval\n' >&2
        fi
        sleep "$BACKUP_INTERVAL_SECONDS"
    done
}

trap cleanup EXIT HUP INT TERM

case "${1:-once}" in
    once)
        create_backup
        ;;
    loop)
        trap - EXIT HUP INT TERM
        run_loop
        ;;
    *)
        fail "usage: minecraft-backup [once|loop]"
        ;;
esac

trap - EXIT HUP INT TERM
