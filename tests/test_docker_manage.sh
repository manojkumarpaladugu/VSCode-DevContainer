#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$TEST_DIR/.." && pwd)
CLI="$REPO_DIR/docker_manage.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/docker-manage-tests.XXXXXX")
MOCK_BIN="$TEST_TMP/bin"
MOCK_LOG="$TEST_TMP/docker.log"
MOCK_AGENT_LOG="$TEST_TMP/agent.log"
MOCK_AGENT_GID_LOG="$TEST_TMP/agent-gid.log"
OUTPUT_FILE="$TEST_TMP/output"
HOST_TEST_SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-}
AUTO_COMPOSE_DIR="$TEST_TMP/auto-compose"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$MOCK_BIN"
mkdir -p "$AUTO_COMPOSE_DIR/nested"
AUTO_COMPOSE_DIR=$(cd "$AUTO_COMPOSE_DIR" && pwd)
: > "$MOCK_LOG"
: > "$MOCK_AGENT_LOG"
: > "$MOCK_AGENT_GID_LOG"
: > "$AUTO_COMPOSE_DIR/compose.yaml"
: > "$AUTO_COMPOSE_DIR/compose.override.yaml"
: > "$AUTO_COMPOSE_DIR/docker-compose.ssh-agent.yml"

cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash

line="docker"
for arg in "$@"; do
    line="$line	$arg"
done
printf '%b\n' "$line" >> "${MOCK_DOCKER_LOG:?}"
printf '%s\n' "${DOCKER_SSH_AUTH_SOCK:-}" >> "${MOCK_AGENT_LOG:?}"
printf '%s\n' "${DOCKER_SSH_AUTH_GID:-}" >> "${MOCK_AGENT_GID_LOG:?}"

if [ "${1:-}" = "info" ]; then
    exit "${MOCK_INFO_STATUS:-0}"
fi

if [ "${1:-}" = "compose" ] && [ "${2:-}" = "version" ]; then
    exit "${MOCK_COMPOSE_STATUS:-0}"
fi

case "$*" in
    *" bash -c :"*) exit "${MOCK_HAS_BASH:-0}" ;;
    *" sh -c :"*) exit "${MOCK_HAS_SH:-0}" ;;
esac

if [ -n "${MOCK_FAIL_MATCH:-}" ]; then
    case "$*" in
        *"$MOCK_FAIL_MATCH"*) exit "${MOCK_FAIL_STATUS:-1}" ;;
    esac
fi
MOCK
chmod +x "$MOCK_BIN/docker"

cat > "$MOCK_BIN/uname" <<'MOCK'
#!/usr/bin/env bash
if [ -n "${MOCK_UNAME:-}" ]; then
    printf '%s\n' "$MOCK_UNAME"
else
    /usr/bin/uname "$@"
fi
MOCK
chmod +x "$MOCK_BIN/uname"

LAST_STATUS=0
LAST_OUTPUT=""
TESTS_RUN=0

run_cli_from() {
    local working_directory=$1
    shift
    : > "$MOCK_LOG"
    : > "$MOCK_AGENT_LOG"
    : > "$MOCK_AGENT_GID_LOG"
    : > "$OUTPUT_FILE"
    set +o errexit
    (
        cd "$working_directory" || exit 1
        PATH="$MOCK_BIN:/usr/bin:/bin" \
            SSH_AUTH_SOCK="${MOCK_SSH_AUTH_SOCK_VALUE:-}" \
            DOCKER_SSH_AUTH_SOCK="${MOCK_DOCKER_SSH_AUTH_SOCK_VALUE:-}" \
            DOCKER_SSH_AUTH_GID="${MOCK_DOCKER_SSH_AUTH_GID_VALUE:-}" \
            MOCK_UNAME="${MOCK_UNAME_VALUE:-}" \
            MOCK_DOCKER_LOG="$MOCK_LOG" \
            MOCK_AGENT_LOG="$MOCK_AGENT_LOG" \
            MOCK_AGENT_GID_LOG="$MOCK_AGENT_GID_LOG" \
            MOCK_HAS_BASH="${MOCK_HAS_BASH_VALUE:-0}" \
            MOCK_HAS_SH="${MOCK_HAS_SH_VALUE:-0}" \
            MOCK_INFO_STATUS="${MOCK_INFO_STATUS_VALUE:-0}" \
            MOCK_COMPOSE_STATUS="${MOCK_COMPOSE_STATUS_VALUE:-0}" \
            MOCK_FAIL_MATCH="${MOCK_FAIL_MATCH_VALUE:-}" \
            MOCK_FAIL_STATUS="${MOCK_FAIL_STATUS_VALUE:-1}" \
            /bin/bash "$CLI" "$@" < /dev/null > "$OUTPUT_FILE" 2>&1
    )
    LAST_STATUS=$?
    set -o errexit
    LAST_OUTPUT=$(command cat "$OUTPUT_FILE")
}

