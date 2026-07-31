#!/bin/sh
set -eu

project_dir="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
image="${1:-dockerized-minecraft-server:test}"
project_name="minecraft-compose-smoke-$$"
override_file="$project_dir/compose.test.yaml"
logs_file=

export COMPOSE_PROJECT_NAME="$project_name"
export MINECRAFT_PROJECT_DIR="$project_dir"
export MINECRAFT_COMPOSE_OVERRIDE="$override_file"
export TEST_MINECRAFT_IMAGE="$image"

compose() {
    docker compose --project-directory "$project_dir" \
        --file "$project_dir/compose.yaml" \
        --file "$override_file" "$@"
}

control() {
    sh "$project_dir/scripts/mc-control.sh" "$@"
}

# Check cleanup removes only this test's containers, network, and named volumes.
# shellcheck disable=SC2317
cleanup() {
    if [ -n "$logs_file" ] && [ -f "$logs_file" ]; then
        rm -f "$logs_file"
    fi
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

compose config --quiet
compose up --detach --wait --wait-timeout 300

control status
control players | grep -q '"result":\[\]'
control whitelist list | grep -q '"result":\[\]'
control whitelist add Notch | grep -q '"name":"Notch"'
control whitelist remove Notch | grep -q '"result":\[\]'
control rpc minecraft:server/status '[]' | grep -q '"started":true'

# Check the scheduler releases its lock before exercising an on-demand backup.
attempt=0
while [ "$attempt" -lt 60 ]; do
    # shellcheck disable=SC2016
    if compose exec -T backup_worker sh -c \
        'set -- /backups/minecraft-*.tar.gz
        [ -f "$1" ] && [ ! -d /backups/.backup.lock ]'; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
[ "$attempt" -lt 60 ] || {
    printf 'Initial scheduled backup did not complete\n' >&2
    exit 1
}

control backup
# shellcheck disable=SC2016
compose exec -T backup_worker sh -c '
    set -- /backups/minecraft-*.tar.gz
    [ "$#" -eq 2 ]
    for archive do
        tar -tzf "$archive" >/dev/null
        if tar -tzf "$archive" \
            | grep -Eq "(^|/)(server.jar|libraries|versions|logs|.management-secret)(/|$)"; then
            printf "Excluded runtime data found in %s\n" "$archive" >&2
            exit 1
        fi
        tar -xOzf "$archive" ./server.properties \
            | grep -q "^management-server-secret=$"
    done
'

control restart
compose up --detach --wait --wait-timeout 300
control stop
[ -z "$(compose ps --quiet --status running)" ]
control start
compose up --detach --wait --wait-timeout 300

# Check the follow-mode logs control streams output until interrupted.
logs_file="$(mktemp)"
if timeout 3 sh "$project_dir/scripts/mc-control.sh" logs \
    >"$logs_file" 2>&1; then
    printf 'Logs control exited before interruption\n' >&2
    exit 1
else
    logs_status=$?
    [ "$logs_status" -eq 124 ] || exit "$logs_status"
fi
grep -q 'Done (' "$logs_file"
rm -f "$logs_file"
logs_file=

printf 'Compose runtime and control smoke test passed\n'

trap - EXIT HUP INT TERM
cleanup
