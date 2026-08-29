#!/usr/bin/env bash
# Manage arbitrary Docker containers, images, and explicit Compose projects.

set -o pipefail

PROGRAM_NAME=${0##*/}
DRY_RUN=0
VERBOSE=0
NO_COLOR_FLAG=0
FORCE=0
DOCKER_READY=0
COMPOSE_READY=0

RED=""
GREEN=""
YELLOW=""
CYAN=""
NC=""

init_colors() {
    if [ "$NO_COLOR_FLAG" -eq 0 ] && [ -z "${NO_COLOR:-}" ] && [ -t 2 ]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    fi
}

info()  { printf '%b%s%b\n' "$GREEN" "$*" "$NC" >&2; }
warn()  { printf '%b%s%b\n' "$YELLOW" "$*" "$NC" >&2; }
error() { printf '%b%s%b\n' "$RED" "$*" "$NC" >&2; }
debug() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf '%b%s%b\n' "$CYAN" "$*" "$NC" >&2
    fi
}

print_command() {
    local arg
    printf '%b+%b' "$CYAN" "$NC" >&2
    for arg in "$@"; do
        printf ' %q' "$arg" >&2
    done
    printf '\n' >&2
}

execute_command() {
    if [ "$DRY_RUN" -eq 1 ]; then
        print_command "$@"
        return 0
    fi

    if [ "$VERBOSE" -eq 1 ]; then
        print_command "$@"
    fi

    "$@"
}

run_command() {
    ensure_docker || return $?
    if [ "${1:-}" = "docker" ] && [ "${2:-}" = "compose" ]; then
        ensure_compose || return $?
    fi
    execute_command "$@"
}

run_help_command() {
    ensure_docker_cli || return $?
    execute_command "$@"
}

usage() {
    cat <<EOF
Usage:
  $PROGRAM_NAME [GLOBAL_OPTIONS] container ACTION [ARGS...]
  $PROGRAM_NAME [GLOBAL_OPTIONS] image ACTION [ARGS...]
  $PROGRAM_NAME [GLOBAL_OPTIONS] compose [COMPOSE_OPTIONS] ACTION [ARGS...]

Manage arbitrary Docker containers, images, and explicit Compose projects.

Global options (must precede the resource):
  --dry-run       Print commands without running them
  --verbose, -v   Print commands before running them
  --no-color      Disable colored diagnostic output
  --force         Skip this script's destructive-action confirmation
  --help, -h      Show this help

Resources:
  container       Manage containers; run '$PROGRAM_NAME container --help'
  image           Manage images; run '$PROGRAM_NAME image --help'
  compose         Manage a Compose project; run '$PROGRAM_NAME compose --help'

Examples:
  $PROGRAM_NAME container list --all
  $PROGRAM_NAME container run --name web -d -p 8080:80 nginx:alpine
  $PROGRAM_NAME container logs --follow web
  $PROGRAM_NAME container shell web
  $PROGRAM_NAME image build -t my-app:dev .
  $PROGRAM_NAME compose -f compose.yml -p demo up -d
EOF
}

container_usage() {
    cat <<EOF
Usage: $PROGRAM_NAME [GLOBAL_OPTIONS] container ACTION [ARGS...]

Actions:
  list [OPTIONS]                  List containers
  run [OPTIONS] IMAGE [COMMAND]  Create and run a container
  start TARGET...                Start stopped containers
  stop TARGET...                 Stop running containers
  restart TARGET...              Restart containers
  status TARGET...               Show concise container state
  logs [OPTIONS] TARGET          Show container logs
  shell TARGET [COMMAND...]      Open a shell or run an interactive command
  exec [OPTIONS] TARGET COMMAND  Run a command in a container
  inspect TARGET...              Display detailed container information
  stats [OPTIONS] TARGET...      Display resource usage
  remove [OPTIONS] TARGET...     Remove containers after confirmation
  prune [OPTIONS]                Remove stopped containers after confirmation

Except for 'status' and 'shell', action arguments are forwarded to the
corresponding 'docker container' command unchanged. 'remove' maps to 'rm'.
EOF
}

