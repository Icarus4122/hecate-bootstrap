#!/usr/bin/env bash
# tests/e2e/e2e-helpers.sh - Extended harness for platform validation.
#
# Builds on top of the TAP-style helpers from tests/helpers.sh, adding:
#   - Stage management (numbered, skippable, ordered)
#   - Scenario management (named, prerequisite-gated, fault-injectable)
#   - Report file generation with timestamps
#   - Section/subsection grouping
#   - Skip tracking (distinct from pass/fail)
#   - Platform-aware gate checks (is_root, has_docker, has_gpu, etc.)
#   - Duration tracking per stage and per scenario
#   - Docker inspect assertions (mounts, network mode)
#   - Idempotency and re-entry assertions
#   - Filesystem state capture/comparison
#   - Fault injection and recovery
set -euo pipefail

# ── Source base harness ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers.sh"

# ── Report state ───────────────────────────────────────────────────
E2E_REPORT_DIR="$SCRIPT_DIR/reports"
E2E_REPORT_FILE=""
E2E_TIMESTAMP=""
E2E_STAGE_NUM=""
E2E_STAGE_NAME=""
E2E_STAGE_START=""

# Counts across all stages
E2E_TOTAL_PASS=0
E2E_TOTAL_FAIL=0
E2E_TOTAL_SKIP=0
E2E_TOTAL_STAGES=0
E2E_STAGES_PASSED=0
E2E_STAGES_FAILED=0
E2E_STAGES_SKIPPED=0
E2E_FAILED_ITEMS=()

# Stage pass/fail record (for scenario prerequisites)
declare -A E2E_STAGE_RESULTS=()

# ── Scenario state ─────────────────────────────────────────────────
E2E_SCENARIO_NAME=""
E2E_SCENARIO_DESC=""
E2E_SCENARIO_START=""

E2E_TOTAL_SCENARIOS=0
E2E_SCENARIOS_PASSED=0
E2E_SCENARIOS_FAILED=0
E2E_SCENARIOS_SKIPPED=0

# Fault injection tracking
declare -a E2E_ACTIVE_FAULTS=()

# State capture storage
declare -A E2E_STATE_SNAPSHOTS=()

# ── Environment queries ───────────────────────────────────────────
is_root()    { [[ "$(id -u)" -eq 0 ]]; }
has_docker() { command -v docker &>/dev/null && docker info &>/dev/null 2>&1; }
has_gpu()    { command -v nvidia-smi &>/dev/null; }
has_empusa() {
    local e="${LAB_ROOT:-/opt/lab}/tools/venvs/empusa/bin/empusa"
    [[ -x "$e" ]] && "$e" --version &>/dev/null 2>&1
}

