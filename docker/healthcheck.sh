#!/bin/sh
set -eu

host="${MANAGEMENT_HOST:-127.0.0.1}"
port="${MANAGEMENT_PORT:-25585}"
secret_file="${MANAGEMENT_SECRET_FILE:-/data/.management-secret}"

response="$(
    MANAGEMENT_HOST="$host" \
    MANAGEMENT_PORT="$port" \
    MANAGEMENT_SECRET_FILE="$secret_file" \
        minecraft-manage minecraft:server/status '[]'
)" || {
    printf 'Minecraft management endpoint is not ready on %s:%s\n' "$host" "$port" >&2
    exit 1
}

printf '%s\n' "$response" | jq -e '.result.started == true' >/dev/null \
    || {
        printf 'Minecraft server has not completed startup\n' >&2
        exit 1
    }
