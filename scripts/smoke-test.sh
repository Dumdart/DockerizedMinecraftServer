#!/bin/sh
set -eu

image="${1:-dockerized-minecraft-server:test}"
container_name="minecraft-smoke-$$"
volume_name="minecraft-smoke-data-$$"

# Check cleanup is invoked indirectly by the trap below.
# shellcheck disable=SC2317
cleanup() {
    docker rm --force "$container_name" >/dev/null 2>&1 || true
    docker volume rm "$volume_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

if docker run --rm "$image" >/tmp/minecraft-eula-test.log 2>&1; then
    printf 'Image started without explicit EULA acceptance\n' >&2
    exit 1
fi
grep -q 'EULA must be set to exactly TRUE' /tmp/minecraft-eula-test.log

if docker run --rm \
    --env EULA=TRUE \
    --env MINECRAFT_VERSION=not-locked \
    "$image" >/tmp/minecraft-version-test.log 2>&1; then
    printf 'Image started with an unsupported Minecraft version\n' >&2
    exit 1
fi
grep -q 'not the repository-selected version' /tmp/minecraft-version-test.log

docker volume create "$volume_name" >/dev/null
docker run --detach \
    --name "$container_name" \
    --env EULA=TRUE \
    --env MINECRAFT_VERSION=26.2 \
    --env JAVA_XMS=1G \
    --env JAVA_XMX=1G \
    --mount "type=volume,source=$volume_name,target=/data" \
    "$image" >/dev/null

attempt=0
while [ "$attempt" -lt 240 ]; do
    state="$(docker inspect --format '{{.State.Status}}' "$container_name")"
    health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_name")"

    if [ "$state" != "running" ]; then
        docker logs "$container_name"
        printf 'Smoke-test server exited with state %s\n' "$state" >&2
        exit 1
    fi
    if [ "$health" = "healthy" ]; then
        docker stop --time 120 "$container_name" >/dev/null
        printf 'Minecraft first-start smoke test passed\n'
        exit 0
    fi
    if [ "$health" = "unhealthy" ]; then
        docker logs "$container_name"
        printf 'Smoke-test server became unhealthy\n' >&2
        exit 1
    fi

    attempt=$((attempt + 1))
    sleep 1
done

docker logs "$container_name"
printf 'Smoke-test server did not become healthy in 240 seconds\n' >&2
exit 1