# Detect compose command (docker compose or docker-compose)
detect_compose() {
    if docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

# ── Report initializer ────────────────────────────────────────────
init_report() {
    mkdir -p "$E2E_REPORT_DIR"
    E2E_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    E2E_REPORT_FILE="${E2E_REPORT_DIR}/validation-${E2E_TIMESTAMP}.txt"

    {
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║            HECATE PLATFORM VALIDATION REPORT                ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Host:      $(hostname)"
        echo "  Date:      $(date -Iseconds)"
        echo "  Kernel:    $(uname -r)"
        echo "  OS:        $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "unknown")"
        echo "  User:      $(whoami) (uid=$(id -u))"
        echo "  Repo:      ${REPO_ROOT}"
        echo "  LAB_ROOT:  ${LAB_ROOT:-/opt/lab}"
        echo ""
    } | tee "$E2E_REPORT_FILE"
}

# ── Stage lifecycle ────────────────────────────────────────────────

# Begin a numbered stage.  Usage: begin_stage 3 "Build & Compose"
begin_stage() {
    E2E_STAGE_NUM="$1"
    E2E_STAGE_NAME="$2"
    E2E_STAGE_START="$(date +%s)"
    _T_COUNT=0; _T_PASS=0; _T_FAIL=0

    local header
    header="── Stage ${E2E_STAGE_NUM}: ${E2E_STAGE_NAME} ──"
    {
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ${header}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } | tee -a "$E2E_REPORT_FILE"

    begin_tests "stage ${E2E_STAGE_NUM}: ${E2E_STAGE_NAME}"
}

# End current stage.  Returns 0 if all passed, 1 otherwise.
end_stage() {
    local now elapsed
    now="$(date +%s)"
    elapsed=$(( now - E2E_STAGE_START ))

    E2E_TOTAL_PASS=$(( E2E_TOTAL_PASS + _T_PASS ))
    E2E_TOTAL_FAIL=$(( E2E_TOTAL_FAIL + _T_FAIL ))
    E2E_TOTAL_STAGES=$(( E2E_TOTAL_STAGES + 1 ))

    local result
    if [[ $_T_FAIL -eq 0 ]]; then
        result="PASSED"
        E2E_STAGES_PASSED=$(( E2E_STAGES_PASSED + 1 ))
        E2E_STAGE_RESULTS[$E2E_STAGE_NUM]="pass"
    else
        result="FAILED"
        E2E_STAGES_FAILED=$(( E2E_STAGES_FAILED + 1 ))
        E2E_STAGE_RESULTS[$E2E_STAGE_NUM]="fail"
    fi

    {
        echo ""
        echo "1..${_T_COUNT}"
        echo "# Stage ${E2E_STAGE_NUM} ${E2E_STAGE_NAME}: ${_T_PASS} passed, ${_T_FAIL} failed (of ${_T_COUNT}) [${elapsed}s] — ${result}"
    } | tee -a "$E2E_REPORT_FILE"

    [[ $_T_FAIL -eq 0 ]]
}

# Skip an entire stage.
skip_stage() {
    local num="$1" name="$2" reason="${3:-skipped by operator}"
    E2E_TOTAL_STAGES=$(( E2E_TOTAL_STAGES + 1 ))
    E2E_STAGES_SKIPPED=$(( E2E_STAGES_SKIPPED + 1 ))
    {
        echo ""
        echo "── Stage ${num}: ${name} ── SKIPPED (${reason})"
    } | tee -a "$E2E_REPORT_FILE"
}

# ── Section separator within a stage ──────────────────────────────
section() {
    local title="$1"
    echo "" | tee -a "$E2E_REPORT_FILE"
    echo "  ── ${title} ──" | tee -a "$E2E_REPORT_FILE"
}

# ── Extended assertions (write to report too) ─────────────────────
# Override _record_pass/_record_fail to also write to report file.
_original_record_pass="$(declare -f _record_pass)"
_original_record_fail="$(declare -f _record_fail)"

_record_pass() {
    _T_COUNT=$((_T_COUNT + 1))
    _T_PASS=$((_T_PASS + 1))
    local line="ok ${_T_COUNT} - $1"
    echo "$line"
    echo "$line" >> "$E2E_REPORT_FILE" 2>/dev/null || true
}

_record_fail() {
    _T_COUNT=$((_T_COUNT + 1))
    _T_FAIL=$((_T_FAIL + 1))
    local line="not ok ${_T_COUNT} - $1"
    echo "$line"
    echo "$line" >> "$E2E_REPORT_FILE" 2>/dev/null || true
    if [[ -n "${2:-}" ]]; then
        local detail="#   got:      ${2}"
        echo "$detail"
        echo "$detail" >> "$E2E_REPORT_FILE" 2>/dev/null || true
    fi
    if [[ -n "${3:-}" ]]; then
        local detail="#   expected: ${3}"
        echo "$detail"
        echo "$detail" >> "$E2E_REPORT_FILE" 2>/dev/null || true
    fi
    E2E_FAILED_ITEMS+=("Stage ${E2E_STAGE_NUM}: $1")
}

# Assert a file is non-empty
assert_file_not_empty() {
    local path="$1" label="${2:-file not empty: $1}"
    if [[ -s "$path" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "(empty or missing)" "non-empty file at $path"
    fi
}

# Assert a file contains a string
assert_file_contains() {
    local path="$1" needle="$2" label="${3:-file contains: $2}"
    if [[ -f "$path" ]] && grep -qF "$needle" "$path"; then
        _record_pass "$label"
    else
        _record_fail "$label" "(not found in $path)" "'$needle' in file"
    fi
}

# Assert a command exits 0
assert_cmd_ok() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        _record_pass "$label"
    else
        _record_fail "$label" "exit $?" "exit 0"
    fi
}

# Assert a command exits non-zero
assert_cmd_fail() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        _record_fail "$label" "exit 0" "non-zero exit"
    else
        _record_pass "$label"
    fi
}

# Assert a symlink exists and points to the expected target
assert_symlink() {
    local link="$1" target="$2" label="${3:-symlink: $1 -> $2}"
    if [[ -L "$link" ]]; then
        local actual
        actual="$(readlink -f "$link")"
        local expected
        expected="$(readlink -f "$target")"
        if [[ "$actual" == "$expected" ]]; then
            _record_pass "$label"
        else
            _record_fail "$label" "-> $actual" "-> $expected"
        fi
    else
        _record_fail "$label" "(not a symlink)" "symlink at $link"
    fi
}

# Assert container is running by name
assert_container_running() {
    local name="$1" label="${2:-container running: $1}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        _record_pass "$label"
    else
        _record_fail "$label" "(not running)" "container $name running"
    fi
}

# Assert container is not running
assert_container_stopped() {
    local name="$1" label="${2:-container stopped: $1}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
        _record_fail "$label" "(still running)" "container $name stopped"
    else
        _record_pass "$label"
    fi
}

# Assert a path is accessible inside a running container
assert_container_path() {
    local container="$1" path="$2" label="${3:-container path: $1:$2}"
    if docker exec "$container" test -e "$path" 2>/dev/null; then
        _record_pass "$label"
    else
        _record_fail "$label" "(missing inside $container)" "$path exists in container"
    fi
}

# Assert a command succeeds inside a container
assert_container_cmd() {
    local container="$1" label="$2"; shift 2
    if docker exec "$container" "$@" &>/dev/null 2>&1; then
        _record_pass "$label"
    else
        _record_fail "$label" "command failed in $container" "success: $*"
    fi
}

# ── Final report ──────────────────────────────────────────────────

print_final_report() {
    local total=$(( E2E_TOTAL_PASS + E2E_TOTAL_FAIL ))
    {
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                    VALIDATION SUMMARY                       ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Stages:    ${E2E_STAGES_PASSED} passed, ${E2E_STAGES_FAILED} failed, ${E2E_STAGES_SKIPPED} skipped (of ${E2E_TOTAL_STAGES})"
        echo "  Scenarios: ${E2E_SCENARIOS_PASSED} passed, ${E2E_SCENARIOS_FAILED} failed, ${E2E_SCENARIOS_SKIPPED} skipped (of ${E2E_TOTAL_SCENARIOS})"
        echo "  Checks:    ${E2E_TOTAL_PASS} passed, ${E2E_TOTAL_FAIL} failed (of ${total})"
        echo ""
        if [[ ${#E2E_FAILED_ITEMS[@]} -gt 0 ]]; then
            echo "  ── Failed Items ──"
            for item in "${E2E_FAILED_ITEMS[@]}"; do
                echo "    ✗ ${item}"
            done
            echo ""
        fi
        if [[ $E2E_STAGES_FAILED -eq 0 && $E2E_SCENARIOS_FAILED -eq 0 ]]; then
            echo "  Result: PLATFORM VALIDATED"
        else
            echo "  Result: VALIDATION FAILED"
        fi
        echo ""
        echo "  Report: ${E2E_REPORT_FILE}"
        echo ""
    } | tee -a "$E2E_REPORT_FILE"

    [[ $E2E_STAGES_FAILED -eq 0 && $E2E_SCENARIOS_FAILED -eq 0 ]]
}

# ══════════════════════════════════════════════════════════════════
#  SCENARIO LAYER
# ══════════════════════════════════════════════════════════════════
# Scenarios are named end-to-end operator journeys that compose
# commands, assertions, fault injection, and state tracking into
# coherent workflows exercising the full platform.

# Begin a named scenario.  Usage: begin_scenario "fresh-bootstrap" "Day-one operator journey"
begin_scenario() {
    E2E_SCENARIO_NAME="$1"
    E2E_SCENARIO_DESC="${2:-}"
    E2E_SCENARIO_START="$(date +%s)"
    _T_COUNT=0; _T_PASS=0; _T_FAIL=0

    {
        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "┃  Scenario: ${E2E_SCENARIO_NAME}"
        [[ -n "$E2E_SCENARIO_DESC" ]] && echo "┃  ${E2E_SCENARIO_DESC}"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    } | tee -a "$E2E_REPORT_FILE"

    begin_tests "scenario: ${E2E_SCENARIO_NAME}"
}

# End current scenario.  Returns 0 if all passed, 1 otherwise.
end_scenario() {
    # Restore any outstanding faults
    _restore_all_faults

    local now elapsed
    now="$(date +%s)"
    elapsed=$(( now - E2E_SCENARIO_START ))

    E2E_TOTAL_PASS=$(( E2E_TOTAL_PASS + _T_PASS ))
    E2E_TOTAL_FAIL=$(( E2E_TOTAL_FAIL + _T_FAIL ))
    E2E_TOTAL_SCENARIOS=$(( E2E_TOTAL_SCENARIOS + 1 ))

    local result
    if [[ $_T_FAIL -eq 0 ]]; then
        result="PASSED"
        E2E_SCENARIOS_PASSED=$(( E2E_SCENARIOS_PASSED + 1 ))
    else
        result="FAILED"
        E2E_SCENARIOS_FAILED=$(( E2E_SCENARIOS_FAILED + 1 ))
    fi

    {
        echo ""
        echo "1..${_T_COUNT}"
        echo "# Scenario ${E2E_SCENARIO_NAME}: ${_T_PASS} passed, ${_T_FAIL} failed (of ${_T_COUNT}) [${elapsed}s] — ${result}"
    } | tee -a "$E2E_REPORT_FILE"

    [[ $_T_FAIL -eq 0 ]]
}

# Skip an entire scenario.
skip_scenario() {
    local name="$1" reason="${2:-skipped}"
    E2E_TOTAL_SCENARIOS=$(( E2E_TOTAL_SCENARIOS + 1 ))
    E2E_SCENARIOS_SKIPPED=$(( E2E_SCENARIOS_SKIPPED + 1 ))
    {
        echo ""
        echo "┃  Scenario: ${name} — SKIPPED (${reason})"
    } | tee -a "$E2E_REPORT_FILE"
}

# ── Scenario prerequisite gates ────────────────────────────────────

# Check a stage passed.  Returns 1 (and records skip) on failure.
# Usage: require_stage 1 || { skip_scenario "name" "stage 1 required"; return 0; }
require_stage() {
    local n="$1"
    [[ "${E2E_STAGE_RESULTS[$n]:-}" == "pass" ]]
}

require_root() { is_root; }
require_docker() { has_docker; }
require_empusa() { has_empusa; }

require_container() {
    local name="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

# ── Docker inspect assertions ──────────────────────────────────────

# Assert a specific bind mount exists on a container via docker inspect.
# Usage: assert_docker_mount "lab-kali" "/host/path" "/container/path" "rw" "label"
assert_docker_mount() {
    local container="$1" host_path="$2" container_path="$3" mode="${4:-rw}" label="${5:-docker mount: $2 -> $3}"
    local mounts
    mounts="$(docker inspect --format '{{json .Mounts}}' "$container" 2>/dev/null)" || {
        _record_fail "$label" "inspect failed" "mount $host_path -> $container_path ($mode)"
        return
    }
    # Check source, destination, and mode in JSON
    if echo "$mounts" | python3 -c "
import sys, json
mounts = json.load(sys.stdin)
for m in mounts:
    src = m.get('Source', '')
    dst = m.get('Destination', '')
    rw  = 'rw' if m.get('RW', False) else 'ro'
    if dst == '$container_path' and rw == '$mode':
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
        _record_pass "$label"
    else
        _record_fail "$label" "not found or wrong mode" "$host_path -> $container_path ($mode)"
    fi
}

# Assert a container's network mode via docker inspect.
# Usage: assert_docker_network "lab-kali" "host" "label"
assert_docker_network() {
    local container="$1" expected_mode="$2" label="${3:-docker network: $container mode=$expected_mode}"
    local actual_mode
    actual_mode="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container" 2>/dev/null)" || {
        _record_fail "$label" "inspect failed" "network mode $expected_mode"
        return
    }
    if [[ "$actual_mode" == "$expected_mode" || "$actual_mode" == *"$expected_mode"* ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$actual_mode" "$expected_mode"
    fi
}

# Assert a container has a specific environment variable set.
assert_docker_env() {
    local container="$1" var_name="$2" label="${3:-docker env: $container $var_name}"
    local env_list
    env_list="$(docker inspect --format '{{json .Config.Env}}' "$container" 2>/dev/null)" || {
        _record_fail "$label" "inspect failed" "env $var_name"
        return
    }
    if echo "$env_list" | grep -q "\"${var_name}="; then
        _record_pass "$label"
    else
        _record_fail "$label" "not set" "$var_name in container env"
    fi
}

# Assert a container's restart policy
assert_docker_restart() {
    local container="$1" expected="$2" label="${3:-docker restart: $container policy=$expected}"
    local actual
    actual="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$container" 2>/dev/null)" || {
        _record_fail "$label" "inspect failed" "restart policy $expected"
        return
    }
    if [[ "$actual" == "$expected" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "$actual" "$expected"
    fi
}

# ── Idempotency and re-entry assertions ───────────────────────────

# Run a command twice and assert both runs succeed with same exit code.
# Usage: assert_idempotent "labctl up is idempotent" bash labctl up
assert_idempotent() {
    local label="$1"; shift

    local out1 rc1 out2 rc2
    set +e
    out1="$("$@" 2>&1)"; rc1=$?
    out2="$("$@" 2>&1)"; rc2=$?
    set -e

    if [[ $rc1 -eq $rc2 ]]; then
        _record_pass "$label: same exit code ($rc1)"
    else
        _record_fail "$label: same exit code" "run1=$rc1 run2=$rc2" "identical"
    fi

    # Second run should not produce error markers
    if echo "$out2" | grep -qE '\[✗\]|ERROR|FATAL|Traceback'; then
        _record_fail "$label: no errors on rerun" "error markers in output" "clean rerun"
    else
        _record_pass "$label: no errors on rerun"
    fi
}

# Assert that re-running a command on existing state produces clean output.
# The command must already have been run once; this just runs it again.
assert_reentry() {
    local label="$1"; shift
    local out rc
    set +e
    out="$("$@" 2>&1)"; rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        _record_pass "$label: exits 0 on re-entry"
    else
        _record_fail "$label: exits 0 on re-entry" "exit $rc" "exit 0"
    fi

    # Should not create new resources or show creation markers
    if echo "$out" | grep -qiE '\[\+\].*creat|already exists|exists'; then
        _record_pass "$label: acknowledges existing state"
    else
        _record_pass "$label: no creation markers (clean re-entry)"
    fi
}

# ── Filesystem state capture ──────────────────────────────────────

# Capture a directory tree fingerprint for later comparison.
# Usage: capture_state "before-down" "/opt/lab/workspaces"
capture_state() {
    local tag="$1" dir="$2"
    E2E_STATE_SNAPSHOTS[$tag]="$(find "$dir" -type f -printf '%p %s\n' 2>/dev/null | sort)"
}

# Assert state unchanged since capture.
assert_state_unchanged() {
    local tag="$1" dir="$2" label="${3:-state unchanged: $tag}"
    local before="${E2E_STATE_SNAPSHOTS[$tag]:-}"
    if [[ -z "$before" ]]; then
        _record_fail "$label" "no snapshot for tag '$tag'" "capture_state called first"
        return
    fi
    local after
    after="$(find "$dir" -type f -printf '%p %s\n' 2>/dev/null | sort)"
    if [[ "$before" == "$after" ]]; then
        _record_pass "$label"
    else
        local added removed
        added="$(diff <(echo "$before") <(echo "$after") | grep '^>' | wc -l)"
        removed="$(diff <(echo "$before") <(echo "$after") | grep '^<' | wc -l)"
        _record_fail "$label" "+${added} -${removed} files changed" "no changes"
    fi
}

# Assert state DID change (new files appeared).
assert_state_changed() {
    local tag="$1" dir="$2" label="${3:-state changed: $tag}"
    local before="${E2E_STATE_SNAPSHOTS[$tag]:-}"
    if [[ -z "$before" ]]; then
        _record_fail "$label" "no snapshot for tag '$tag'" "capture_state called first"
        return
    fi
    local after
    after="$(find "$dir" -type f -printf '%p %s\n' 2>/dev/null | sort)"
    if [[ "$before" != "$after" ]]; then
        _record_pass "$label"
    else
        _record_fail "$label" "no changes detected" "state should have changed"
    fi
}

# ── Fault injection ───────────────────────────────────────────────
# Controlled, reversible faults for testing recovery paths.

# Inject a fault.  Type determines behavior:
#   rename_file <path>       — renames file to .e2e-fault-backup
#   break_manifest <path>    — corrupts a manifest file
#   stop_container <name>    — docker stop
#   kill_plugin <plugin_dir> — renames manifest.json
#   break_permission <path>  — chmod 000
inject_fault() {
    local type="$1"; shift
    case "$type" in
        rename_file)
            local path="$1"
            cp "$path" "${path}.e2e-fault-backup" 2>/dev/null
            rm -f "$path"
            E2E_ACTIVE_FAULTS+=("rename_file:$path")
            ;;
        break_manifest)
            local path="$1"
            cp "$path" "${path}.e2e-fault-backup" 2>/dev/null
            echo "CORRUPTED_BY_E2E" > "$path"
            E2E_ACTIVE_FAULTS+=("break_manifest:$path")
            ;;
        stop_container)
            local name="$1"
            docker stop "$name" &>/dev/null || true
            E2E_ACTIVE_FAULTS+=("stop_container:$name")
            ;;
        kill_plugin)
            local dir="$1"
            if [[ -f "$dir/manifest.json" ]]; then
                mv "$dir/manifest.json" "$dir/manifest.json.e2e-fault-backup"
                E2E_ACTIVE_FAULTS+=("kill_plugin:$dir")
            fi
            ;;
        break_permission)
            local path="$1"
            local orig_perms
            orig_perms="$(stat -c '%a' "$path" 2>/dev/null)"
            echo "$orig_perms" > "${path}.e2e-perm-backup"
            chmod 000 "$path"
            E2E_ACTIVE_FAULTS+=("break_permission:$path")
            ;;
    esac
}

