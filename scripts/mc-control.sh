#!/bin/sh
set -eu

project_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
compose() {
    docker compose --project-directory "$project_dir" \
        --file "$project_dir/compose.yaml" "$@"
}

usage() {
    cat >&2 <<'EOF'
usage: ./scripts/mc-control.sh COMMAND [ARGUMENTS]

Lifecycle:
  status | start | stop | restart | logs

Administration:
  players
  whitelist list
  whitelist add PLAYER
  whitelist remove PLAYER
  backup
  rpc METHOD [PARAMS_JSON]
EOF
    exit 64
}

manage() {
    method="$1"
    params="${2:-{}}"
    compose exec -T minecraft minecraft-manage "$method" "$params"
}

validate_player_name() {
    player_name="$1"
    case "$player_name" in
        ''|*[!A-Za-z0-9_]*)
            printf 'Invalid Minecraft player name: %s\n' "$player_name" >&2
            exit 64
            ;;
    esac
    [ "${#player_name}" -le 16 ] || {
        printf 'Minecraft player names cannot exceed 16 characters\n' >&2
        exit 64
    }
}

command="${1:-}"
case "$command" in
    status)
        compose ps
        ;;
    start)
        compose up -d
        ;;
    stop)
        compose stop
        ;;
    restart)
        compose up -d --force-recreate minecraft
        ;;
    logs)
        compose logs --follow minecraft
        ;;
    players)
        manage minecraft:players '{}'
        ;;
    whitelist)
        action="${2:-}"
        case "$action" in
            list)
                manage minecraft:allowlist '{}'
                ;;
            add|remove)
                player_name="${3:-}"
                validate_player_name "$player_name"
                manage "minecraft:allowlist/$action" \
                    "{\"$action\":[{\"name\":\"$player_name\"}]}"
                ;;
            *)
                usage
                ;;
        esac
        ;;
    backup)
        compose exec -T backup_worker minecraft-backup once
        ;;
    rpc)
        [ -n "${2:-}" ] || usage
        manage "$2" "${3:-{}}"
        ;;
    *)
        usage
        ;;
esac