image_usage() {
    cat <<EOF
Usage: $PROGRAM_NAME [GLOBAL_OPTIONS] image ACTION [ARGS...]

Actions:
  list [OPTIONS]                 List images
  build [OPTIONS] CONTEXT        Build an image
  pull [OPTIONS] IMAGE           Pull an image
  tag SOURCE TARGET              Tag an image
  inspect IMAGE...               Display detailed image information
  history [OPTIONS] IMAGE        Show image history
  remove [OPTIONS] IMAGE...      Remove images after confirmation
  prune [OPTIONS]                Remove eligible images after confirmation

Action arguments are forwarded to the corresponding 'docker image' command
unchanged. 'remove' maps to 'rm'.
EOF
}

compose_usage() {
    cat <<EOF
Usage: $PROGRAM_NAME [GLOBAL_OPTIONS] compose [COMPOSE_OPTIONS] ACTION [ARGS...]

Compose options (must precede the action):
  -f, --file FILE
  -p, --project-name NAME
      --profile PROFILE
      --env-file FILE
      --project-directory DIR
      --ansi MODE
      --parallel LIMIT
      --progress MODE
      --all-resources
      --compatibility
      --dry-run

Actions:
  config, up, down, build, pull, start, stop, restart, ps, logs, exec, shell

Action arguments are forwarded to 'docker compose' unchanged. 'shell' takes a
service followed by an optional command and otherwise tries bash, then sh.
Compose performs its normal file discovery when --file is omitted.
EOF
}

action_usage_error() {
    error "Missing arguments for '$1 $2'."
    case "$1" in
        container) container_usage >&2 ;;
        image) image_usage >&2 ;;
        compose) compose_usage >&2 ;;
    esac
    return 2
}

require_arg_count() {
    local resource=$1
    local action=$2
    local minimum=$3
    local actual=$4
    if [ "$actual" -lt "$minimum" ]; then
        action_usage_error "$resource" "$action"
        return $?
    fi
    return 0
}

ensure_docker() {
    ensure_docker_cli || return $?

    if [ "$DRY_RUN" -eq 1 ] || [ "$DOCKER_READY" -eq 1 ]; then
        return 0
    fi

    docker info >/dev/null 2>&1
    local status=$?
    if [ "$status" -ne 0 ]; then
        error "Cannot access the Docker daemon. Start Docker and verify your current context and permissions."
        return "$status"
    fi
    DOCKER_READY=1
    return 0
}

ensure_docker_cli() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker CLI was not found in PATH. Install Docker and try again."
        return 127
    fi
    return 0
}

ensure_compose() {
    ensure_docker || return $?

    if [ "$DRY_RUN" -eq 1 ] || [ "$COMPOSE_READY" -eq 1 ]; then
        return 0
    fi

    docker compose version >/dev/null 2>&1
    local status=$?
    if [ "$status" -ne 0 ]; then
        error "Docker Compose v2 is unavailable. Install or enable the Docker Compose plugin."
        return "$status"
    fi
    COMPOSE_READY=1
    return 0
}

confirm_destructive() {
    local description=$1
    local response

    if [ "$DRY_RUN" -eq 1 ]; then
        debug "Skipping confirmation because dry-run mode cannot modify Docker resources."
        return 0
    fi

    if [ "$FORCE" -eq 1 ]; then
        debug "Skipping confirmation because global --force was supplied."
        return 0
    fi

    if [ ! -t 0 ]; then
        error "$description requires confirmation. Re-run with global --force in a non-interactive session."
        return 2
    fi

    printf '%b%s [y/N]: %b' "$RED" "$description" "$NC" >&2
    if ! IFS= read -r response; then
        error "Unable to read confirmation."
        return 2
    fi

    case "$response" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) warn "Cancelled."; return 1 ;;
    esac
}

