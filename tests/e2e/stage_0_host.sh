#!/usr/bin/env bash
# tests/e2e/stage_0_host.sh - Host prerequisite validation.
#
# Validates: OS, kernel, required commands, filesystem, repo integrity.
# No root, no Docker, no network required.

begin_stage 0 "Host Prerequisites"

# ═══════════════════════════════════════════════════════════════════
#  0.1  Operating system
# ═══════════════════════════════════════════════════════════════════
section "Operating System"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    assert_eq "ubuntu" "$ID" "OS: Ubuntu"
    assert_eq "24.04" "$VERSION_ID" "OS: 24.04 LTS"
else
    _record_fail "OS: /etc/os-release exists" "(missing)" "/etc/os-release"
fi

# Kernel must be 5.x or 6.x (for Docker overlay2 + cgroup v2)
kernel_major="$(uname -r | cut -d. -f1)"
if [[ "$kernel_major" -ge 5 ]]; then
    _record_pass "Kernel: >= 5.x ($(uname -r))"
else
    _record_fail "Kernel: >= 5.x" "$(uname -r)" "5.x+"
fi

# ═══════════════════════════════════════════════════════════════════
#  0.2  Required host commands
# ═══════════════════════════════════════════════════════════════════
section "Required Commands"

for cmd in bash git curl jq file python3 tmux wget unzip; do
    if command -v "$cmd" &>/dev/null; then
        _record_pass "command: $cmd"
    else
        _record_fail "command: $cmd" "(not found)" "in PATH"
    fi
done

# Docker (separate — may need to be installed by bootstrap)
if command -v docker &>/dev/null; then
    _record_pass "command: docker"
    # Check Docker daemon
    if docker info &>/dev/null 2>&1; then
        _record_pass "Docker: daemon reachable"
    else
        _record_fail "Docker: daemon reachable" "unreachable" "docker info succeeds"
    fi
    # Check compose plugin
    if docker compose version &>/dev/null 2>&1; then
        _record_pass "Docker: compose plugin"
    elif command -v docker-compose &>/dev/null; then
        _record_pass "Docker: docker-compose (legacy)"
    else
        _record_fail "Docker: compose available" "missing" "docker compose or docker-compose"
    fi
else
    _record_fail "command: docker" "(not found)" "in PATH"
fi

# ═══════════════════════════════════════════════════════════════════
#  0.3  Repository integrity
# ═══════════════════════════════════════════════════════════════════
section "Repository Integrity"

# Critical repo files that must exist
for f in labctl \
         compose/docker-compose.yml \
         compose/docker-compose.gpu.yml \
         compose/docker-compose.hostnet.yml \
         docker/kali-main/Dockerfile \
         docker/kali-main/apt-packages.txt \
         docker/builder/Dockerfile \
         docker/builder/apt-packages.txt \
         manifests/apt-host.txt \
         manifests/binaries.tsv \
         scripts/bootstrap-host.sh \
         scripts/verify-host.sh \
         scripts/launch-lab.sh \
         scripts/sync-binaries.sh \
         scripts/update-lab.sh \
         scripts/create-workspace.sh \
         scripts/install-empusa.sh \
         scripts/lib/compose.sh \
         .env.example; do
    assert_file_exists "$REPO_ROOT/$f" "repo: $f"
done

# labctl must be executable
if [[ -x "$REPO_ROOT/labctl" ]]; then
    _record_pass "repo: labctl is executable"
else
    _record_fail "repo: labctl is executable" "not executable" "chmod +x"
fi

# Templates directory — all 9 expected templates
section "Repo Templates"

for tmpl in ad.md engagement.md finding.md pivot.md privesc.md \
            recon.md services.md target.md web.md; do
    assert_file_exists "$REPO_ROOT/templates/$tmpl" "template: $tmpl"
    assert_file_not_empty "$REPO_ROOT/templates/$tmpl" "template: $tmpl non-empty"
done

# tmux profiles
section "Tmux Profiles"

for profile in default.sh htb.sh build.sh research.sh; do
    assert_file_exists "$REPO_ROOT/tmux/profiles/$profile" "tmux profile: $profile"
done
assert_file_exists "$REPO_ROOT/tmux/.tmux.conf" "tmux: .tmux.conf"

# ═══════════════════════════════════════════════════════════════════
#  0.4  Manifest format validation
# ═══════════════════════════════════════════════════════════════════
section "Manifest Format"

# apt-host.txt: non-empty, no broken lines
if [[ -s "$REPO_ROOT/manifests/apt-host.txt" ]]; then
    _record_pass "manifest: apt-host.txt non-empty"
    # Count non-comment, non-blank lines
    pkg_count="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$REPO_ROOT/manifests/apt-host.txt" | wc -l)"
    if [[ "$pkg_count" -gt 5 ]]; then
        _record_pass "manifest: apt-host.txt has ${pkg_count} packages"
    else
        _record_fail "manifest: apt-host.txt package count" "$pkg_count" ">5"
    fi
else
    _record_fail "manifest: apt-host.txt non-empty" "(empty)" "non-empty"
fi

# binaries.tsv: non-empty, tab-separated, 7 columns
if [[ -s "$REPO_ROOT/manifests/binaries.tsv" ]]; then
    _record_pass "manifest: binaries.tsv non-empty"
    # Check first non-comment data line has 7 tab-separated fields
    data_line="$(grep -v '^#' "$REPO_ROOT/manifests/binaries.tsv" | grep -v '^[[:space:]]*$' | head -1)"
    if [[ -n "$data_line" ]]; then
        field_count="$(echo "$data_line" | awk -F'\t' '{print NF}')"
        if [[ "$field_count" -ge 6 ]]; then
            _record_pass "manifest: binaries.tsv has ${field_count} columns"
        else
            _record_fail "manifest: binaries.tsv columns" "$field_count" ">=6"
        fi
    fi
else
    _record_fail "manifest: binaries.tsv non-empty" "(empty)" "non-empty"
fi

end_stage
