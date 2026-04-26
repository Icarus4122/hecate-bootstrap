#!/usr/bin/env bash
# scripts/verify-host.sh - Pre-flight checks for the lab host.
#
# Verifies that the Ubuntu 24.04 host is ready to run the full lab
# environment.  Catches path drift, missing dependencies, Docker
# issues, GPU runtime gaps, and Empusa installation problems before
# launch.
#
# This script is read-only - it does NOT modify the system or
# attempt to fix anything it finds.
#
# Usage:
#   bash scripts/verify-host.sh          Run all checks
#   bash scripts/verify-host.sh --strict Promote selected release/CI
#                                        readiness warnings to failures
#   bash scripts/verify-host.sh --help   Show usage
#   labctl verify                        (after adding dispatch - see below)
#   LAB_GPU=1 bash scripts/verify-host.sh   Include GPU runtime checks
#
# Exit codes:
#   0  All critical checks passed (warnings may still be present)
#   1  One or more critical checks failed
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_ROOT="${LAB_ROOT:-/opt/lab}"

# ── Mode flags ─────────────────────────────────────────────────────
STRICT_MODE=0

usage() {
    cat <<'USAGE'
Usage: verify-host.sh [--strict] [--help]

Read-only host pre-flight checks for the Hecate lab.

Options:
  --strict   Promote selected release/CI readiness warnings to
             [FAIL] (missing .env, missing tmux profiles, unsynced
             chisel binaries). Hard failures already in default mode
             remain hard failures. Intended for release/CI gating;
             default mode stays operator-friendly.
  --help     Show this message and exit.

Environment:
  LAB_ROOT   Root of the lab tree (default: /opt/lab)
  LAB_GPU    Set to 1 to require NVIDIA driver/runtime
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --strict) STRICT_MODE=1 ;;
        --help|-h) usage; exit 0 ;;
        *)
            printf '[FAIL] Unknown argument: %s\n' "$arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# ── Shared UI primitives ──────────────────────────────────────────
source "${REPO_DIR}/scripts/lib/ui.sh"

# ── Counters ───────────────────────────────────────────────────────
PASS=0
WARN=0
FAIL=0

# ── Failure log (reprinted in summary) ─────────────────────────────
declare -a FAIL_LOG=()
declare -a WARN_LOG=()

# ── Output helpers (wrap shared ui.sh + track counters) ─────────────
_pass() { ((PASS++)) || true; ui_pass "$*"; }
_warn() { ((WARN++)) || true; ui_warn "$*"; WARN_LOG+=("$*"); }
_fail() { ((FAIL++)) || true; ui_fail "$*"; FAIL_LOG+=("$*"); }
_fix()  { ui_fix "$*"; }
_note() { ui_note "$*"; }
banner() { ui_section "$1"; }

# Promote a warning to a failure under --strict.  In default mode it
# behaves exactly like _warn; under STRICT_MODE=1 it becomes _fail and
# contributes to the nonzero exit. Used only for clear release/CI
# readiness gaps (missing .env, missing tmux profiles, unsynced
# binaries). Hard failures already in default mode remain _fail
# unconditionally.
_strict_warn() {
    if [[ "${STRICT_MODE:-0}" == "1" ]]; then
        _fail "$*"
    else
        _warn "$*"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  1. Host OS
# ═══════════════════════════════════════════════════════════════════
check_os() {
    banner "1/9  Host OS"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        local desc="${PRETTY_NAME:-unknown}"
        if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
            _pass "Ubuntu 24.04 LTS (${desc})"
        else
            _warn "Expected Ubuntu 24.04 LTS - found: ${desc}"
            _note "Hecate is tested on Ubuntu 24.04.  Other distros may work"
            _note "but are not officially supported."
        fi
    else
        _warn "/etc/os-release not found - cannot determine host OS"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  2. Required host commands
# ═══════════════════════════════════════════════════════════════════
check_commands() {
    banner "2/9  Required host commands"
    local cmds=(docker git curl jq file python3)
    for cmd in "${cmds[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            local ver=""
            case "$cmd" in
                docker)  ver="$(docker --version 2>/dev/null | head -1)" ;;
                git)     ver="$(git --version 2>/dev/null)" ;;
                python3) ver="$(python3 --version 2>/dev/null)" ;;
                curl)    ver="$(curl --version 2>/dev/null | head -1)" ;;
                jq)      ver="$(jq --version 2>/dev/null)" ;;
                *)       ver="found" ;;
            esac
            _pass "${cmd} - ${ver}"
        else
            _fail "${cmd} not found"
            _fix "sudo apt install ${cmd}"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════