run_cli() {
    run_cli_from "$REPO_DIR" "$@"
}

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

fail() {
    printf 'not ok %d - %s\n' "$((TESTS_RUN + 1))" "$1" >&2
    printf '%s\n' "$LAST_OUTPUT" >&2
    printf '%s\n' '--- mock Docker calls ---' >&2
    command cat "$MOCK_LOG" >&2
    exit 1
}

assert_status() {
    local expected=$1
    local name=$2
    [ "$LAST_STATUS" -eq "$expected" ] || fail "$name (expected status $expected, got $LAST_STATUS)"
}

assert_output_contains() {
    local expected=$1
    local name=$2
    case "$LAST_OUTPUT" in
        *"$expected"*) ;;
        *) fail "$name (missing '$expected')" ;;
    esac
}

assert_output_excludes() {
    local unexpected=$1
    local name=$2
    case "$LAST_OUTPUT" in
        *"$unexpected"*) fail "$name (unexpected '$unexpected')" ;;
        *) ;;
    esac
}

assert_log_line() {
    local expected=$1
    local name=$2
    command grep -F -x "$expected" "$MOCK_LOG" >/dev/null || fail "$name (missing Docker call)"
}

assert_log_excludes() {
    local unexpected=$1
    local name=$2
    if command grep -F -- "$unexpected" "$MOCK_LOG" >/dev/null; then
        fail "$name (unexpected Docker call)"
    fi
}

assert_agent_log_line() {
    local expected=$1
    local name=$2
    command grep -F -x "$expected" "$MOCK_AGENT_LOG" >/dev/null || fail "$name (missing forwarded socket)"
}

assert_agent_gid_log_line() {
    local expected=$1
    local name=$2
    command grep -F -x "$expected" "$MOCK_AGENT_GID_LOG" >/dev/null || fail "$name (missing forwarded socket group)"
}

run_cli --help
assert_status 0 "global help succeeds"
assert_output_contains "[COMPOSE_OPTIONS] ACTION" "global help documents action-first syntax"
assert_output_contains "cleanup" "global help documents cleanup"
[ ! -s "$MOCK_LOG" ] || fail "global help does not call Docker"
pass "global help works without contacting Docker"

run_cli
assert_status 2 "missing action returns usage error"
assert_output_contains "An action is required" "missing action is actionable"
[ ! -s "$MOCK_LOG" ] || fail "missing action does not call Docker"
pass "an action is required"

run_cli -f first.yml --file second.yml --profile dev -p demo start api worker
assert_status 0 "start succeeds"
assert_log_line $'docker\tcompose\t-f\tfirst.yml\t--file\tsecond.yml\t--profile\tdev\t-p\tdemo\tup\t-d\t--build\tapi\tworker' "start selects the project and services"
pass "start builds, creates, and starts selected services"

run_cli rebuild api
assert_status 0 "rebuild succeeds"
assert_log_line $'docker\tcompose\tup\t-d\t--build\t--force-recreate\tapi' "rebuild forces recreation"
pass "rebuild refreshes service containers"

run_cli stop --timeout 15 api
assert_status 0 "stop succeeds"
assert_log_line $'docker\tcompose\tstop\t--timeout\t15\tapi' "stop forwards arguments"
pass "standard Compose action arguments are forwarded"

