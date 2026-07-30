#!/bin/sh
set -eu

host="${HEALTHCHECK_HOST:-127.0.0.1}"
port="${HEALTHCHECK_PORT:-25565}"
timeout="${HEALTHCHECK_TIMEOUT:-3}"

nc -z -w "$timeout" "$host" "$port" \
    || {
        printf 'Minecraft is not accepting connections on %s:%s\n' "$host" "$port" >&2
        exit 1
    }
