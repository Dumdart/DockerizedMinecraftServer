LOCK_FILE=/opt/minecraft/versions.lock.json

version_data="$(jq -e --arg version "$MINECRAFT_VERSION"  '.versions[$version]' "$LOCK_FILE")" || {
    echo "Unsupported Minecraft version: $MINECRAFT_VERSION" >&2
    exit 1
}
