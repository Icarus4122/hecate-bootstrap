#!/usr/bin/env bash
# tests/test_repo_integrity_manifest.sh
#
# Verifies ci-repo-integrity.sh's binaries.tsv validation:
#   - skips header row (first column == "name")
#   - skips comment / blank rows
#   - flags malformed rows (< 8 tab-separated fields) with a row number
#   - flags rows whose sha256 is neither 64-hex nor TODO_SHA256
#   - reports [PASS] for a manifest that contains at least one valid row
#   - emits a [WARN] when any data row carries TODO_SHA256
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
    # labctl needs real content + exec bit so the executable-bit check
    # passes on filesystems (NTFS / Git Bash) that drop +x on empty files.
    printf '#!/usr/bin/env bash\n' > "$root/labctl"
    chmod 755 "$root/labctl"
    : > "$root/compose/docker-compose.yml"
    : > "$root/compose/docker-compose.gpu.yml"
    : > "$root/compose/docker-compose.hostnet.yml"
    : > "$root/docker/kali-main/Dockerfile"
    : > "$root/docker/kali-main/apt-packages.txt"
    : > "$root/docker/builder/Dockerfile"
    : > "$root/docker/builder/apt-packages.txt"
    # apt-host.txt needs >5 non-comment, non-blank lines for the
    # validator to PASS the package-count assertion.
    cat > "$root/manifests/apt-host.txt" <<'APT'
# stub host packages
curl
git
jq
make
tmux
unzip
APT
    for s in bootstrap-host.sh verify-host.sh launch-lab.sh sync-binaries.sh \
             update-lab.sh create-workspace.sh install-empusa.sh; do
        : > "$root/scripts/$s"
    done
    : > "$root/scripts/lib/compose.sh"
    : > "$root/.env.example"
    # Templates: validator uses [[ -s ]] (non-empty), so write a byte.
    for t in ad.md engagement.md finding.md pivot.md privesc.md \
             recon.md services.md target.md web.md; do
        printf '# stub\n' > "$root/templates/$t"
    done
    # Tmux profiles + .tmux.conf must exist.
    for p in default.sh htb.sh build.sh research.sh; do
        : > "$root/tmux/profiles/$p"
    done
    : > "$root/tmux/.tmux.conf"
    cp "$REPO_DIR/scripts/dev/ci-repo-integrity.sh" "$root/scripts/dev/"

    case "$kind" in
        good_todo)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
# comment row
name	type	repo	tag	mode	dest	flags	sha256

chisel	github-release	jpillora/chisel	v1.10.0	binary	chisel	-	TODO_SHA256
TSV
            ;;
        good_pinned)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags	sha256
pspy	github-release	DominicBreuker/pspy	v1.2.1	pspy64	pspy	executable	0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
TSV
            ;;
        header_only)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags	sha256
TSV
            ;;
        too_few_fields)
            # 7 fields - missing sha256 column
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags	sha256
chisel	github-release	jpillora/chisel	v1.10.0	binary	chisel	-
TSV
            ;;
        malformed)
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags	sha256
chisel	github-release	jpillora/chisel
TSV
            ;;
        bad_sha)
            # 8 fields, but sha256 is neither 64-hex nor TODO_SHA256
            cat > "$root/manifests/binaries.tsv" <<'TSV'
name	type	repo	tag	mode	dest	flags	sha256
chisel	github-release	jpillora/chisel	v1.10.0	binary	chisel	-	NOTAHASH
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

# ── Case: well-formed manifest with TODO_SHA256 ─────────────────────
GOOD="$SANDBOX/good_todo"
stub_repo good_todo "$GOOD"
OUT="$SANDBOX/good_todo.out"
RC="$(run_check "$GOOD" "$OUT")"
GOOD_OUT="$(cat "$OUT")"
assert_eq "0" "$RC" "good (TODO_SHA256): exit 0"
assert_contains "$GOOD_OUT" "[PASS] binaries.tsv: 1 data row" "good (TODO): reports valid data rows"
assert_not_contains "$GOOD_OUT" "[FAIL] binaries.tsv" "good (TODO): no manifest [FAIL]"
assert_contains "$GOOD_OUT" "[WARN] binaries.tsv" "good (TODO): emits [WARN] for unpinned checksum"
assert_contains "$GOOD_OUT" "TODO_SHA256" "good (TODO): warning mentions TODO_SHA256"

# ── Case: well-formed manifest with real (lowercase 64-hex) sha256 ──
PIN="$SANDBOX/good_pinned"
stub_repo good_pinned "$PIN"
OUT="$SANDBOX/good_pinned.out"
RC="$(run_check "$PIN" "$OUT")"
PIN_OUT="$(cat "$OUT")"
assert_eq "0" "$RC" "good (pinned): exit 0"
assert_contains "$PIN_OUT" "[PASS] binaries.tsv: 1 data row" "good (pinned): reports valid data rows"
assert_not_contains "$PIN_OUT" "[FAIL] binaries.tsv" "good (pinned): no manifest [FAIL]"
assert_not_contains "$PIN_OUT" "[WARN] binaries.tsv" "good (pinned): no TODO warning"

# ── Case: header row only (no real data) ────────────────────────────
HDR="$SANDBOX/header"
stub_repo header_only "$HDR"
OUT="$SANDBOX/header.out"
RC="$(run_check "$HDR" "$OUT")"
HDR_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "header-only: nonzero exit"
assert_contains "$HDR_OUT" "no real data rows" "header-only: explains the failure"

# ── Case: missing sha256 column (only 7 fields) ─────────────────────
SEVEN="$SANDBOX/too_few"
stub_repo too_few_fields "$SEVEN"
OUT="$SANDBOX/too_few.out"
RC="$(run_check "$SEVEN" "$OUT")"
SEVEN_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "missing sha256: nonzero exit"
assert_contains "$SEVEN_OUT" "[FAIL] binaries.tsv: row" "missing sha256: per-row [FAIL]"
assert_contains "$SEVEN_OUT" "expected >=8" "missing sha256: states expected field count"

# ── Case: malformed data row (< 8 fields, badly broken) ─────────────
BAD="$SANDBOX/bad"
stub_repo malformed "$BAD"
OUT="$SANDBOX/bad.out"
RC="$(run_check "$BAD" "$OUT")"
BAD_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "malformed: nonzero exit"
assert_contains "$BAD_OUT" "[FAIL] binaries.tsv: row" "malformed: per-row [FAIL]"
assert_contains "$BAD_OUT" "expected >=8" "malformed: states expected field count"

# ── Case: invalid sha256 value (not hex, not TODO sentinel) ─────────
BSH="$SANDBOX/bad_sha"
stub_repo bad_sha "$BSH"
OUT="$SANDBOX/bad_sha.out"
RC="$(run_check "$BSH" "$OUT")"
BSH_OUT="$(cat "$OUT")"
assert_neq "0" "$RC" "bad sha256: nonzero exit"
assert_contains "$BSH_OUT" "sha256 must be 64 lowercase hex chars or TODO_SHA256" \
    "bad sha256: explains required format"

end_tests
