#!/usr/bin/env bash
# Manage Docker Compose projects through a small action-first interface.

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

usage() {
    cat <<EOF
Usage:
  $PROGRAM_NAME [GLOBAL_OPTIONS] [COMPOSE_OPTIONS] ACTION [ARGS...]

Manage the Compose project selected by the current directory or by explicit
Compose options. All project actions use Docker Compose internally.

Global options (must precede Compose options and the action):
  --dry-run       Print commands without running them
  --verbose, -v   Print commands before running them
  --no-color      Disable colored diagnostic output
  --force         Skip this script's destructive-action confirmation
  --help, -h      Show this help

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

Actions:
  start [ARGS...]                 Build, create, and start services
  rebuild [ARGS...]               Rebuild and force-recreate services
  stop [ARGS...]                  Stop services without removing them
  restart [ARGS...]               Restart services
  status [ARGS...]                Show all service containers
  logs [ARGS...]                  Show service logs
  shell SERVICE [COMMAND...]      Start a service and open a shell or command
  exec [OPTIONS] SERVICE COMMAND  Run a command in a running service
  run [OPTIONS] SERVICE [COMMAND] Build and run a disposable service container
  build [ARGS...]                 Build services
  pull [ARGS...]                  Pull service images
  config [ARGS...]                Render or validate the Compose configuration
  remove [SERVICE...]             Stop and remove a project or selected services
  cleanup                         Remove all unused Docker data globally

Examples:
  $PROGRAM_NAME start
  $PROGRAM_NAME shell app
  $PROGRAM_NAME rebuild app
  $PROGRAM_NAME run app bash
  $PROGRAM_NAME -f environments/app/compose.yml status
  $PROGRAM_NAME remove
  $PROGRAM_NAME --force cleanup

'remove' preserves images and volumes. 'cleanup' permanently removes stopped
containers and all Docker data unused by running containers. It is the only
action that uses Docker-wide commands because Compose cannot prune resources
across projects. On Ubuntu/Linux and macOS, standalone project actions forward
a detected SSH agent; set DOCKER_SSH_AUTH_SOCK and, when needed,
DOCKER_SSH_AUTH_GID to override its source path and socket group.
EOF
}

action_usage_error() {
    error "Missing arguments for '$1'."
    usage >&2
    return 2
}

require_arg_count() {
    local action=$1
    local minimum=$2
    local actual=$3
    if [ "$actual" -lt "$minimum" ]; then
        action_usage_error "$action"
        return $?
    fi
    return 0
}

ensure_docker_cli() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker CLI was not found in PATH. Install Docker and try again."
        return 127
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

run_docker() {
    if [ "$DRY_RUN" -eq 0 ]; then
        ensure_docker || return $?
    fi
    execute_command docker "$@"
}

COMPOSE_OPTIONS=()
run_compose() {
    if [ "$DRY_RUN" -eq 0 ]; then
        ensure_compose || return $?
    fi
    execute_command docker compose "${COMPOSE_OPTIONS[@]}" "$@"
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

validate_service_names() {
    local service
    for service in "$@"; do
        case "$service" in
            -*)
                error "'remove' accepts service names only; unsupported option: $service"
                return 2
                ;;
        esac
    done
    return 0
}

COMPOSE_ACTION=""
COMPOSE_ARGS=()
SSH_AGENT_OVERLAY=""
SSH_AGENT_BASE_FILE=""
SSH_AGENT_DEFAULT_OVERRIDE=""
SSH_AGENT_ERROR=""
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
            --all-resources|--compatibility)
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
                usage >&2
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

