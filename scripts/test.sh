#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

for script in docker/*.sh scripts/*.sh; do
    sh -n "$script"
done
printf 'Shell syntax checks passed\n'

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck docker/*.sh scripts/*.sh
    printf 'ShellCheck passed\n'
else
    printf 'ShellCheck is not installed; syntax checks still ran\n'
fi

if command -v jq >/dev/null 2>&1; then
    jq -e '
        type == "object"
        and (.selected | type == "string")
        and (.versions | type == "object" and length > 0)
        and (.versions[.selected] != null)
        and all(
            .versions[];
            (.url | type == "string" and startswith("https://piston-data.mojang.com/"))
            and (.sha1 | test("^[0-9a-f]{40}$"))
        )
    ' versions.lock.json >/dev/null
    printf 'Version lock structure passed\n'
fi

if command -v javac >/dev/null 2>&1; then
    classes_dir="$project_dir/.test-classes.$$"
    mkdir "$classes_dir"
    trap 'rm -rf "$classes_dir"' EXIT HUP INT TERM
    javac -d "$classes_dir" docker/ManagementCommand.java
    rm -rf "$classes_dir"
    trap - EXIT HUP INT TERM
    printf 'Management client compilation passed\n'
fi

if command -v docker >/dev/null 2>&1; then
    docker compose --file compose.yaml config --quiet
    printf 'Compose validation passed\n'
fi

if [ "${1:-}" = "--docker" ]; then
    docker build --tag dockerized-minecraft-server:test .
    printf 'Docker image build passed\n'
fi