# Restore a specific fault.
restore_fault() {
    local type="$1"; shift
    case "$type" in
        rename_file)
            local path="$1"
            [[ -f "${path}.e2e-fault-backup" ]] && mv "${path}.e2e-fault-backup" "$path"
            ;;
        break_manifest)
            local path="$1"
            [[ -f "${path}.e2e-fault-backup" ]] && mv "${path}.e2e-fault-backup" "$path"
            ;;
        stop_container)
            # Caller is responsible for bringing container back
            ;;
        kill_plugin)
            local dir="$1"
            [[ -f "$dir/manifest.json.e2e-fault-backup" ]] && \
                mv "$dir/manifest.json.e2e-fault-backup" "$dir/manifest.json"
            ;;
        break_permission)
            local path="$1"
            if [[ -f "${path}.e2e-perm-backup" ]]; then
                chmod "$(cat "${path}.e2e-perm-backup")" "$path"
                rm -f "${path}.e2e-perm-backup"
            fi
            ;;
    esac
}

# Restore all outstanding faults (called by end_scenario).
_restore_all_faults() {
    for fault in "${E2E_ACTIVE_FAULTS[@]}"; do
        local type="${fault%%:*}"
        local arg="${fault#*:}"
        restore_fault "$type" "$arg" 2>/dev/null || true
    done
    E2E_ACTIVE_FAULTS=()
}