REMOVE_TARGETS=()
collect_remove_targets() {
    local resource=$1
    shift
    local after_separator=0
    local skip_value=0
    local arg
    REMOVE_TARGETS=()

    for arg in "$@"; do
        if [ "$skip_value" -eq 1 ]; then
            skip_value=0
            continue
        fi
        if [ "$after_separator" -eq 1 ]; then
            REMOVE_TARGETS+=("$arg")
            continue
        fi
        case "$arg" in
            --) after_separator=1 ;;
            --platform)
                if [ "$resource" = "image" ]; then
                    skip_value=1
                fi
                ;;
            --platform=*) ;;
            -*) ;;
            *) REMOVE_TARGETS+=("$arg") ;;
        esac
    done
}

join_targets() {
    local result=""
    local target
    for target in "$@"; do
        if [ -n "$result" ]; then
            result="$result, "
        fi
        result="$result$target"
    done
    printf '%s' "$result"
}

INTERACTIVE_FLAGS=()
interactive_exec_flags() {
    INTERACTIVE_FLAGS=(-i)
    if [ -t 0 ] && [ -t 1 ]; then
        INTERACTIVE_FLAGS=(-it)
    fi
}

container_shell() {
    require_arg_count container shell 1 "$#" || return $?
    local target=$1
    shift
    local state
    local status

    interactive_exec_flags
    ensure_docker || return $?

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$#" -gt 0 ]; then
            run_command docker container exec "${INTERACTIVE_FLAGS[@]}" "$target" "$@"
        else
            info "Dry run: default shell resolution would try bash, then sh."
            run_command docker container exec "${INTERACTIVE_FLAGS[@]}" "$target" bash
        fi
        return $?
    fi

    state=$(docker container inspect --format '{{.State.Running}}' "$target" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ]; then
        error "Container '$target' does not exist or cannot be inspected."
        return "$status"
    fi
    if [ "$state" != "true" ]; then
        error "Container '$target' is not running. Start it before opening a shell."
        return 1
    fi

    if [ "$#" -gt 0 ]; then
        run_command docker container exec "${INTERACTIVE_FLAGS[@]}" "$target" "$@"
        return $?
    fi

    if docker container exec "$target" bash -c ':' >/dev/null 2>&1; then
        run_command docker container exec "${INTERACTIVE_FLAGS[@]}" "$target" bash
    elif docker container exec "$target" sh -c ':' >/dev/null 2>&1; then
        run_command docker container exec "${INTERACTIVE_FLAGS[@]}" "$target" sh
    else
        error "Container '$target' has neither bash nor sh. Supply an executable explicitly."
        return 1
    fi
}

handle_container() {
    local action=${1:-}
    if [ -z "$action" ] || [ "$action" = "--help" ] || [ "$action" = "-h" ] || [ "$action" = "help" ]; then
        container_usage
        return 0
    fi
    shift

    if [ "${1:-}" = "--help" ]; then
        case "$action" in
            list) run_help_command docker container ls "$@"; return $? ;;
            remove) run_help_command docker container rm "$@"; return $? ;;
            status|shell) container_usage; return 0 ;;
            run|start|stop|restart|logs|exec|inspect|stats|prune)
                run_help_command docker container "$action" "$@"
                return $?
                ;;
        esac
    fi

    case "$action" in
        list)
            run_command docker container ls "$@"
            ;;
        run)
            require_arg_count container run 1 "$#" || return $?
            run_command docker container run "$@"
            ;;
        start|stop|restart|inspect)
            require_arg_count container "$action" 1 "$#" || return $?
            run_command docker container "$action" "$@"
            ;;
        status)
            require_arg_count container status 1 "$#" || return $?
            run_command docker container inspect \
                --format $'{{.Name}}\t{{.State.Status}}\t{{.Config.Image}}\t{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$@"
            ;;
        logs)
            require_arg_count container logs 1 "$#" || return $?
            run_command docker container logs "$@"
            ;;
        shell)
            container_shell "$@"
            ;;
        exec)
            require_arg_count container exec 2 "$#" || return $?
            run_command docker container exec "$@"
            ;;
        stats)
            require_arg_count container stats 1 "$#" || return $?
            run_command docker container stats "$@"
            ;;
        remove)
            require_arg_count container remove 1 "$#" || return $?
            collect_remove_targets container "$@"
            if [ "${#REMOVE_TARGETS[@]}" -eq 0 ]; then
                action_usage_error container remove
                return $?
            fi
            local targets
            targets=$(join_targets "${REMOVE_TARGETS[@]}")
            confirm_destructive "Remove container(s): $targets?" || return $?
            run_command docker container rm "$@"
            ;;
        prune)
            confirm_destructive "Remove all stopped containers eligible under the supplied options?" || return $?
            run_command docker container prune --force "$@"
            ;;
        *)
            error "Unknown container action: $action"
            container_usage >&2
            return 2
            ;;
    esac
}