for forwarded_action in restart build pull config logs; do
    run_cli "$forwarded_action" api
    assert_status 0 "$forwarded_action succeeds"
    assert_log_line "$(printf 'docker\tcompose\t%s\tapi' "$forwarded_action")" "$forwarded_action uses Compose"
done
pass "all direct project actions use their Compose counterparts"

run_cli status api
assert_status 0 "status succeeds"
assert_log_line $'docker\tcompose\tps\t--all\tapi' "status includes stopped service containers"
pass "status shows all selected service containers"

run_cli exec api
assert_status 2 "exec without a command fails"
assert_output_contains "Missing arguments for 'exec'" "exec usage error is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid exec does not call Docker"
pass "exec validates its service and command"

run_cli exec -T api env FOO=bar
assert_status 0 "exec succeeds"
assert_log_line $'docker\tcompose\texec\t-T\tapi\tenv\tFOO=bar' "exec forwards arguments"
pass "exec runs commands through Compose"

run_cli run
assert_status 2 "run without a service fails"
assert_output_contains "Missing arguments for 'run'" "run usage error is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid run does not call Docker"
pass "run requires a service"

run_cli --env-file dev.env run -e MODE=test api bash
assert_status 0 "disposable run succeeds"
assert_log_line $'docker\tcompose\t--env-file\tdev.env\trun\t--rm\t--build\t-e\tMODE=test\tapi\tbash' "run builds and removes its container"
pass "run creates a disposable service container"

MOCK_HAS_BASH_VALUE=0
MOCK_HAS_SH_VALUE=0
run_cli -f stack.yml shell api
assert_status 0 "bash shell succeeds"
assert_log_line $'docker\tcompose\t-f\tstack.yml\tup\t-d\t--build\tapi' "shell starts its service"
assert_log_line $'docker\tcompose\t-f\tstack.yml\texec\t-T\tapi\tbash' "shell selects bash"
pass "shell prepares the service and prefers bash"

MOCK_HAS_BASH_VALUE=1
MOCK_HAS_SH_VALUE=0
run_cli shell api
assert_status 0 "sh fallback succeeds"
assert_log_line $'docker\tcompose\texec\t-T\tapi\tsh' "shell falls back to sh"
pass "shell falls back to sh"

MOCK_HAS_BASH_VALUE=44
MOCK_HAS_SH_VALUE=45
run_cli shell api
assert_status 45 "shell resolution failure is preserved"
assert_output_contains "bash probe exited 44; sh probe exited 45" "shell resolution reports both failures"
MOCK_HAS_BASH_VALUE=0
MOCK_HAS_SH_VALUE=0
pass "shell resolution preserves the final Compose failure"

MOCK_HAS_BASH_VALUE=0
run_cli shell api python3 -V
assert_status 0 "explicit shell command succeeds"
assert_log_line $'docker\tcompose\tup\t-d\t--build\tapi' "explicit shell command prepares the service"
assert_log_line $'docker\tcompose\texec\t-T\tapi\tpython3\t-V' "explicit shell command is unchanged"
assert_log_excludes "bash -c :" "explicit command skips shell probing"
pass "shell accepts an explicit command"

run_cli --dry-run shell api
assert_status 0 "shell dry run succeeds"
assert_output_contains "+ docker compose up -d --build api" "shell dry run prints service preparation"
assert_output_contains "+ docker compose exec -T api bash" "shell dry run prints its default attempt"
[ ! -s "$MOCK_LOG" ] || fail "shell dry run does not invoke Docker"
pass "shell dry run reports both phases without contacting Docker"

run_cli --dry-run -f stack.yml start api
assert_status 0 "start dry run succeeds"
assert_output_contains "+ docker compose -f stack.yml up -d --build api" "start dry run prints the command"
[ ! -s "$MOCK_LOG" ] || fail "start dry run does not invoke Docker"
pass "project dry runs do not contact Docker"