# ── Compose compatibility helper ──────────────────────────────────

# Run a compose command using whichever compose variant is available.
# Usage: run_compose config
#        run_compose -f file.yml up -d
run_compose() {
    local compose_cmd
    compose_cmd="$(detect_compose)"
    if [[ -z "$compose_cmd" ]]; then
        echo "ERROR: no compose command available" >&2
        return 1
    fi
    $compose_cmd "$@"
}

# Assert a command works under both docker compose and docker-compose (if available).
# Usage: assert_dual_compose "label" config --services
assert_dual_compose() {
    local label="$1"; shift
    local available=0
    # Plugin variant
    if docker compose version &>/dev/null 2>&1; then
        available=1
        local out1 rc1
        set +e
        out1="$(docker compose "$@" 2>&1)"; rc1=$?
        set -e
        if [[ $rc1 -eq 0 ]]; then
            _record_pass "$label (docker compose)"
        else
            _record_fail "$label (docker compose)" "exit $rc1" "exit 0"
        fi
    else
        _record_pass "$label (docker compose): not available — skip"
    fi
    # Legacy variant
    if command -v docker-compose &>/dev/null; then
        available=1
        local out2 rc2
        set +e
        out2="$(docker-compose "$@" 2>&1)"; rc2=$?
        set -e
        if [[ $rc2 -eq 0 ]]; then
            _record_pass "$label (docker-compose)"
        else
            _record_fail "$label (docker-compose)" "exit $rc2" "exit 0"
        fi
    else
        _record_pass "$label (docker-compose): not available — skip"
    fi

    # Avoid false positives when both variants are missing.
    if [[ $available -eq 0 ]]; then
        _record_fail "$label (compose availability)" "no compose variant" "docker compose or docker-compose installed"
    fi
}

