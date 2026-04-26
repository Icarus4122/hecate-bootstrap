#!/usr/bin/env bash
# tests/test_repo_integrity_manifest.sh
#
# Verifies ci-repo-integrity.sh's binaries.tsv validation:
#   - skips header row (first column == "name")
#   - skips comment / blank rows
#   - flags malformed rows (< 7 tab-separated fields) with a row number
#   - reports [PASS] for a manifest that contains at least one valid row
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "ci-repo-integrity binaries.tsv validation"

REPO_DIR="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_DIR/scripts/dev/ci-repo-integrity.sh"
assert_file_exists "$SCRIPT" "ci-repo-integrity.sh present"

# Build a sandbox repo containing only the bits the script touches.
make_sandbox

stub_repo() {
    local kind="$1" root="$2"
    mkdir -p "$root/compose" "$root/docker/kali-main" "$root/docker/builder" \
             "$root/manifests" "$root/scripts/lib" "$root/scripts/dev" \
             "$root/templates" "$root/tmux/profiles"
    # Critical files (content irrelevant; presence-only).
    : > "$root/labctl"; chmod +x "$root/labctl"
    : > "$root/compose/docker-compose.yml"
    : > "$root/compose/docker-compose.gpu.yml"
    : > "$root/compose/docker-compose.hostnet.yml"
    : > "$root/docker/kali-main/Dockerfile"
    : > "$root/docker/kali-main/apt-packages.txt"
    : > "$root/docker/builder/Dockerfile"
    : > "$root/docker/builder/apt-packages.txt"
    : > "$root/manifests/apt-host.txt"
    for s in bootstrap-host.sh verify-host.sh launch-lab.sh sync-binaries.sh \
             update-lab.sh create-workspace.sh install-empusa.sh; do
        : > "$root/scripts/$s"
    done
    : > "$root/scripts/lib/compose.sh"
    : > "$root/.env.example"
    cp "$REPO_DIR/scripts/dev/ci-repo-integrity.sh" "$root/scripts/dev/"

    case "$kind" in
        good)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
# comment row
name	type	repo	tag	mode	dest	flags

chisel	github-release	jpillora/chisel	v1.10.0	binary	/opt/lab/tools/binaries	-
TSV
            ;;
        header_only)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags
TSV
            ;;
        malformed)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags
chisel	github-release	jpillora/chisel
TSV
            ;;
    esac
}

run_check() {
    local root="$1" out="$2"
    local rc=0
    bash "$root/scripts/dev/ci-repo-integrity.sh" > "$out" 2>&1 || rc=$?
    echo "$rc"
}

# ── Case: well-formed manifest ─────────────────────────────────────
GOOD="$SANDBOX/good"
stub_repo good "$GOOD"
OUT="$SANDBOX/good.out"
RC="$(run_check "$GOOD" "$OUT")"
GOOD_OUT="$(cat "$OUT")"
assert_eq "0" "$RC" "good manifest: exit 0"
assert_contains "$GOOD_OUT" "[PASS] binaries.tsv: 1 data row" "good: reports valid data rows"
assert_not_contains "$GOOD_OUT" "[FAIL] binaries.tsv" "good: no manifest [FAIL]"

# ── Case: header row only (no real data) ───────────────────────────
HDR="$SANDBOX/header"
stub_repo header_only "$HDR"
OUT="$SANDBOX/header.out"
RC="$(run_check "$HDR" "$OUT")"
HDR_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "header-only: nonzero exit"
assert_contains "$HDR_OUT" "no real data rows" "header-only: explains the failure"

# ── Case: malformed data row (< 7 fields) ──────────────────────────
BAD="$SANDBOX/bad"
stub_repo malformed "$BAD"
OUT="$SANDBOX/bad.out"
RC="$(run_check "$BAD" "$OUT")"
BAD_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "malformed: nonzero exit"
assert_contains "$BAD_OUT" "[FAIL] binaries.tsv: row" "malformed: per-row [FAIL]"
assert_contains "$BAD_OUT" "expected >=7" "malformed: states expected field count"

end_tests
