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
OUTPUT_FILE="$TEST_TMP/output"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT INT TERM

mkdir -p "$MOCK_BIN"
: > "$MOCK_LOG"

cat > "$MOCK_BIN/docker" <<'MOCK'
#!/usr/bin/env bash

line="docker"
for arg in "$@"; do
    line="$line	$arg"
done
printf '%b\n' "$line" >> "${MOCK_DOCKER_LOG:?}"

if [ "${1:-}" = "info" ]; then
    exit "${MOCK_INFO_STATUS:-0}"
fi

if [ "${1:-}" = "compose" ] && [ "${2:-}" = "version" ]; then
    exit "${MOCK_COMPOSE_STATUS:-0}"
fi

case "$*" in
    *"{{.State.Running}}"*)
        printf '%s\n' "${MOCK_CONTAINER_RUNNING:-true}"
        exit "${MOCK_INSPECT_STATUS:-0}"
        ;;
    *" bash -c :"*)
        exit "${MOCK_HAS_BASH:-0}"
        ;;
    *" sh -c :"*)
        exit "${MOCK_HAS_SH:-0}"
        ;;
esac

if [ -n "${MOCK_FAIL_MATCH:-}" ]; then
    case "$*" in
        *"$MOCK_FAIL_MATCH"*) exit "${MOCK_FAIL_STATUS:-1}" ;;
    esac
fi

if [ "${1:-}" = "container" ] && [ "${2:-}" = "ls" ]; then
    printf 'mock-container-output\n'
fi
MOCK
chmod +x "$MOCK_BIN/docker"

LAST_STATUS=0
LAST_OUTPUT=""
TESTS_RUN=0

