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

pass() { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1"; }

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

# binaries.tsv: validate every real data row, ignoring comments / blanks /
# header. Header is recognised by its first column being literally "name".
# Each real row must have >=7 tab-separated fields (name, type, repo, tag,
# mode, dest, flags).
declare -i bin_data_rows=0
declare -i bin_bad_rows=0
declare -i bin_lineno=0
while IFS= read -r line; do
    bin_lineno=$((bin_lineno + 1))
    # Strip comments and blank lines.
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # Skip header row (first column is literally "name").
    first="${line%%$'\t'*}"
    if [[ "$first" == "name" ]]; then
        continue
    fi
    bin_data_rows=$((bin_data_rows + 1))
    # Validate field count.
    fc="$(awk -F'\t' '{print NF}' <<< "$line")"
    if [[ "$fc" -lt 7 ]]; then
        bin_bad_rows=$((bin_bad_rows + 1))
        fail "binaries.tsv: row ${bin_lineno} has ${fc} fields (expected >=7)"
    fi
done < "$REPO/manifests/binaries.tsv"

if [[ $bin_data_rows -eq 0 ]]; then
    fail "binaries.tsv: no real data rows (only header / comments)"
elif [[ $bin_bad_rows -eq 0 ]]; then
    pass "binaries.tsv: ${bin_data_rows} data row(s), all well-formed"
fi

# Summary
echo ""
echo "── ${PASS} passed, ${FAIL} failed ──"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
