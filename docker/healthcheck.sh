#!/bin/sh
set -eu

host="${HEALTHCHECK_HOST:-127.0.0.1}"
port="${HEALTHCHECK_PORT:-25565}"
timeout="${HEALTHCHECK_TIMEOUT:-3}"

nc -z -w "$timeout" "$host" "$port"