if [ -n "$HOST_TEST_SSH_AUTH_SOCK" ] && [ -S "$HOST_TEST_SSH_AUTH_SOCK" ]; then
    HOST_TEST_SSH_AUTH_GID=$(stat -c '%g' "$HOST_TEST_SSH_AUTH_SOCK" 2>/dev/null \
        || stat -f '%g' "$HOST_TEST_SSH_AUTH_SOCK")
    MOCK_UNAME_VALUE=Linux
    MOCK_SSH_AUTH_SOCK_VALUE=$HOST_TEST_SSH_AUTH_SOCK
    run_cli -f "$REPO_DIR/generic/docker-compose.yml" start generic-ubuntu
    assert_status 0 "Linux agent forwarding succeeds"
    assert_log_line "$(printf 'docker\tcompose\t-f\t%s\t-f\t%s\tup\t-d\t--build\tgeneric-ubuntu' "$REPO_DIR/generic/docker-compose.yml" "$REPO_DIR/generic/docker-compose.ssh-agent.yml")" "explicit Compose selection appends the agent overlay"
    assert_agent_log_line "$HOST_TEST_SSH_AUTH_SOCK" "Linux forwards SSH_AUTH_SOCK"
    assert_agent_gid_log_line "$HOST_TEST_SSH_AUTH_GID" "Linux forwards the socket group"
    pass "Linux forwards its Unix SSH-agent socket"

    MOCK_UNAME_VALUE=Darwin
    run_cli -f "$REPO_DIR/zephyr/docker-compose.yml" status
    assert_status 0 "macOS agent forwarding succeeds"
    assert_log_line "$(printf 'docker\tcompose\t-f\t%s\t-f\t%s\tps\t--all' "$REPO_DIR/zephyr/docker-compose.yml" "$REPO_DIR/zephyr/docker-compose.ssh-agent.yml")" "macOS appends the agent overlay"
    assert_agent_log_line "/run/host-services/ssh-auth.sock" "macOS selects the Docker Desktop bridge"
    assert_agent_gid_log_line "0" "macOS adds Docker Desktop's socket group"
    pass "macOS uses Docker Desktop's SSH-agent bridge"
else
    pass "Linux automatic socket selection skipped because the test host has no agent socket"
    pass "macOS automatic socket selection skipped because the test host has no agent socket"
fi

MOCK_UNAME_VALUE=Unsupported
MOCK_SSH_AUTH_SOCK_VALUE=""
MOCK_DOCKER_SSH_AUTH_SOCK_VALUE=/custom/agent.sock
MOCK_DOCKER_SSH_AUTH_GID_VALUE=1234
run_cli_from "$REPO_DIR/generic" start generic-ubuntu
assert_status 0 "explicit agent override succeeds"
assert_log_line "$(printf 'docker\tcompose\t-f\t%s\t-f\t%s\tup\t-d\t--build\tgeneric-ubuntu' "$REPO_DIR/generic/docker-compose.yml" "$REPO_DIR/generic/docker-compose.ssh-agent.yml")" "current-directory discovery adds both Compose files"
assert_agent_log_line "/custom/agent.sock" "explicit override is forwarded"
assert_agent_gid_log_line "1234" "explicit socket group is forwarded"
pass "current-directory discovery honors an explicit agent socket"

run_cli_from "$AUTO_COMPOSE_DIR/nested" start api
assert_status 0 "parent-directory agent discovery succeeds"
assert_log_line "$(printf 'docker\tcompose\t-f\t%s\t-f\t%s\t-f\t%s\tup\t-d\t--build\tapi' "$AUTO_COMPOSE_DIR/compose.yaml" "$AUTO_COMPOSE_DIR/compose.override.yaml" "$AUTO_COMPOSE_DIR/docker-compose.ssh-agent.yml")" "automatic discovery preserves the conventional override before the agent overlay"
pass "agent discovery follows Compose to a parent and preserves its default override"

MOCK_DOCKER_SSH_AUTH_SOCK_VALUE=/daemon-only/agent.sock
MOCK_DOCKER_SSH_AUTH_GID_VALUE=""
run_cli_from "$REPO_DIR/generic" start generic-ubuntu
assert_status 2 "explicit daemon-only socket without a group fails"
assert_output_contains "set DOCKER_SSH_AUTH_GID explicitly" "missing explicit socket group is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid explicit socket does not call Docker"
pass "invalid explicit socket configuration cannot silently disable forwarding"