discover_ssh_agent_overlay() {
    local compose_file=""
    local project_directory=""
    local search_directory=""
    local parent_directory=""
    local option
    local index=0

    while [ "$index" -lt "${#COMPOSE_OPTIONS[@]}" ]; do
        option=${COMPOSE_OPTIONS[$index]}
        case "$option" in
            -f|--file)
                index=$((index + 1))
                if [ -z "$compose_file" ]; then
                    compose_file=${COMPOSE_OPTIONS[$index]}
                fi
                ;;
            --file=*)
                if [ -z "$compose_file" ]; then
                    compose_file=${option#*=}
                fi
                ;;
            --project-directory)
                index=$((index + 1))
                project_directory=${COMPOSE_OPTIONS[$index]}
                ;;
            --project-directory=*)
                project_directory=${option#*=}
                ;;
        esac
        index=$((index + 1))
    done

    SSH_AGENT_BASE_FILE=""
    SSH_AGENT_DEFAULT_OVERRIDE=""
    if [ -n "$compose_file" ]; then
        if [ "$compose_file" = "-" ]; then
            return 1
        fi
        SSH_AGENT_BASE_FILE=$compose_file
    else
        if [ -z "$project_directory" ]; then
            project_directory=.
        fi
        search_directory=$(cd "$project_directory" 2>/dev/null && pwd) || return 1
        while [ -z "$SSH_AGENT_BASE_FILE" ]; do
            for option in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
                if [ -f "$search_directory/$option" ]; then
                    SSH_AGENT_BASE_FILE="$search_directory/$option"
                    break
                fi
            done
            [ -n "$SSH_AGENT_BASE_FILE" ] && break

            parent_directory=$(dirname "$search_directory")
            [ "$parent_directory" = "$search_directory" ] && break
            search_directory=$parent_directory
        done
    fi

    if [ -z "$SSH_AGENT_BASE_FILE" ]; then
        return 1
    fi

    search_directory=$(dirname "$SSH_AGENT_BASE_FILE")
    if [ -z "$compose_file" ]; then
        for option in compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
            if [ -f "$search_directory/$option" ]; then
                SSH_AGENT_DEFAULT_OVERRIDE="$search_directory/$option"
                break
            fi
        done
    fi

    SSH_AGENT_OVERLAY="$search_directory/docker-compose.ssh-agent.yml"
    [ -f "$SSH_AGENT_OVERLAY" ]
}

compose_options_include_file() {
    local expected=$1
    local option
    local index=0

    while [ "$index" -lt "${#COMPOSE_OPTIONS[@]}" ]; do
        option=${COMPOSE_OPTIONS[$index]}
        case "$option" in
            -f|--file)
                index=$((index + 1))
                if [ "${COMPOSE_OPTIONS[$index]}" = "$expected" ]; then
                    return 0
                fi
                ;;
            --file=*)
                if [ "${option#*=}" = "$expected" ]; then
                    return 0
                fi
                ;;
        esac
        index=$((index + 1))
    done
    return 1
}

read_socket_gid() {
    local socket_path=$1
    local socket_gid

    socket_gid=$(stat -c '%g' "$socket_path" 2>/dev/null) \
        || socket_gid=$(stat -f '%g' "$socket_path" 2>/dev/null) \
        || return 1
    case "$socket_gid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s' "$socket_gid"
}

validate_ssh_agent_gid() {
    case "${DOCKER_SSH_AUTH_GID:-}" in
        ''|*[!0-9]*)
            SSH_AGENT_ERROR="DOCKER_SSH_AUTH_GID must be a numeric group ID."
            return 1
            ;;
    esac
    return 0
}

