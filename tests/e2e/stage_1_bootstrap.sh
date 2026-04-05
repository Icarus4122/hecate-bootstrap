#!/usr/bin/env bash
# tests/e2e/stage_1_bootstrap.sh - Bootstrap validation.
#
# Requires: root (sudo).  Validates that bootstrap-host.sh creates the
# full /opt/lab tree, installs packages, configures Docker, seeds .env,
# installs Empusa, and symlinks labctl.
#
# DESTRUCTIVE: Modifies /opt/lab on a real host.  Only run on a fresh
# system or one you intend to (re-)provision.

begin_stage 1 "Bootstrap"

# ═══════════════════════════════════════════════════════════════════
#  1.1  Run bootstrap
# ═══════════════════════════════════════════════════════════════════
section "Execute bootstrap-host.sh"

bootstrap_out="$(bash "$REPO_ROOT/scripts/bootstrap-host.sh" 2>&1)" || true
bootstrap_rc=$?

# Bootstrap should exit 0
assert_eq "0" "$bootstrap_rc" "bootstrap: exits 0"

# ═══════════════════════════════════════════════════════════════════
#  1.2  /opt/lab directory tree
# ═══════════════════════════════════════════════════════════════════
section "Lab Root Directory Tree"

LAB="${LAB_ROOT:-/opt/lab}"
assert_dir_exists "$LAB" "lab root: $LAB"

for d in data tools tools/binaries tools/git tools/venvs \
         resources workspaces knowledge templates; do
    assert_dir_exists "$LAB/$d" "lab dir: $d"
done

# Ownership: should be SUDO_USER or the current real user
real_user="${SUDO_USER:-$(whoami)}"
owner="$(stat -c '%U' "$LAB" 2>/dev/null || echo unknown)"
assert_eq "$real_user" "$owner" "lab root: owned by $real_user"

# ═══════════════════════════════════════════════════════════════════
#  1.3  Host packages installed
# ═══════════════════════════════════════════════════════════════════
section "Host Packages"

for pkg in docker git curl jq file python3 tmux wget; do
    if command -v "$pkg" &>/dev/null; then
        _record_pass "host pkg: $pkg"
    else
        _record_fail "host pkg: $pkg" "(not found)" "installed"
    fi
done

# Docker specifically
if docker info &>/dev/null 2>&1; then
    _record_pass "Docker: daemon running post-bootstrap"
else
    _record_fail "Docker: daemon running post-bootstrap" "unreachable" "running"
fi

if docker compose version &>/dev/null 2>&1; then
    _record_pass "Docker: compose plugin installed"
else
    _record_fail "Docker: compose plugin installed" "missing" "docker compose"
fi

# ═══════════════════════════════════════════════════════════════════
#  1.4  .env file seeded
# ═══════════════════════════════════════════════════════════════════
section "Environment File"

assert_file_exists "$REPO_ROOT/.env" "config: .env exists"
if [[ -f "$REPO_ROOT/.env" ]]; then
    assert_file_contains "$REPO_ROOT/.env" "LAB_ROOT" "config: .env has LAB_ROOT"
    assert_file_contains "$REPO_ROOT/.env" "COMPOSE_PROJECT_NAME" "config: .env has COMPOSE_PROJECT_NAME"
fi

# ═══════════════════════════════════════════════════════════════════
#  1.5  Empusa installation
# ═══════════════════════════════════════════════════════════════════
section "Empusa Installation"

empusa_bin="$LAB/tools/venvs/empusa/bin/empusa"
if [[ -x "$empusa_bin" ]]; then
    _record_pass "Empusa: binary exists and executable"
    ver="$("$empusa_bin" --version 2>&1 || echo "unknown")"
    if [[ "$ver" != "unknown" ]]; then
        _record_pass "Empusa: --version returns ($ver)"
    else
        _record_fail "Empusa: --version" "unknown" "version string"
    fi
else
    _record_fail "Empusa: binary exists" "missing" "$empusa_bin"
fi

empusa_repo="$LAB/tools/git/empusa"
assert_dir_exists "$empusa_repo" "Empusa: repo cloned to tools/git/empusa"
if [[ -d "$empusa_repo/.git" ]]; then
    _record_pass "Empusa: repo has .git"
else
    _record_fail "Empusa: repo has .git" "missing" ".git in empusa repo"
fi

# ═══════════════════════════════════════════════════════════════════
#  1.6  labctl symlink
# ═══════════════════════════════════════════════════════════════════
section "labctl Symlink"

if [[ -L /usr/local/bin/labctl ]]; then
    assert_symlink "/usr/local/bin/labctl" "$REPO_ROOT/labctl" "labctl: symlink correct"
else
    _record_fail "labctl: /usr/local/bin/labctl is symlink" "not a symlink" "symlink"
fi

# labctl should be callable from PATH
if command -v labctl &>/dev/null; then
    _record_pass "labctl: in PATH"
else
    _record_fail "labctl: in PATH" "not found" "labctl on PATH"
fi

# ═══════════════════════════════════════════════════════════════════
#  1.7  GPU (conditional)
# ═══════════════════════════════════════════════════════════════════
section "GPU (optional)"

if has_gpu; then
    _record_pass "GPU: nvidia-smi available"
    # Check nvidia-container-toolkit
    if command -v nvidia-ctk &>/dev/null; then
        _record_pass "GPU: nvidia-ctk installed"
    else
        _record_fail "GPU: nvidia-ctk installed" "missing" "nvidia-ctk"
    fi
    # Check Docker runtime
    if docker info 2>/dev/null | grep -qi nvidia; then
        _record_pass "GPU: NVIDIA runtime registered with Docker"
    else
        _record_fail "GPU: NVIDIA runtime registered" "not found" "nvidia in docker info"
    fi
else
    _record_pass "GPU: no NVIDIA hardware (skip GPU checks)"
fi

# ═══════════════════════════════════════════════════════════════════
#  1.8  Bootstrap output quality
# ═══════════════════════════════════════════════════════════════════
section "Bootstrap Output"

assert_contains "$bootstrap_out" "Summary" "bootstrap output: has Summary"
assert_contains "$bootstrap_out" "Result:" "bootstrap output: has Result:"

end_stage
