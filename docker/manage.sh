#!/bin/sh
set -eu

host="${MANAGEMENT_HOST:-127.0.0.1}"
port="${MANAGEMENT_PORT:-25585}"
secret_file="${MANAGEMENT_SECRET_FILE:-/data/.management-secret}"
method="${1:-}"
params="${2:-[]}"

[ -n "$method" ] || {
    printf 'usage: minecraft-manage METHOD [PARAMS_JSON]\n' >&2
    exit 64
}
[ -r "$secret_file" ] || {
    printf 'Management secret is not readable: %s\n' "$secret_file" >&2
    exit 1
}

exec java -cp /opt/minecraft/tools ManagementCommand \
    "ws://$host:$port" "$secret_file" "$method" "$params"