resolve_ssh_agent_socket() {
    local host_os

    SSH_AGENT_ERROR=""
    if [ -n "${DOCKER_SSH_AUTH_SOCK:-}" ]; then
        if [ -n "${DOCKER_SSH_AUTH_GID:-}" ]; then
            validate_ssh_agent_gid
            return $?
        fi

        host_os=$(uname -s 2>/dev/null) || host_os=""
        if [ "$host_os" = "Darwin" ] && [ "$DOCKER_SSH_AUTH_SOCK" = "/run/host-services/ssh-auth.sock" ]; then
            DOCKER_SSH_AUTH_GID=0
        elif [ -S "$DOCKER_SSH_AUTH_SOCK" ]; then
            DOCKER_SSH_AUTH_GID=$(read_socket_gid "$DOCKER_SSH_AUTH_SOCK") || {
                SSH_AGENT_ERROR="Unable to determine the SSH-agent socket group; set DOCKER_SSH_AUTH_GID explicitly."
                return 1
            }
        else
            SSH_AGENT_ERROR="The overridden SSH-agent socket is not locally inspectable; set DOCKER_SSH_AUTH_GID explicitly."
            return 1
        fi
        export DOCKER_SSH_AUTH_GID
        return 0
    fi

    host_os=$(uname -s 2>/dev/null) || host_os=""
    case "$host_os" in
        Darwin)
            if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
                DOCKER_SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
                DOCKER_SSH_AUTH_GID=0
                export DOCKER_SSH_AUTH_SOCK DOCKER_SSH_AUTH_GID
                return 0
            fi
            SSH_AGENT_ERROR="SSH_AUTH_SOCK is not set to a usable macOS agent socket."
            ;;
        Linux)
            if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
                DOCKER_SSH_AUTH_SOCK=$SSH_AUTH_SOCK
                DOCKER_SSH_AUTH_GID=$(read_socket_gid "$SSH_AUTH_SOCK") || {
                    SSH_AGENT_ERROR="Unable to determine the Linux SSH-agent socket group."
                    return 1
                }
                export DOCKER_SSH_AUTH_SOCK DOCKER_SSH_AUTH_GID
                return 0
            fi
            SSH_AGENT_ERROR="SSH_AUTH_SOCK is not set to a usable Linux agent socket."
            ;;
        *)
            SSH_AGENT_ERROR="SSH-agent forwarding is supported only on Ubuntu/Linux and macOS."
            ;;
    esac
    return 1
}

action_creates_containers() {
    case "$1" in
        start|rebuild|shell|run) return 0 ;;
        *) return 1 ;;
    esac
}

configure_ssh_agent() {
    local action=$1
    local explicit_socket=0

    if [ -n "${DOCKER_SSH_AUTH_SOCK:-}" ]; then
        explicit_socket=1
    fi

    discover_ssh_agent_overlay || return 0
    if ! resolve_ssh_agent_socket; then
        if [ "$explicit_socket" -eq 1 ]; then
            error "$SSH_AGENT_ERROR"
            return 2
        fi
        if action_creates_containers "$action"; then
            warn "$SSH_AGENT_ERROR Continuing without SSH-agent forwarding. Start an agent, load a key with ssh-add, and rerun the command for private Git access."
        fi
        return 0
    fi

    if ! compose_options_include_file "$SSH_AGENT_BASE_FILE"; then
        COMPOSE_OPTIONS+=(-f "$SSH_AGENT_BASE_FILE")
    fi
    if [ -n "$SSH_AGENT_DEFAULT_OVERRIDE" ] && ! compose_options_include_file "$SSH_AGENT_DEFAULT_OVERRIDE"; then
        COMPOSE_OPTIONS+=(-f "$SSH_AGENT_DEFAULT_OVERRIDE")
    fi
    if ! compose_options_include_file "$SSH_AGENT_OVERLAY"; then
        COMPOSE_OPTIONS+=(-f "$SSH_AGENT_OVERLAY")
    fi
    debug "Forwarding SSH agent through Compose overlay: $SSH_AGENT_OVERLAY (socket group $DOCKER_SSH_AUTH_GID)"
}

