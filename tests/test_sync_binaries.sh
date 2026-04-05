#!/usr/bin/env bash
# tests/test_sync_binaies.sh - Tests for scripts/sync-binaries.sh logic.
#
# We test validate_download() by creating stub files with known
# file(1) signatures, and test manifest parsing / argument parsing
# by running the script against a sandbox.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "sync-binaries.sh logic"

make_sandbox
OUT="$SANDBOX/out.txt"
_REAL_REPO="$(dirname "$TESTS_DIR")"
SCRIPT="$_REAL_REPO/scripts/sync-binaries.sh"

# Build a sourceable version (only functions/variables, skip main + ag parsing)
# We need to strip: set -euo, top-level argument parsing while loop, main call,
# dependency check block at top level. We only want functions.
{
    # Extract function definitions only.  The sourced file will define:
    #   usage, fetch_release, validate_download, download_one, file_size, process_entry
    sed -n '/^[a-z_]*() {/,/^}/p' "$SCRIPT"
    # Also source the state variables (DRY_RUN, FILTER, ERRORS, etc.)
    echo 'DRY_RUN=false; FILTER=""; ERRORS=0; SYNCED=0; SKIPPED=0'
    echo 'declare -A _release_cache'
    # Mock gh_curl_opts
    echo 'gh_curl_opts=(-fsSL -H "Accept: application/vnd.github+json")'
} > "$SANDBOX/sync-funcs.sh"

export LAB_ROOT="$SANDBOX/opt/lab"
BIN_DIR="$LAB_ROOT/tools/binaries"
mkdir -p "$BIN_DIR"
REPO_DIR="$SANDBOX/repo"
mkdir -p "$REPO_DIR/manifests"

source "$SANDBOX/sync-funcs.sh"

# ═══════════════════════════════════════════════════════════════════
#  validate_download - file type classification
# ═══════════════════════════════════════════════════════════════════

# Case 1: ELF binary -> accepted
elf_file="$SANDBOX/test.elf"
printf '\x7fELF' > "$elf_file"
c=0
validate_download "$elf_file" false > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "validate: ELF binary -> accepted"

# Case 2: HTML document -> rejected
html_file="$SANDBOX/test.html"
echo '<!DOCTYPE html><html><body>Eo 404</body></html>' > "$html_file"
c=0
validate_download "$html_file" false > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "validate: HTML document -> rejected"
assert_contains "$(cat "$OUT")" "HTML" "validate: HTML rejection mentions HTML"

# Case 3: XML document -> rejected
xml_file="$SANDBOX/test.xml"
echo '<?xml version="1.0"?><error>Rate limit</error>' > "$xml_file"
c=0
validate_download "$xml_file" false > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "validate: XML document -> rejected"

# Case 4: text file, allow_text=false -> rejected
text_file="$SANDBOX/test.txt"
echo 'This is some plain text content' > "$text_file"
c=0
validate_download "$text_file" false > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "validate: text, allow=false -> rejected"

# Case 5: text file, allow_text=true -> accepted
c=0
validate_download "$text_file" true > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "validate: text, allow=true -> accepted"

# Case 6: gzip archive -> accepted
gz_file="$SANDBOX/test.gz"
printf '\x1f\x8b\x08' > "$gz_file"
c=0
validate_download "$gz_file" false > "$OUT" 2>&1 || c=$?
assert_eq "0" "$c" "validate: gzip archive -> accepted"

# ═══════════════════════════════════════════════════════════════════
#  Argument parsing (run script directly)
#  These tests invoke the full script.  If host dependencies are
#  missing (jq, curl, file), the script fails at its dep-check
#  before eaching the logic under test.  We gate on jq availability.
# ═══════════════════════════════════════════════════════════════════

if command -v jq &>/dev/null && command -v curl &>/dev/null; then

# --name with missing argument -> error
c=0
bash "$SCRIPT" --name > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "args: --name without value -> exit 1"

# Unknown option -> error
c=0
bash "$SCRIPT" --bogus > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "args: unknown option -> exit 1"

# --dry-run with --name filter for nonexistent entry -> error
c=0
bash "$SCRIPT" --dry-run --name nosuchentry > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "args: --name nosuchentry -> exit 1"
assert_contains "$(cat "$OUT")" "No manifest entry" "args: reports no matching entry"

# ═══════════════════════════════════════════════════════════════════
#  Manifest missing entiely -> error
#  We copy the script to the sandbox and patch the MANIFEST path.
# ═══════════════════════════════════════════════════════════════════
sed "s|^MANIFEST=.*|MANIFEST=\"$SANDBOX/nonexistent.tsv\"|" "$SCRIPT" \
    > "$SANDBOX/sync-patched.sh"
c=0
bash "$SANDBOX/sync-patched.sh" > "$OUT" 2>&1 || c=$?
assert_eq "1" "$c" "missing manifest -> exit 1"
assert_contains "$(cat "$OUT")" "Manifest not found" "missing manifest: reports not found"

else
    echo "# SKIP: jq or curl not available - skipping full-script tests"
fi

end_tests
