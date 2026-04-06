#!/usr/bin/env bash
# scripts/dev/ci-repo-integrity.sh — Validate repo structure and file inventory.
#
# Lightweight version of e2e stage 0's repo-integrity checks that runs
# on any Linux runner without root, Docker, or Ubuntu 24.04.
#
# Checks: critical files exist, labctl executable, templates present,
# tmux profiles present, manifest format valid, .env.example present.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

echo "── Repo integrity ──"

# Critical files
echo ""
echo "Critical files:"
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
    if [[ -f "$REPO/$f" ]]; then
        pass "$f"
    else
        fail "$f (missing)"
    fi
done

# Executable bit
echo ""
echo "Executable bits:"
if [[ -x "$REPO/labctl" ]]; then
    pass "labctl is executable"
else
    fail "labctl is not executable"
fi

# Templates
echo ""
echo "Templates:"
for tmpl in ad.md engagement.md finding.md pivot.md privesc.md \
            recon.md services.md target.md web.md; do
    if [[ -s "$REPO/templates/$tmpl" ]]; then
        pass "template: $tmpl"
    else
        fail "template: $tmpl (missing or empty)"
    fi
done

# Tmux profiles
echo ""
echo "Tmux profiles:"
for profile in default.sh htb.sh build.sh research.sh; do
    if [[ -f "$REPO/tmux/profiles/$profile" ]]; then
        pass "tmux: $profile"
    else
        fail "tmux: $profile (missing)"
    fi
done
if [[ -f "$REPO/tmux/.tmux.conf" ]]; then
    pass "tmux: .tmux.conf"
else
    fail "tmux: .tmux.conf (missing)"
fi

# Manifest format
echo ""
echo "Manifest format:"
pkg_count="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$REPO/manifests/apt-host.txt" | wc -l)"
if [[ "$pkg_count" -gt 5 ]]; then
    pass "apt-host.txt: ${pkg_count} packages"
else
    fail "apt-host.txt: only ${pkg_count} packages (expected >5)"
fi

data_line="$(grep -v '^#' "$REPO/manifests/binaries.tsv" | grep -v '^[[:space:]]*$' | head -1)"
if [[ -n "$data_line" ]]; then
    field_count="$(echo "$data_line" | awk -F'\t' '{print NF}')"
    if [[ "$field_count" -ge 6 ]]; then
        pass "binaries.tsv: ${field_count} columns"
    else
        fail "binaries.tsv: ${field_count} columns (expected >=6)"
    fi
else
    fail "binaries.tsv: no data lines"
fi

# Summary
echo ""
echo "── ${PASS} passed, ${FAIL} failed ──"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