compose_shell() {
    require_arg_count shell 1 "$#" || return $?
    local service=$1
    shift
    local no_tty=()
    local bash_status
    local sh_status

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        no_tty=(-T)
    fi

    run_compose up -d --build "$service" || return $?

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$#" -gt 0 ]; then
            run_compose exec "${no_tty[@]}" "$service" "$@"
        else
            info "Dry run: default shell resolution would try bash, then sh."
            run_compose exec "${no_tty[@]}" "$service" bash
        fi
        return $?
    fi

    if [ "$#" -gt 0 ]; then
        run_compose exec "${no_tty[@]}" "$service" "$@"
        return $?
    fi

    docker compose "${COMPOSE_OPTIONS[@]}" exec -T "$service" bash -c ':' >/dev/null 2>&1
    bash_status=$?
    if [ "$bash_status" -eq 0 ]; then
        run_compose exec "${no_tty[@]}" "$service" bash
        return $?
    fi

    docker compose "${COMPOSE_OPTIONS[@]}" exec -T "$service" sh -c ':' >/dev/null 2>&1
    sh_status=$?
    if [ "$sh_status" -eq 0 ]; then
        run_compose exec "${no_tty[@]}" "$service" sh
        return $?
    fi

    error "Unable to resolve a shell for Compose service '$service' (bash probe exited $bash_status; sh probe exited $sh_status). Supply an executable explicitly."
    return "$sh_status"
}

handle_remove() {
    validate_service_names "$@" || return $?

    if [ "$#" -eq 0 ]; then
        confirm_destructive "Stop and remove the selected Compose project? Images and volumes will be preserved." || return $?
        run_compose down --remove-orphans
        return $?
    fi

    local services
    services=$(join_targets "$@")
    confirm_destructive "Stop and remove Compose service(s): $services? Images and volumes will be preserved." || return $?
    run_compose rm --stop --force "$@"
}

handle_cleanup() {
    if [ "${#COMPOSE_OPTIONS[@]}" -ne 0 ]; then
        error "'cleanup' is Docker-wide and does not accept Compose options."
        return 2
    fi
    if [ "$#" -ne 0 ]; then
        error "'cleanup' does not accept arguments."
        return 2
    fi

    confirm_destructive "Remove stopped containers and all Docker images, networks, volumes, and build cache unused by running containers?" || return $?
    run_docker system prune --all --volumes --force || return $?
    run_docker volume prune --all --force
}

handle_action() {
    local action=$1
    shift

    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        return 0
    fi

    case "$action" in
        start|rebuild|stop|restart|status|logs|shell|exec|run|build|pull|config|remove)
            configure_ssh_agent "$action" || return $?
            ;;
    esac

    case "$action" in
        start)
            run_compose up -d --build "$@"
            ;;
        rebuild)
            run_compose up -d --build --force-recreate "$@"
            ;;
        stop|restart|build|pull|config|logs)
            run_compose "$action" "$@"
            ;;
        status)
            run_compose ps --all "$@"
            ;;
        shell)
            compose_shell "$@"
            ;;
        exec)
            require_arg_count exec 2 "$#" || return $?
            run_compose exec "$@"
            ;;
        run)
            require_arg_count run 1 "$#" || return $?
            run_compose run --rm --build "$@"
            ;;
        remove)
            handle_remove "$@"
            ;;
        cleanup)
            handle_cleanup "$@"
            ;;
        container|image|compose)
            error "The '$action' resource group was removed. Use a top-level action; run '$PROGRAM_NAME --help'."
            return 2
            ;;
        *)
            error "Unknown action: $action"
            usage >&2
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
        --) break ;;
        *) break ;;
    esac
done

init_colors
parse_compose_options "$@" || exit $?

if [ -z "$COMPOSE_ACTION" ]; then
    error "An action is required."
    usage >&2
    exit 2
fi

if [ "$COMPOSE_ACTION" = "--help" ] || [ "$COMPOSE_ACTION" = "-h" ] || [ "$COMPOSE_ACTION" = "help" ]; then
    usage
    exit 0
fi

debug "Action: $COMPOSE_ACTION"
handle_action "$COMPOSE_ACTION" "${COMPOSE_ARGS[@]}"
exit $?