#  3. Docker health
# ═══════════════════════════════════════════════════════════════════
check_docker() {
    banner "3/9  Docker health"
    if docker info &>/dev/null; then
        _pass "Docker daemon is reachable"
    else
        _fail "Docker daemon unreachable"
        _note "Docker may not be running, or the current user is not in the docker group."
        _fix "sudo systemctl start docker"
        _fix "sudo usermod -aG docker \$USER && newgrp docker"
    fi

    if docker compose version >/dev/null 2>&1; then
        _pass "Docker Compose plugin available"
    elif docker-compose --version >/dev/null 2>&1; then
        _warn "Legacy docker-compose found, but Docker Compose plugin is not available"
        _note "labctl works with both, but the Compose plugin is recommended."
        _fix "sudo apt install docker-compose-plugin"
    else
        _fail "Docker Compose not found (neither plugin nor standalone)"
        _fix "sudo apt install docker-compose-plugin"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  4. /opt/lab layout
# ═══════════════════════════════════════════════════════════════════
check_lab_layout() {
    banner "4/9  ${LAB_ROOT} directory tree"

    if [[ ! -d "$LAB_ROOT" ]]; then
        _fail "${LAB_ROOT} does not exist"
        _note "The lab host has not been provisioned yet."
        _fix "sudo labctl bootstrap"
        return
    fi
    _pass "${LAB_ROOT} exists"

    local required_dirs=(
        data
        tools
        tools/binaries
        tools/git
        tools/venvs
        resources
        workspaces
        knowledge
        templates
    )
    for d in "${required_dirs[@]}"; do
        if [[ -d "${LAB_ROOT}/${d}" ]]; then
            _pass "${LAB_ROOT}/${d}"
        else
            _fail "${LAB_ROOT}/${d} missing"
        fi
    done

    # If any dirs were missing, print one remediation line.
    if [[ "$FAIL" -gt 0 ]]; then
        _fix "sudo labctl bootstrap   (re-creates the full directory tree)"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  5. Repository files
# ═══════════════════════════════════════════════════════════════════
check_repo_files() {
    banner "5/9  Repository files"

    local _pre_fail_count=$FAIL
    local files=(
        compose/docker-compose.yml
        compose/docker-compose.gpu.yml
        compose/docker-compose.hostnet.yml
        docker/kali-main/Dockerfile
        docker/builder/Dockerfile
        manifests/binaries.tsv
    )
    for f in "${files[@]}"; do
        if [[ -f "${REPO_DIR}/${f}" ]]; then
            _pass "${f}"
        else
            _fail "${f} missing from repo"
        fi
    done

    # Collective remediation if any repo files are missing.
    local repo_fails=$((FAIL - _pre_fail_count))
    if [[ "$repo_fails" -gt 0 ]]; then
        _note "Missing repo files break compose, build, or sync operations."
        _fix "git -C ${REPO_DIR} checkout -- <file>   or re-clone the repo"
    fi

    # tmux profiles
    local profiles_found=0
    if [[ -d "${REPO_DIR}/tmux/profiles" ]]; then
        profiles_found="$(find "${REPO_DIR}/tmux/profiles" -name '*.sh' -type f | wc -l)"
    fi
    if [[ "$profiles_found" -gt 0 ]]; then
        _pass "tmux profiles - ${profiles_found} found"
    else
        _strict_warn "No tmux profiles found under tmux/profiles/"
        _note "labctl launch will not be able to set up tmux sessions."
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  6. Empusa installation
# ═══════════════════════════════════════════════════════════════════
check_empusa() {
    banner "6/9  Empusa (workspace engine)"
    local empusa_bin="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"

    if [[ -x "$empusa_bin" ]]; then
        local ver
        ver="$("$empusa_bin" --version 2>/dev/null || echo "version unknown")"
        _pass "empusa installed - ${ver}"
    else
        _warn "empusa not found at ${empusa_bin}"
        _note "Without Empusa, labctl workspace creates a minimal directory"
        _note "scaffold instead of full profiled workspaces."
        _fix "bash scripts/install-empusa.sh install"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  7. Binary sync destination
# ═══════════════════════════════════════════════════════════════════
check_binaries() {
    banner "7/9  Synced binaries"
    local bin_dir="${LAB_ROOT}/tools/binaries"

    if [[ -d "$bin_dir" ]]; then
        _pass "${bin_dir} exists"
    else
        _fail "${bin_dir} missing"
        _fix "sudo labctl bootstrap   (creates the directory tree)"
        return
    fi

    # Chisel check (representative synced asset)
    if compgen -G "${bin_dir}/chisel"'*' &>/dev/null || [[ -d "${bin_dir}/chisel" ]]; then
        local count
        count="$(find "${bin_dir}/chisel" -type f 2>/dev/null | wc -l)"
        _pass "chisel assets present (${count} files)"
    else
        _strict_warn "No chisel assets found — binaries have not been synced yet"
        _fix "labctl sync"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  8. GPU (optional)
# ═══════════════════════════════════════════════════════════════════
check_gpu() {
    banner "8/9  GPU (optional)"

    if ! command -v nvidia-smi &>/dev/null; then
        if [[ "${LAB_GPU:-0}" == "1" ]]; then
            _fail "LAB_GPU=1 but nvidia-smi not found"
            _note "GPU passthrough was requested but the NVIDIA driver is missing."
            _fix "Install the NVIDIA driver, then: bash scripts/setup-nvidia.sh"
        else
            _warn "nvidia-smi not found — GPU passthrough unavailable"
            _note "Not needed unless you plan to use hashcat or GPU workloads."
            _note "To enable later: install the NVIDIA driver, then: bash scripts/setup-nvidia.sh"
        fi
        return
    fi

    # nvidia-smi is available - report GPU info
    local gpu_info
    gpu_info="$(nvidia-smi --query-gpu=name,driver_version,memory.total \
                    --format=csv,noheader 2>/dev/null || true)"
    if [[ -n "$gpu_info" ]]; then
        _pass "GPU detected: ${gpu_info}"
    else
        _warn "nvidia-smi present but returned no GPU data"
    fi

    # NVIDIA container runtime
    if docker info 2>/dev/null | grep -qi "nvidia"; then
        _pass "NVIDIA container runtime registered with Docker"
    elif command -v nvidia-ctk &>/dev/null; then
        local ctk_ver
        ctk_ver="$(nvidia-ctk --version 2>/dev/null | head -1 || echo "version unknown")"
        _warn "nvidia-ctk present (${ctk_ver}) but runtime not visible in docker info"
        _fix "sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
    else
        if [[ "${LAB_GPU:-0}" == "1" ]]; then
            _fail "LAB_GPU=1 but NVIDIA container toolkit not found"
            _fix "bash scripts/setup-nvidia.sh"
        else
            _warn "NVIDIA container toolkit not installed"
            _note "Required only if you want GPU passthrough (labctl up --gpu)."
            _fix "bash scripts/setup-nvidia.sh"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  9. .env file
# ═══════════════════════════════════════════════════════════════════
check_env_file() {
    banner "9/9  Configuration"

    if [[ -f "${REPO_DIR}/.env" ]]; then
        _pass ".env file present"
    else
        _strict_warn ".env file not found"
        _note "labctl uses .env for LAB_ROOT, GPU, and token settings."
        _fix "cp .env.example .env   (then edit as needed)"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════════
print_summary() {
    ui_summary_line
    printf "  %d passed   %d warnings   %d failed\n" "$PASS" "$WARN" "$FAIL"

    # Reprint failures so the operator doesn't have to scroll
    if [[ "$FAIL" -gt 0 ]]; then
        echo ""
        echo "  Failed checks:"
        for msg in "${FAIL_LOG[@]}"; do
            printf "    [FAIL] %s\n" "$msg"
        done
    fi

    echo ""
    if [[ "$FAIL" -gt 0 ]]; then
        echo "  Result: Host is NOT ready — fix the failed items above."
        ui_next_block "sudo labctl bootstrap" "labctl verify"
    elif [[ "$WARN" -gt 0 ]]; then
        echo "  Result: Host is usable but has warnings."
        ui_next_block "labctl build" "labctl up"
    else
        echo "  Result: Host is ready."
        ui_next_block "labctl build" "labctl up" "labctl launch default"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
main() {
    ui_banner "Hecate" "Host verification"
    echo ""
    if [[ "${STRICT_MODE:-0}" == "1" ]]; then
        ui_info "Strict mode: selected readiness warnings will be promoted to [FAIL]."
    fi
    ui_info "This check is read-only — it will not modify your system."

    check_os
    check_commands
    check_docker
    check_lab_layout
    check_repo_files
    check_empusa
    check_binaries
    check_gpu
    check_env_file
    print_summary

    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
