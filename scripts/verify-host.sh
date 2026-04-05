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

# ── Counters ───────────────────────────────────────────────────────
PASS=0
WARN=0
FAIL=0

# ── Output helpers ─────────────────────────────────────────────────
_pass() { ((PASS++)) || true; printf "  [PASS]  %s\n" "$*"; }
_warn() { ((WARN++)) || true; printf "  [WARN]  %s\n" "$*"; }
_fail() { ((FAIL++)) || true; printf "  [FAIL]  %s\n" "$*"; }
banner() { echo ""; echo "── $1 ──"; }

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
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════
#  3. Docker health
# ═══════════════════════════════════════════════════════════════════
check_docker() {
    banner "3/9  Docker health"

    # Daemon reachable
    if docker info &>/dev/null; then
        _pass "Docker daemon reachable"
    else
        _fail "Docker daemon unreachable (is dockerd running?)"
        return  # No point checking compose if daemon is down
    fi

    # Compose plugin
    if docker compose version &>/dev/null; then
        local cver
        cver="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -1)"
        _pass "docker compose plugin - ${cver}"
    else
        _fail "docker compose plugin not available"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  4. /opt/lab layout
# ═══════════════════════════════════════════════════════════════════
check_lab_layout() {
    banner "4/9  ${LAB_ROOT} directory tree"

    if [[ ! -d "$LAB_ROOT" ]]; then
        _fail "${LAB_ROOT} does not exist (run: sudo labctl bootstrap)"
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
}

# ═══════════════════════════════════════════════════════════════════
#  5. Repository files
# ═══════════════════════════════════════════════════════════════════
check_repo_files() {
    banner "5/9  Repository files"

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

    # tmux profiles
    local profiles_found=0
    if [[ -d "${REPO_DIR}/tmux/profiles" ]]; then
        profiles_found="$(find "${REPO_DIR}/tmux/profiles" -name '*.sh' -type f | wc -l)"
    fi
    if [[ "$profiles_found" -gt 0 ]]; then
        _pass "tmux profiles - ${profiles_found} found"
    else
        _warn "No tmux profiles found under tmux/profiles/"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  6. Empusa installation
# ═══════════════════════════════════════════════════════════════════
check_empusa() {
    banner "6/9  Empusa"
    local empusa_bin="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"

    if [[ -x "$empusa_bin" ]]; then
        local ver
        ver="$("$empusa_bin" --version 2>/dev/null || echo "version unknown")"
        _pass "empusa installed - ${ver}"
    else
        _warn "empusa not found at ${empusa_bin} (labctl workspace will use shell fallback)"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  7. Binary sync destination
# ═══════════════════════════════════════════════════════════════════
check_binaries() {
    banner "7/9  Binary sync destination"
    local bin_dir="${LAB_ROOT}/tools/binaries"

    if [[ -d "$bin_dir" ]]; then
        _pass "${bin_dir} exists"
    else
        _fail "${bin_dir} missing"
        return
    fi

    # Chisel check (representative synced asset)
    if compgen -G "${bin_dir}/chisel"'*' &>/dev/null || [[ -d "${bin_dir}/chisel" ]]; then
        local count
        count="$(find "${bin_dir}/chisel" -type f 2>/dev/null | wc -l)"
        _pass "chisel assets present (${count} files)"
    else
        _warn "No chisel assets found - run: labctl sync"
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  8. GPU (optional)
# ═══════════════════════════════════════════════════════════════════
check_gpu() {
    banner "8/9  GPU"

    if ! command -v nvidia-smi &>/dev/null; then
        if [[ "${LAB_GPU:-0}" == "1" ]]; then
            _fail "LAB_GPU=1 but nvidia-smi not found"
        else
            _warn "nvidia-smi not found - GPU passthrough unavailable"
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
    else
        if [[ "${LAB_GPU:-0}" == "1" ]]; then
            _fail "LAB_GPU=1 but NVIDIA container toolkit not found"
        else
            _warn "NVIDIA container toolkit not installed"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════
#  9. Summary
# ═══════════════════════════════════════════════════════════════════
print_summary() {
    banner "Summary"
    printf "  PASS: %d  |  WARN: %d  |  FAIL: %d\n" "$PASS" "$WARN" "$FAIL"
    echo ""

    if [[ "$FAIL" -gt 0 ]]; then
        echo "  ✗ Host is NOT ready - fix the FAIL items above."
        echo "    Most can be resolved with:  sudo labctl bootstrap"
    elif [[ "$WARN" -gt 0 ]]; then
        echo "  ~ Host is usable but has warnings.  Review items above."
    else
        echo "  ✓ Host is ready.  Run: labctl up"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
main() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║  Hecate · Host verification · $(date +%F)                  ║"
    echo "╚═══════════════════════════════════════════════════════════╝"

    check_os
    check_commands
    check_docker
    check_lab_layout
    check_repo_files
    check_empusa
    check_binaries
    check_gpu
    print_summary

    if [[ "$FAIL" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