handle_image() {
    local action=${1:-}
    if [ -z "$action" ] || [ "$action" = "--help" ] || [ "$action" = "-h" ] || [ "$action" = "help" ]; then
        image_usage
        return 0
    fi
    shift

    if [ "${1:-}" = "--help" ]; then
        case "$action" in
            list) run_help_command docker image ls "$@"; return $? ;;
            remove) run_help_command docker image rm "$@"; return $? ;;
            build|pull|tag|inspect|history|prune)
                run_help_command docker image "$action" "$@"
                return $?
                ;;
        esac
    fi

    case "$action" in
        list)
            run_command docker image ls "$@"
            ;;
        build|pull|inspect|history)
            require_arg_count image "$action" 1 "$#" || return $?
            run_command docker image "$action" "$@"
            ;;
        tag)
            require_arg_count image tag 2 "$#" || return $?
            run_command docker image tag "$@"
            ;;
        remove)
            require_arg_count image remove 1 "$#" || return $?
            collect_remove_targets image "$@"
            if [ "${#REMOVE_TARGETS[@]}" -eq 0 ]; then
                action_usage_error image remove
                return $?
            fi
            local targets
            targets=$(join_targets "${REMOVE_TARGETS[@]}")
            confirm_destructive "Remove image(s): $targets?" || return $?
            run_command docker image rm "$@"
            ;;
        prune)
            confirm_destructive "Remove images eligible under the supplied options?" || return $?
            run_command docker image prune --force "$@"
            ;;
        *)
            error "Unknown image action: $action"
            image_usage >&2
            return 2
            ;;
    esac
}

COMPOSE_OPTIONS=()
COMPOSE_ARGS=()
COMPOSE_ACTION=""
parse_compose_options() {
    COMPOSE_OPTIONS=()
    COMPOSE_ACTION=""
    COMPOSE_ARGS=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f|--file|-p|--project-name|--profile|--env-file|--project-directory|--ansi|--parallel|--progress)
                if [ "$#" -lt 2 ]; then
                    error "Compose option '$1' requires a value."
                    return 2
                fi
                COMPOSE_OPTIONS+=("$1" "$2")
                shift 2
                ;;
            --file=*|--project-name=*|--profile=*|--env-file=*|--project-directory=*|--ansi=*|--parallel=*|--progress=*)
                COMPOSE_OPTIONS+=("$1")
                shift
                ;;
            --all-resources|--compatibility|--dry-run)
                COMPOSE_OPTIONS+=("$1")
                shift
                ;;
            --help|-h)
                COMPOSE_ACTION=$1
                shift
                COMPOSE_ARGS=("$@")
                return 0
                ;;
            --)
                shift
                if [ "$#" -gt 0 ]; then
                    COMPOSE_ACTION=$1
                    shift
                    COMPOSE_ARGS=("$@")
                fi
                return 0
                ;;
            -*)
                error "Unsupported Compose option before the action: $1"
                compose_usage >&2
                return 2
                ;;
            *)
                COMPOSE_ACTION=$1
                shift
                COMPOSE_ARGS=("$@")
                return 0
                ;;
        esac
    done
    return 0
}