MOCK_DOCKER_SSH_AUTH_GID_VALUE=not-a-number
run_cli_from "$REPO_DIR/generic" start generic-ubuntu
assert_status 2 "nonnumeric socket group fails"
assert_output_contains "must be a numeric group ID" "invalid socket group is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid explicit group does not call Docker"
pass "explicit socket group is validated"

MOCK_UNAME_VALUE=Linux
MOCK_DOCKER_SSH_AUTH_SOCK_VALUE=""
MOCK_DOCKER_SSH_AUTH_GID_VALUE=""
run_cli -f "$REPO_DIR/generic/docker-compose.yml" start generic-ubuntu
assert_status 0 "startup without an agent succeeds"
assert_output_contains "Continuing without SSH-agent forwarding" "missing agent emits a warning"
assert_log_line "$(printf 'docker\tcompose\t-f\t%s\tup\t-d\t--build\tgeneric-ubuntu' "$REPO_DIR/generic/docker-compose.yml")" "missing agent leaves the base Compose command unchanged"
assert_log_excludes "docker-compose.ssh-agent.yml" "missing agent does not add the overlay"
pass "container startup warns and continues without an agent"

run_cli -f "$REPO_DIR/generic/docker-compose.yml" status
assert_status 0 "status without an agent succeeds"
assert_output_excludes "Continuing without SSH-agent forwarding" "non-creating actions remain quiet"
pass "non-creating actions do not warn when the agent is absent"

MOCK_UNAME_VALUE=""
MOCK_SSH_AUTH_SOCK_VALUE=""

run_cli remove
assert_status 2 "noninteractive project removal is rejected"
assert_output_contains "Re-run with global --force" "project removal explains confirmation override"
[ ! -s "$MOCK_LOG" ] || fail "rejected project removal does not call Docker"
pass "project removal requires confirmation or force"

run_cli --force -f stack.yml remove
assert_status 0 "forced project removal succeeds"
assert_log_line $'docker\tcompose\t-f\tstack.yml\tdown\t--remove-orphans' "project removal uses Compose down"
assert_log_excludes "--volumes" "project removal preserves volumes"
assert_log_excludes "--rmi" "project removal preserves images"
pass "project removal stops and removes while preserving data"

run_cli --force remove api worker
assert_status 0 "forced service removal succeeds"
assert_log_line $'docker\tcompose\trm\t--stop\t--force\tapi\tworker' "service removal stops before removing"
pass "service removal combines stop and remove"

run_cli --force remove --volumes
assert_status 2 "remove options are rejected"
assert_output_contains "accepts service names only" "remove option rejection is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid remove does not call Docker"
pass "remove cannot accidentally delete volumes"

run_cli cleanup
assert_status 2 "noninteractive cleanup is rejected"
assert_output_contains "unused by running containers" "cleanup confirmation explains its scope"
[ ! -s "$MOCK_LOG" ] || fail "rejected cleanup does not call Docker"
pass "global cleanup requires confirmation or force"

run_cli --dry-run cleanup
assert_status 0 "cleanup dry run succeeds"
assert_output_contains "+ docker system prune --all --volumes --force" "cleanup dry run prints system prune"
assert_output_contains "+ docker volume prune --all --force" "cleanup dry run prints named-volume prune"
[ ! -s "$MOCK_LOG" ] || fail "cleanup dry run does not invoke Docker"
pass "cleanup dry run reports both phases"

run_cli --force cleanup
assert_status 0 "forced cleanup succeeds"
assert_log_line $'docker\tsystem\tprune\t--all\t--volumes\t--force' "cleanup prunes unused system data"
assert_log_line $'docker\tvolume\tprune\t--all\t--force' "cleanup prunes unused named volumes"
assert_log_excludes $'docker\tcompose' "cleanup is the documented engine-level exception"
pass "cleanup removes every class of unused Docker data"

run_cli --force -f stack.yml cleanup
assert_status 2 "cleanup rejects Compose options"
assert_output_contains "does not accept Compose options" "cleanup option error is actionable"
[ ! -s "$MOCK_LOG" ] || fail "invalid cleanup does not call Docker"
pass "cleanup cannot imply a project-specific scope"

