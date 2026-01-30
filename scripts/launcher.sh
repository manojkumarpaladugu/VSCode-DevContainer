#!/bin/bash

###############################################################################
# Launcher Script - Bash Version
# Launch Editor Connected to Remote Host or Remote/Local Docker Container
###############################################################################

# Default Configuration
DEFAULT_HOST="Fusion"
DEFAULT_DEV_CONTAINER="/opt/workspace/dev-containers/zephyr"
DEFAULT_WORKSPACE="/opt/workspace"
DEFAULT_EDITOR="code"
SUPPORTED_EDITORS=("code" "cursor")

# Initialize variables
MODE=""
HOST="${DEFAULT_HOST}"
DEV_CONTAINER="${DEFAULT_DEV_CONTAINER}"
WORKSPACE="${DEFAULT_WORKSPACE}"
EDITOR="${DEFAULT_EDITOR}"
DRY_RUN=0
VERBOSE=0
LOG_LEVEL="INFO"

###############################################################################
# Parse Command Line Arguments
###############################################################################

if [[ $# -eq 0 ]]; then
    show_help
fi

MODE="$1"
shift

# Validate mode
case "${MODE}" in
    remote-host|remote-container|local-container)
        ;;
    *)
        log_error "Invalid mode: ${MODE}"
        show_help
        ;;
esac

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --editor)
            EDITOR="$2"
            shift 2
            ;;
        --dev-container)
            DEV_CONTAINER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --verbose)
            VERBOSE=1
            LOG_LEVEL="DEBUG"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            ;;
    esac
done

# Validate Arguments
VALID_EDITOR=0
for editor in "${SUPPORTED_EDITORS[@]}"; do
    if [[ "${EDITOR}" == "${editor}" ]]; then
        VALID_EDITOR=1
        break
    fi
done

if [[ ${VALID_EDITOR} -eq 0 ]]; then
    log_error "Unsupported editor: ${EDITOR}"
    log_error "Supported editors: ${SUPPORTED_EDITORS[*]}"
    exit 1
fi

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo "[INFO] $1"
}

log_debug() {
    if [[ "${VERBOSE}" == "1" ]]; then
        echo "[DEBUG] $1"
    fi
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_warning() {
    echo "[WARNING] $1" >&2
}

hex_encode() {
    # Hex encode a path for vscode-remote URI
    local input_path="$1"
    echo -n "$input_path" | xxd -p | tr -d '\n'
}

run_command() {
    # Execute a command with dry-run and verbose support
    local cmd="$1"
    
    if [[ "${DRY_RUN}" == "1" ]]; then
        log_info "[Dry-Run] Would execute: ${cmd}"
        return 0
    fi
    
    log_debug "Executing command: ${cmd}"
    
    eval "${cmd}" > /dev/null 2>&1
    local exit_code=$?
    
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Command failed: ${cmd}"
        return 1
    fi
    
    return 0
}

verify_docker() {
    # Verify Docker is running
    log_debug "Verifying Docker is running..."
    
    run_command "docker info"
    if [[ $? -ne 0 ]]; then
        log_error "Docker is not running or not accessible"
        return 1
    fi
    
    log_debug "Docker verified successfully"
    return 0
}

show_help() {
    cat << EOF

Usage: $(basename "$0") MODE [OPTIONS]

Launch Editor Connected to Remote Host or Remote/Local Docker Container

Modes:
  remote-host         Connect to remote host via SSH
  remote-container    Connect to Docker container on remote host via SSH
  local-container     Connect to Docker container on local host

Options:
  --host HOST           Remote hostname for SSH connections
  --workspace PATH      Absolute path to workspace directory
  --editor EDITOR       Specify editor (code, cursor)
  --dev-container PATH  Absolute path to .devcontainer directory
  --dry-run             Print commands without executing
  --verbose             Enable verbose output
  --help, -h            Show this help message

Examples:
  $(basename "$0") remote-host --host myserver
  $(basename "$0") remote-container --host myserver --dev-container /path/to/.devcontainer
  $(basename "$0") local-container --dev-container /path/to/.devcontainer

EOF
    exit 1
}

###############################################################################
# Main
###############################################################################

URI=""

case "${MODE}" in
    remote-host)
        URI="vscode-remote://ssh-remote+${HOST}${WORKSPACE}"
        ;;
    remote-container)
        HEX_PATH=$(hex_encode "${DEV_CONTAINER}")
        URI="vscode-remote://dev-container+${HEX_PATH}@ssh-remote+${HOST}${WORKSPACE}"
        ;;
    local-container)
        verify_docker
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        HEX_PATH=$(hex_encode "${DEV_CONTAINER}")
        URI="vscode-remote://dev-container+${HEX_PATH}@${WORKSPACE}"
        ;;
esac

# Display Launch Parameters
echo "==========================================================================="
log_info "Launching with the following parameters:"
echo "==========================================================================="
log_info "Mode           : ${MODE}"

case "${MODE}" in
    remote-host)
        log_info "Host           : ${HOST}"
        ;;
    remote-container)
        log_info "Host           : ${HOST}"
        log_info "Dev Container  : ${DEV_CONTAINER}"
        ;;
    local-container)
        log_info "Dev Container  : ${DEV_CONTAINER}"
        ;;
esac

log_info "Workspace      : ${WORKSPACE}"
log_info "Editor         : ${EDITOR}"
echo "==========================================================================="

# Launch the Editor
COMMAND_TO_RUN="${EDITOR} --folder-uri ${URI}"

if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[Dry-Run] Would execute: ${COMMAND_TO_RUN}"
    exit 0
fi

log_debug "Executing command: ${COMMAND_TO_RUN}"

eval "${COMMAND_TO_RUN}" &
LAUNCHER_PID=$!

if ! wait ${LAUNCHER_PID} 2>/dev/null; then
    log_error "Failed to launch ${EDITOR}"
    exit 1
fi

exit 0
