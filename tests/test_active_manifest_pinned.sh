#!/usr/bin/env bash
# tests/test_active_manifest_pinned.sh
#
# Regression guard on the *real* manifests/binaries.tsv shipped in the
# repo.  Every active (non-comment, non-header) row must:
#
#   1. NOT be mode=all-assets   — strict release-sanity rejects all-assets
#      because per-asset checksums are unsupported.
#   2. Have a 64-lowercase-hex sha256                         (no TODO_SHA256).
#
# This test does not download anything and does not depend on Docker.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/helpers.sh
source "$TESTS_DIR/helpers.sh"
begin_tests "active manifest is deterministic + pinned"

REPO_DIR="$(dirname "$TESTS_DIR")"
MANIFEST="$REPO_DIR/manifests/binaries.tsv"
assert_file_exists "$MANIFEST" "binaries.tsv present"

active_rows=0
all_assets_rows=0
todo_rows=0
malformed_rows=0
chisel_seen=0

while IFS=$'\t' read -r f_name f_type f_repo f_tag f_mode f_dest f_flags f_sha || [[ -n "${f_name:-}" ]]; do
    [[ -z "${f_name:-}" || "${f_name:0:1}" == "#" || "$f_name" == "name" ]] && continue
    f_sha="${f_sha%$'\r'}"
    f_mode="${f_mode%$'\r'}"
    active_rows=$((active_rows + 1))
    [[ "$f_mode" == "all-assets" ]] && all_assets_rows=$((all_assets_rows + 1))
    [[ "$f_sha" == "TODO_SHA256" ]] && todo_rows=$((todo_rows + 1))
    [[ "$f_sha" =~ ^[a-f0-9]{64}$ ]] || malformed_rows=$((malformed_rows + 1))
    [[ "$f_name" == "chisel" ]] && chisel_seen=1
done < "$MANIFEST"

assert_neq "0" "$active_rows" "manifest has at least one active row"
assert_eq "0" "$all_assets_rows" "no active row uses mode=all-assets"
assert_eq "0" "$todo_rows" "no active row carries TODO_SHA256"
assert_eq "0" "$malformed_rows" "every active sha256 is 64 lowercase hex"
assert_eq "1" "$chisel_seen" "chisel row still present in active manifest"

end_tests
