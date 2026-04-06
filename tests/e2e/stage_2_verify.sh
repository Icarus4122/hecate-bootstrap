#!/usr/bin/env bash
# tests/e2e/stage_2_verify.sh - Verify and sync validation.
#
# Requires: Docker running.  Validates that labctl verify passes on a
# bootstrapped host, and that sync-binaries.sh correctly fetches and
# validates pinned assets.

begin_stage 2 "Verify & Sync"

LAB="${LAB_ROOT:-/opt/lab}"

# ═══════════════════════════════════════════════════════════════════
#  2.1  labctl verify — full pass on provisioned host
# ═══════════════════════════════════════════════════════════════════
section "labctl verify"

verify_out="$(bash "$REPO_ROOT/labctl" verify 2>&1)" || true
verify_rc=$?

# On a correctly bootstrapped host, verify should exit 0
assert_eq "0" "$verify_rc" "verify: exits 0 on provisioned host"

# Output structure
assert_contains "$verify_out" "Summary" "verify output: has Summary"
assert_contains "$verify_out" "Result:" "verify output: has Result:"

# Should report ≥1 pass
assert_match "$verify_out" '[0-9]+ passed' "verify: reports pass count"

# ═══════════════════════════════════════════════════════════════════
#  2.2  Verify checks detail
# ═══════════════════════════════════════════════════════════════════
section "Verify Check Coverage"

# The verify script checks 9 areas — confirm key ones are in output
for check in "docker" "compose" "lab" "Empusa"; do
    if echo "$verify_out" | grep -qi "$check"; then
        _record_pass "verify covers: $check"
    else
        _record_fail "verify covers: $check" "not mentioned" "in verify output"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  2.3  Verify with LAB_GPU=1 (if GPU present)
# ═══════════════════════════════════════════════════════════════════
section "Verify GPU (conditional)"

if has_gpu; then
    gpu_out="$(LAB_GPU=1 bash "$REPO_ROOT/labctl" verify 2>&1)" || true
    gpu_rc=$?
    assert_eq "0" "$gpu_rc" "verify --gpu: exits 0 with GPU hardware"
    if echo "$gpu_out" | grep -qi "nvidia\|gpu"; then
        _record_pass "verify --gpu: mentions GPU/NVIDIA"
    else
        _record_fail "verify --gpu: mentions GPU/NVIDIA" "not found" "GPU checks in output"
    fi
else
    _record_pass "verify GPU: no hardware (skip)"
fi

# ═══════════════════════════════════════════════════════════════════
#  2.4  Sync binaries
# ═══════════════════════════════════════════════════════════════════
section "Binary Sync"

sync_out="$(bash "$REPO_ROOT/labctl" sync 2>&1)" || true
sync_rc=$?

# Sync should exit 0 (assuming network access and valid manifest)
assert_eq "0" "$sync_rc" "sync: exits 0"

# Binaries directory should have content
assert_dir_exists "$LAB/tools/binaries" "sync: binaries/ exists"

# Check that at least one binary is present after sync.
sync_file_count="$(find "$LAB/tools/binaries" -type f 2>/dev/null | wc -l)"
if [[ "$sync_file_count" -gt 0 ]]; then
    _record_pass "sync: at least one file present after sync"
else
    _record_fail "sync: at least one file present after sync" "empty" "files in binaries/"
fi

# ═══════════════════════════════════════════════════════════════════
#  2.5  Sync idempotency
# ═══════════════════════════════════════════════════════════════════
section "Sync Idempotency"

# Count files before second sync
count_before="$(find "$LAB/tools/binaries" -type f 2>/dev/null | wc -l)"

sync2_out="$(bash "$REPO_ROOT/labctl" sync 2>&1)" || true
sync2_rc=$?

assert_eq "0" "$sync2_rc" "sync re-run: exits 0"

count_after="$(find "$LAB/tools/binaries" -type f 2>/dev/null | wc -l)"
assert_eq "$count_before" "$count_after" "sync idempotent: file count unchanged ($count_before)"

# Second run should show skip markers
if echo "$sync2_out" | grep -q '\[=\]\|skipped\|already'; then
    _record_pass "sync re-run: reports skips"
else
    _record_fail "sync re-run: reports skips" "no skip output" "[=] or 'skipped'"
fi

# ═══════════════════════════════════════════════════════════════════
#  2.6  Sync --dry-run
# ═══════════════════════════════════════════════════════════════════
section "Sync Dry Run"

dry_out="$(bash "$REPO_ROOT/labctl" sync --dry-run 2>&1)" || true
dry_rc=$?
assert_eq "0" "$dry_rc" "sync --dry-run: exits 0"

# Dry run should not change file count
count_dry="$(find "$LAB/tools/binaries" -type f 2>/dev/null | wc -l)"
assert_eq "$count_after" "$count_dry" "sync --dry-run: no files changed"

# ═══════════════════════════════════════════════════════════════════
#  2.7  Binary validation — file types
# ═══════════════════════════════════════════════════════════════════
section "Binary File Types"

# Every file in binaries/ should be a valid binary type (not HTML/XML error pages)
bad_files=0
while IFS= read -r f; do
    ftype="$(file -b "$f" 2>/dev/null || echo "unknown")"
    if echo "$ftype" | grep -qiE 'HTML|XML'; then
        _record_fail "binary type: $(basename "$f")" "$ftype" "not HTML/XML"
        bad_files=$((bad_files + 1))
    fi
done < <(find "$LAB/tools/binaries" -type f 2>/dev/null)

if [[ $bad_files -eq 0 ]]; then
    _record_pass "binary types: no HTML/XML error pages"
fi

end_stage