run_cli --force cleanup extra
assert_status 2 "cleanup rejects arguments"
assert_output_contains "does not accept arguments" "cleanup argument error is actionable"
[ ! -s "$MOCK_LOG" ] || fail "cleanup with arguments does not call Docker"
pass "cleanup has one unambiguous global scope"

MOCK_FAIL_MATCH_VALUE="system prune"
MOCK_FAIL_STATUS_VALUE=41
run_cli --force cleanup
assert_status 41 "system prune failure is preserved"
assert_log_excludes $'docker\tvolume\tprune' "cleanup stops after a failed system prune"
MOCK_FAIL_MATCH_VALUE=""
MOCK_FAIL_STATUS_VALUE=1
pass "cleanup preserves a system-prune failure"

MOCK_FAIL_MATCH_VALUE="volume prune"
MOCK_FAIL_STATUS_VALUE=42
run_cli --force cleanup
assert_status 42 "volume prune failure is preserved"
MOCK_FAIL_MATCH_VALUE=""
MOCK_FAIL_STATUS_VALUE=1
pass "cleanup preserves a named-volume-prune failure"

for removed_resource in container image compose; do
    run_cli "$removed_resource" list
    assert_status 2 "removed resource group fails"
    assert_output_contains "resource group was removed" "removed resource group provides migration help"
    [ ! -s "$MOCK_LOG" ] || fail "removed resource group does not call Docker"
done
pass "legacy resource groups fail with a migration hint"

run_cli explode target
assert_status 2 "unknown action fails"
assert_output_contains "Unknown action: explode" "unknown action is identified"
[ ! -s "$MOCK_LOG" ] || fail "unknown action does not call Docker"
pass "unknown actions fail before Docker checks"

MOCK_INFO_STATUS_VALUE=55
run_cli status
assert_status 55 "daemon preflight status is preserved"
assert_output_contains "Cannot access the Docker daemon" "daemon failure is actionable"
MOCK_INFO_STATUS_VALUE=0
pass "daemon failures remain actionable"

MOCK_COMPOSE_STATUS_VALUE=56
run_cli status
assert_status 56 "Compose preflight status is preserved"
assert_output_contains "Docker Compose v2 is unavailable" "Compose failure is actionable"
MOCK_COMPOSE_STATUS_VALUE=0
pass "missing Compose v2 is reported separately"

MOCK_FAIL_MATCH_VALUE="compose logs broken"
MOCK_FAIL_STATUS_VALUE=43
run_cli logs broken
assert_status 43 "Compose action failure is preserved"
MOCK_FAIL_MATCH_VALUE=""
MOCK_FAIL_STATUS_VALUE=1
pass "Compose exit codes propagate unchanged"

run_cli --no-color --verbose status
assert_status 0 "verbose uncolored status succeeds"
if LC_ALL=C command grep "$(printf '\033')" "$OUTPUT_FILE" >/dev/null; then
    fail "no-color suppresses ANSI escapes"
fi
assert_output_contains "+ docker compose ps --all" "verbose mode prints the Compose command"
pass "diagnostics can be verbose and uncolored"

if command grep -E 'docker (container|image|network|builder)' "$CLI" >/dev/null; then
    fail "normal implementation contains a direct Docker resource command"
fi
pass "normal project implementation is Compose-only"

for devcontainer_file in \
    "$REPO_DIR/generic/.devcontainer/devcontainer.json" \
    "$REPO_DIR/zephyr/.devcontainer/devcontainer.json"; do
    command grep -F '"dockerComposeFile": "../docker-compose.yml"' "$devcontainer_file" >/dev/null \
        || fail "editor configuration no longer selects only the base Compose file"
    if command grep -F 'docker-compose.ssh-agent.yml' "$devcontainer_file" >/dev/null; then
        fail "editor configuration unexpectedly references the SSH-agent overlay"
    fi
done
pass "editor launches remain isolated from wrapper-only overlays"

printf '1..%d\n' "$TESTS_RUN"
