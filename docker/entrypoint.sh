#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
LOCK_FILE="${LOCK_FILE:-/opt/minecraft/versions.lock.json}"
SERVER_JAR="${SERVER_JAR:-$DATA_DIR/server.jar}"
MANAGEMENT_SECRET_FILE="${MANAGEMENT_SECRET_FILE:-$DATA_DIR/.management-secret}"
MANAGEMENT_PORT="${MANAGEMENT_PORT:-25585}"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

set_server_property() {
    property_name="$1"
    property_value="$2"
    properties_file="$DATA_DIR/server.properties"

    if grep -q "^${property_name}=" "$properties_file" 2>/dev/null; then
        sed -i "s/^${property_name}=.*/${property_name}=${property_value}/" "$properties_file"
    else
        printf '%s=%s\n' "$property_name" "$property_value" >> "$properties_file"
    fi
}

[ "${EULA:-}" = "TRUE" ] \
    || fail "EULA must be set to exactly TRUE before downloading or starting Minecraft"
[ -r "$LOCK_FILE" ] || fail "version lock is not readable: $LOCK_FILE"
selected_version="$(jq -er '.selected' "$LOCK_FILE")" \
    || fail "version lock has no selected Minecraft version"
MINECRAFT_VERSION="${MINECRAFT_VERSION:-$selected_version}"
[ "$MINECRAFT_VERSION" = "$selected_version" ] \
    || fail "Minecraft $MINECRAFT_VERSION is not the repository-selected version $selected_version"

case "${JAVA_XMS:-2G}:${JAVA_XMX:-4G}" in
    *[!0-9kKmMgG:]*) fail "JAVA_XMS and JAVA_XMX must use JVM memory values such as 2G or 4096M" ;;
esac
case "$MANAGEMENT_PORT" in
    ''|*[!0-9]*) fail "MANAGEMENT_PORT must be an integer" ;;
esac
if [ "$MANAGEMENT_PORT" -lt 1 ] || [ "$MANAGEMENT_PORT" -gt 65535 ]; then
    fail "MANAGEMENT_PORT must be between 1 and 65535"
fi

mkdir -p "$DATA_DIR"
cd "$DATA_DIR"
[ -w "$DATA_DIR" ] || fail "data directory is not writable by uid $(id -u): $DATA_DIR"

download_url="$(
    jq -er --arg version "$MINECRAFT_VERSION" '.versions[$version].url' "$LOCK_FILE"
)" || fail "unsupported Minecraft version: $MINECRAFT_VERSION"
expected_sha1="$(
    jq -er --arg version "$MINECRAFT_VERSION" '.versions[$version].sha1' "$LOCK_FILE"
)" || fail "version lock has no SHA-1 for Minecraft $MINECRAFT_VERSION"

case "$expected_sha1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) fail "version lock contains an invalid SHA-1 for Minecraft $MINECRAFT_VERSION" ;;
esac

actual_sha1=""
if [ -f "$SERVER_JAR" ]; then
    actual_sha1="$(sha1sum "$SERVER_JAR" | awk '{print $1}')"
fi

if [ "$actual_sha1" != "$expected_sha1" ]; then
    temporary_jar="$DATA_DIR/.server.jar.download"
    trap 'rm -f "$temporary_jar"' EXIT HUP INT TERM

    printf 'Downloading Minecraft %s from Mojang...\n' "$MINECRAFT_VERSION"
    curl --fail --location --show-error --silent \
        --retry 3 --retry-all-errors \
        --output "$temporary_jar" "$download_url"

    actual_sha1="$(sha1sum "$temporary_jar" | awk '{print $1}')"
    [ "$actual_sha1" = "$expected_sha1" ] \
        || fail "server JAR checksum mismatch: expected $expected_sha1, got $actual_sha1"

    mv "$temporary_jar" "$SERVER_JAR"
    trap - EXIT HUP INT TERM
    printf 'Verified Minecraft server JAR with SHA-1 %s\n' "$expected_sha1"
else
    printf 'Using checksum-verified cached server JAR for Minecraft %s\n' "$MINECRAFT_VERSION"
fi

management_secret="${MANAGEMENT_SECRET:-}"
if [ -z "$management_secret" ] && [ -r "$MANAGEMENT_SECRET_FILE" ]; then
    IFS= read -r management_secret < "$MANAGEMENT_SECRET_FILE"
fi
if [ -z "$management_secret" ]; then
    management_secret="$(
        LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40
    )"
fi
case "$management_secret" in
    ????????????????????????????????????????) ;;
    *) fail "management secret must be exactly 40 alphanumeric characters" ;;
esac
case "$management_secret" in
    *[!A-Za-z0-9]*) fail "management secret must be exactly 40 alphanumeric characters" ;;
esac
printf '%s\n' "$management_secret" > "$MANAGEMENT_SECRET_FILE"
chmod 600 "$MANAGEMENT_SECRET_FILE"

printf 'eula=true\n' > "$DATA_DIR/eula.txt"

# Check the official management endpoint stays on the private Compose network.
set_server_property management-server-enabled true
set_server_property management-server-host 0.0.0.0
set_server_property management-server-port "$MANAGEMENT_PORT"
set_server_property management-server-secret "$management_secret"
set_server_property management-server-tls-enabled false
chmod 600 "$DATA_DIR/server.properties"

exec java \
    "-Xms${JAVA_XMS:-2G}" \
    "-Xmx${JAVA_XMX:-4G}" \
    -jar "$SERVER_JAR" "$@"