compose_shell() {
    require_arg_count compose shell 1 "$#" || return $?
    local service=$1
    shift
    local no_tty=()

    ensure_compose || return $?

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        no_tty=(-T)
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$#" -gt 0 ]; then
            run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${no_tty[@]}" "$service" "$@"
        else
            info "Dry run: default shell resolution would try bash, then sh."
            run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${no_tty[@]}" "$service" bash
        fi
        return $?
    fi

    if [ "$#" -gt 0 ]; then
        run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${no_tty[@]}" "$service" "$@"
        return $?
    fi

    if docker compose "${COMPOSE_OPTIONS[@]}" exec -T "$service" bash -c ':' >/dev/null 2>&1; then
        run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${no_tty[@]}" "$service" bash
    elif docker compose "${COMPOSE_OPTIONS[@]}" exec -T "$service" sh -c ':' >/dev/null 2>&1; then
        run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${no_tty[@]}" "$service" sh
    else
        error "Compose service '$service' is not running or has neither bash nor sh."
        return 1
    fi
}

handle_compose() {
    parse_compose_options "$@" || return $?

    if [ -z "$COMPOSE_ACTION" ] || [ "$COMPOSE_ACTION" = "--help" ] || [ "$COMPOSE_ACTION" = "-h" ] || [ "$COMPOSE_ACTION" = "help" ]; then
        compose_usage
        return 0
    fi

    if [ "${COMPOSE_ARGS[0]:-}" = "--help" ]; then
        case "$COMPOSE_ACTION" in
            shell) compose_usage; return 0 ;;
            config|up|down|build|pull|start|stop|restart|ps|logs|exec)
                run_help_command docker compose "${COMPOSE_OPTIONS[@]}" "$COMPOSE_ACTION" "${COMPOSE_ARGS[@]}"
                return $?
                ;;
        esac
    fi

    case "$COMPOSE_ACTION" in
        config|up|down|build|pull|start|stop|restart|ps|logs)
            run_command docker compose "${COMPOSE_OPTIONS[@]}" "$COMPOSE_ACTION" "${COMPOSE_ARGS[@]}"
            ;;
        exec)
            require_arg_count compose exec 2 "${#COMPOSE_ARGS[@]}" || return $?
            run_command docker compose "${COMPOSE_OPTIONS[@]}" exec "${COMPOSE_ARGS[@]}"
            ;;
        shell)
            compose_shell "${COMPOSE_ARGS[@]}"
            ;;
        *)
            error "Unknown Compose action: $COMPOSE_ACTION"
            compose_usage >&2
            return 2
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --no-color) NO_COLOR_FLAG=1; shift ;;
        --force) FORCE=1; shift ;;
        --help|-h)
            init_colors
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            init_colors
            error "Unknown global option: $1"
            usage >&2
            exit 2
            ;;
        *) break ;;
    esac
done

init_colors

RESOURCE=${1:-}
if [ -z "$RESOURCE" ]; then
    usage >&2
    exit 2
fi
shift

case "$RESOURCE" in
    container|image|compose) ;;
    *)
        error "Unknown resource: $RESOURCE"
        usage >&2
        exit 2
        ;;
esac

# Resource help should remain available even when Docker is not installed.
if [ "$#" -eq 0 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "help" ]; then
    case "$RESOURCE" in
        container) container_usage ;;
        image) image_usage ;;
        compose) compose_usage ;;
    esac
    exit 0
fi

debug "Resource: $RESOURCE"

case "$RESOURCE" in
    container) handle_container "$@" ;;
    image) handle_image "$@" ;;
    compose) handle_compose "$@" ;;
esac
exit $?
