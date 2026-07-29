#!/bin/sh
set -eu

LOCK_FILE=/opt/minecraft/versions.lock.json
SERVER_JAR=server.jar

# Validate configuration
if [ "${EULA:-}" != "TRUE" ]; then
    echo "EULA is not set to true" >&2
    exit 1
fi

if [ -z "${MINECRAFT_VERSION:-}" ]; then
    echo "MINECRAFT_VERSION is not set" >&2
    exit 1
fi

# Prepare /data
download_url="$(
    jq -er --arg version "$MINECRAFT_VERSION"  '.[$version].url' "$LOCK_FILE"
)" || {
    echo "Unsupported Minecraft version: $MINECRAFT_VERSION" >&2
    exit 1
}

expected_sha1="$(
    jq -er --arg version "$MINECRAFT_VERSION"  '.[$version].sha1' "$LOCK_FILE"
)"

actual_sha1=""

if [ -f "$SERVER_JAR" ]; then
    actual_sha1="$(sha1sum "$SERVER_JAR" | cut -d' ' -f 1)"
fi

 if [ "$actual_sha1" != "$expected_sha1" ]; then
     temporary_jar="server.temp.jar".

     echo "Downloading server.jar..."
     curl --fail --location --show-error --output "$temporary_jar" "$download_url"

     echo "Verifying SHA-1..."
     actual_sha1="$(sha1sum "$temporary_jar" | cut -d' ' -f 1)"

     if [ "$actual_sha1" != "$expected_sha1" ]; then
         rm -f "$temporary_jar"
         echo "SHA-1 mismatch: expected $expected_sha1, got $actual_sha1" >&2
         exit 1
     fi

     mv "$temporary_jar" "$SERVER_JAR"
 fi

printf 'eula=true\n' > eula.txt

exec java "-Xms${JAVA_XMS:-2G}" "-Xmx${JAVA_XMX:-4G}" -jar "$SERVER_JAR" "$@"
