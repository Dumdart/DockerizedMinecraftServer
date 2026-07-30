#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
lock_file="${LOCK_FILE:-$project_dir/versions.lock.json}"
manifest_url="${VERSION_MANIFEST_URL:-https://piston-meta.mojang.com/mc/game/version_manifest_v2.json}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

curl --fail --location --show-error --silent \
    --retry 3 --retry-all-errors \
    --output "$work_dir/manifest.json" "$manifest_url"

jq -e '
    type == "object"
    and (.selected | type == "string")
    and (.versions | type == "object" and length > 0)
    and (.versions[.selected] != null)
' "$lock_file" >/dev/null

jq -r '.versions | keys[]' "$lock_file" | while IFS= read -r version; do
    metadata_url="$(
        jq -er --arg version "$version" \
            '.versions[] | select(.id == $version) | .url' "$work_dir/manifest.json"
    )" || {
        printf 'Minecraft version is absent from Mojang manifest: %s\n' "$version" >&2
        exit 1
    }

    curl --fail --location --show-error --silent \
        --retry 3 --retry-all-errors \
        --output "$work_dir/version.json" "$metadata_url"

    locked_url="$(jq -er --arg version "$version" '.versions[$version].url' "$lock_file")"
    locked_sha1="$(jq -er --arg version "$version" '.versions[$version].sha1' "$lock_file")"
    official_url="$(jq -er '.downloads.server.url' "$work_dir/version.json")"
    official_sha1="$(jq -er '.downloads.server.sha1' "$work_dir/version.json")"

    [ "$locked_url" = "$official_url" ] || {
        printf 'Download URL mismatch for Minecraft %s\n' "$version" >&2
        exit 1
    }
    [ "$locked_sha1" = "$official_sha1" ] || {
        printf 'SHA-1 mismatch for Minecraft %s\n' "$version" >&2
        exit 1
    }
    printf 'Verified Minecraft %s lock metadata\n' "$version"
done

trap - EXIT HUP INT TERM
rm -rf "$work_dir"