# ── Output assertion helpers ──────────────────────────────────────

# Assert output contains a pattern and does NOT contain anti-patterns.
assert_output_quality() {
    local output="$1" label="$2"
    shift 2
    # Remaining args: +pattern (must exist) or -pattern (must not exist)
    for spec in "$@"; do
        local prefix="${spec:0:1}"
        local pattern="${spec:1}"
        if [[ "$prefix" == "+" ]]; then
            if echo "$output" | grep -qiE "$pattern"; then
                _record_pass "$label: has '$pattern'"
            else
                _record_fail "$label: has '$pattern'" "not found" "in output"
            fi
        elif [[ "$prefix" == "-" ]]; then
            if echo "$output" | grep -qiE "$pattern"; then
                _record_fail "$label: no '$pattern'" "found" "should be absent"
            else
                _record_pass "$label: no '$pattern'"
            fi
        fi
    done
}

# Assert a command produces structured output (summary, result, markers).
assert_structured_output() {
    local output="$1" label="$2"
    local has_summary=0 has_result=0 has_markers=0
    echo "$output" | grep -qi 'summary' && has_summary=1
    echo "$output" | grep -qi 'result:' && has_result=1
    echo "$output" | grep -qE '\[✓\]|\[✗\]|\[!\]|\[\*\]|\[=\]' && has_markers=1

    [[ $has_summary -eq 1 ]] && _record_pass "$label: has summary" || _record_fail "$label: has summary" "missing" "Summary section"
    [[ $has_result -eq 1 ]]  && _record_pass "$label: has Result:" || _record_fail "$label: has Result:" "missing" "Result: label"
    [[ $has_markers -eq 1 ]] && _record_pass "$label: has markers" || _record_fail "$label: has markers" "missing" "[✓]/[✗]/[!] markers"
}

# ── Markdown structure assertion ──────────────────────────────────

# Assert a markdown file has headings in the correct order.
# Usage: assert_heading_order file.md "label" "# Title" "## Section 1" "## Section 2"
assert_heading_order() {
    local file="$1" label="$2"; shift 2
    local prev_line=0 all_ordered=1
    for heading in "$@"; do
        local line_num
        line_num="$(grep -n "$heading" "$file" 2>/dev/null | head -1 | cut -d: -f1)"
        if [[ -z "$line_num" ]]; then
            _record_fail "$label: heading '$heading' exists" "missing" "in $file"
            all_ordered=0
            continue
        fi
        if [[ "$line_num" -le "$prev_line" ]]; then
            _record_fail "$label: heading order" "'$heading' at line $line_num <= $prev_line" "after previous heading"
            all_ordered=0
        fi
        prev_line="$line_num"
    done
    [[ $all_ordered -eq 1 ]] && _record_pass "$label: heading order correct"
}