run_cli() {
    : > "$MOCK_LOG"
    : > "$OUTPUT_FILE"
    set +o errexit
    PATH="$MOCK_BIN:/usr/bin:/bin" \
        MOCK_DOCKER_LOG="$MOCK_LOG" \
        MOCK_HAS_BASH="${MOCK_HAS_BASH_VALUE:-0}" \
        MOCK_HAS_SH="${MOCK_HAS_SH_VALUE:-0}" \
        MOCK_CONTAINER_RUNNING="${MOCK_CONTAINER_RUNNING_VALUE:-true}" \
        MOCK_INFO_STATUS="${MOCK_INFO_STATUS_VALUE:-0}" \
        MOCK_COMPOSE_STATUS="${MOCK_COMPOSE_STATUS_VALUE:-0}" \
        MOCK_FAIL_MATCH="${MOCK_FAIL_MATCH_VALUE:-}" \
        MOCK_FAIL_STATUS="${MOCK_FAIL_STATUS_VALUE:-1}" \
        /bin/bash "$CLI" "$@" < /dev/null > "$OUTPUT_FILE" 2>&1
    LAST_STATUS=$?
    set -o errexit
    LAST_OUTPUT=$(command cat "$OUTPUT_FILE")
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

run_cli --help
assert_status 0 "global help succeeds"
assert_output_contains "container ACTION" "global help documents resources"
[ ! -s "$MOCK_LOG" ] || fail "global help does not call Docker"
pass "global help works without contacting Docker"

run_cli container start alpha beta
assert_status 0 "container start succeeds"
assert_log_line $'docker\tcontainer\tstart\talpha\tbeta' "container start forwards all targets"
pass "container lifecycle arguments are forwarded"

run_cli image build --no-cache -f docker/Customfile -t example/app:test ./context
assert_status 0 "image build succeeds"
assert_log_line $'docker\timage\tbuild\t--no-cache\t-f\tdocker/Customfile\t-t\texample/app:test\t./context' "image build forwards flags"
pass "image build arguments are unchanged"

run_cli compose -f first.yml --file second.yml --profile dev -p demo up -d api
assert_status 0 "compose up succeeds"
assert_log_line $'docker\tcompose\t-f\tfirst.yml\t--file\tsecond.yml\t--profile\tdev\t-p\tdemo\tup\t-d\tapi' "compose ordering is preserved"
pass "Compose project options precede the action"

run_cli container stop
assert_status 2 "missing target returns usage error"
assert_output_contains "Missing arguments for 'container stop'" "missing target is actionable"
[ ! -s "$MOCK_LOG" ] || fail "missing target is validated before Docker preflight"
pass "targeted actions reject missing targets before daemon checks"

run_cli container remove --help
assert_status 0 "container remove help succeeds"
assert_log_line $'docker\tcontainer\trm\t--help' "container remove delegates native help"
assert_log_excludes $'docker\tinfo' "native help does not require the daemon"
pass "destructive action help never prompts or checks the daemon"

run_cli compose exec --help
assert_status 0 "compose exec help succeeds"
assert_log_line $'docker\tcompose\texec\t--help' "compose exec delegates native help"
assert_log_excludes $'docker\tinfo' "Compose action help does not require the daemon"
pass "multi-argument Compose actions expose native help"

run_cli compose -f stack.yml --help
assert_status 0 "Compose resource help accepts preceding options"
assert_output_contains "Compose options" "Compose resource help is displayed"
[ ! -s "$MOCK_LOG" ] || fail "Compose resource help does not call Docker"
pass "Compose help remains available after project options"

run_cli container run alpine:latest --help
assert_status 0 "container command named help is forwarded"
assert_log_line $'docker\tinfo' "command argument named help still checks the daemon"
assert_log_line $'docker\tcontainer\trun\talpine:latest\t--help' "command argument named help is unchanged"
pass "a post-image --help token is not mistaken for wrapper help"

MOCK_HAS_BASH_VALUE=0
MOCK_HAS_SH_VALUE=0
run_cli container shell app
assert_status 0 "container bash shell succeeds"
assert_log_line $'docker\tcontainer\texec\t-i\tapp\tbash' "container shell selects bash"
pass "container shell prefers bash"

MOCK_HAS_BASH_VALUE=1
MOCK_HAS_SH_VALUE=0
run_cli container shell app
assert_status 0 "container sh fallback succeeds"
assert_log_line $'docker\tcontainer\texec\t-i\tapp\tsh' "container shell falls back to sh"
pass "container shell falls back to sh"

MOCK_HAS_BASH_VALUE=0
run_cli compose -f stack.yml shell api
assert_status 0 "compose shell succeeds"
assert_log_line $'docker\tcompose\t-f\tstack.yml\texec\t-T\tapi\tbash' "compose shell uses project options"
pass "Compose shell resolves a shell within the selected project"

run_cli --dry-run container run --name demo alpine:latest echo hello
assert_status 0 "dry run succeeds"
assert_output_contains "+ docker container run --name demo alpine:latest echo hello" "dry run prints command"
[ ! -s "$MOCK_LOG" ] || fail "dry run does not invoke Docker"
pass "dry run does not contact Docker"

run_cli --dry-run container remove old-api
assert_status 0 "destructive dry run succeeds without confirmation"
assert_output_contains "+ docker container rm old-api" "destructive dry run prints command"
[ ! -s "$MOCK_LOG" ] || fail "destructive dry run does not invoke Docker"
pass "dry run never prompts for a destructive command"

run_cli container remove old-api old-worker
assert_status 2 "noninteractive removal is rejected"
assert_output_contains "Re-run with global --force" "noninteractive removal explains override"
assert_log_excludes $'container\trm' "rejected removal does not call rm"
pass "destructive operations require confirmation or force"

run_cli --force container remove --volumes old-api old-worker
assert_status 0 "forced container removal succeeds"
assert_log_line $'docker\tcontainer\trm\t--volumes\told-api\told-worker' "forced removal forwards arguments"
pass "global force skips only the wrapper confirmation"

run_cli --force image remove --platform linux/amd64 app:test
assert_status 0 "platform-specific image removal succeeds"
assert_log_line $'docker\timage\trm\t--platform\tlinux/amd64\tapp:test' "image removal preserves platform"
pass "image removal resolves targets without consuming option values"

run_cli --force image prune --all --filter until=24h
assert_status 0 "forced image prune succeeds"
assert_log_line $'docker\timage\tprune\t--force\t--all\t--filter\tuntil=24h' "image prune is noninteractive after wrapper confirmation"
pass "resource-scoped prune forwards filters"

run_cli compose -f stack.yml down
assert_status 0 "compose down succeeds"
assert_log_line $'docker\tcompose\t-f\tstack.yml\tdown' "compose down adds no destructive flags"
assert_log_excludes "--volumes" "compose down preserves volumes"
assert_log_excludes "--rmi" "compose down preserves images"
pass "Compose down preserves volumes and images by default"

run_cli --no-color --verbose container list --all
assert_status 0 "no-color list succeeds"
if LC_ALL=C command grep "$(printf '\033')" "$OUTPUT_FILE" >/dev/null; then
    fail "no-color suppresses ANSI escapes"
fi
assert_output_contains "mock-container-output" "Docker stdout remains visible"
pass "diagnostics can be uncolored without hiding Docker output"

run_cli container explode target
assert_status 2 "invalid action returns usage error"
assert_output_contains "Unknown container action: explode" "invalid action is identified"
[ ! -s "$MOCK_LOG" ] || fail "unknown action is validated before Docker preflight"
pass "unknown actions fail clearly before daemon checks"

MOCK_INFO_STATUS_VALUE=55
run_cli container list
assert_status 55 "daemon preflight status is preserved"
assert_output_contains "Cannot access the Docker daemon" "daemon failure is actionable"
MOCK_INFO_STATUS_VALUE=0
pass "daemon failures remain actionable and preserve status"

MOCK_COMPOSE_STATUS_VALUE=56
run_cli compose ps
assert_status 56 "Compose preflight status is preserved"
assert_output_contains "Docker Compose v2 is unavailable" "Compose failure is actionable"
MOCK_COMPOSE_STATUS_VALUE=0
pass "missing Compose v2 is reported separately"

MOCK_FAIL_MATCH_VALUE="container stop broken"
MOCK_FAIL_STATUS_VALUE=42
run_cli container stop broken
assert_status 42 "Docker failure status is preserved"
MOCK_FAIL_MATCH_VALUE=""
MOCK_FAIL_STATUS_VALUE=1
pass "Docker exit codes propagate unchanged"

printf '1..%d\n' "$TESTS_RUN"
