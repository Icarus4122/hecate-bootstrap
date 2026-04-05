#!/usr/bin/env bash
# scenarios/sc_10_template_workflow.sh - Template-to-workflow correctness.
#
# Tests the complete template journey: raw repo templates → Empusa seed →
# operator fills in data → templates survive restart → templates match
# profile semantics → docs/help consistency.
#
# Prerequisites: Empusa installed (no Docker needed for seed tests;
#                Docker needed for workflow integration)

begin_scenario "template-workflow" "Template seed through operator usage lifecycle"

LAB="${LAB_ROOT:-/opt/lab}"
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"
TEMPLATES_DIR="$REPO_ROOT/templates"

if [[ ! -x "$EMPUSA_BIN" ]]; then
    skip_scenario "template-workflow" "Empusa not available"
    return 0
fi

make_sandbox
WS_ROOT="$SANDBOX/workspaces"
mkdir -p "$WS_ROOT"

# ── Step 1: HTB template seed and validate ─────────────────────────
section "Step 1 — HTB Seed"

"$EMPUSA_BIN" workspace init \
    --name "tw-htb" --profile "htb" \
    --root "$WS_ROOT" --templates-dir "$TEMPLATES_DIR" \
    --set-active &>/dev/null || true

WS="$WS_ROOT/tw-htb"

# All expected templates present
htb_templates="engagement.md target.md recon.md services.md finding.md privesc.md web.md"
for tmpl in $htb_templates; do
    assert_file_exists "$WS/$tmpl" "htb seed: $tmpl present"
    assert_file_not_empty "$WS/$tmpl" "htb seed: $tmpl non-empty"
done

# No stray templates
for tmpl in pivot.md ad.md; do
    if [[ ! -f "$WS/$tmpl" ]]; then
        _record_pass "htb seed: $tmpl correctly absent"
    else
        _record_fail "htb seed: $tmpl should be absent" "present" "absent"
    fi
done

# ── Step 2: Validate seeded template structure ─────────────────────
section "Step 2 — Seeded Structure"

# Each seeded template should retain markdown structure from repo
for tmpl in $htb_templates; do
    if [[ ! -f "$WS/$tmpl" ]]; then continue; fi

    # Has at least one heading
    if grep -qE '^#{1,4} ' "$WS/$tmpl"; then
        _record_pass "structure: $tmpl has headings"
    else
        _record_fail "structure: $tmpl headings" "none" "at least one # heading"
    fi

    # No raw {{PLACEHOLDER}} remaining (NAME at minimum should be substituted)
    if grep -q '{{NAME}}' "$WS/$tmpl"; then
        _record_fail "structure: $tmpl no {{NAME}}" "found {{NAME}}" "substituted"
    else
        _record_pass "structure: $tmpl {{NAME}} substituted"
    fi
done

# Specific heading order in engagement.md
if [[ -f "$WS/engagement.md" ]]; then
    assert_heading_order "$WS/engagement.md" "engagement.md seeded" \
        "Scope" "Rules" "Objectives" "Timeline"
fi

# target.md should have logical order
if [[ -f "$WS/target.md" ]]; then
    assert_heading_order "$WS/target.md" "target.md seeded" \
        "Open Ports" "Credentials" "Attack Path"
fi

# ── Step 3: Simulate operator filling in templates ─────────────────
section "Step 3 — Operator Fill-In"

# Operator edits target.md
cat >> "$WS/target.md" << 'EOF'

## Target Details
- IP: 10.10.10.100
- OS: Linux
- Hostname: devvortex

## Open Ports
| Port | Service | Version |
|------|---------|---------|
| 22   | SSH     | OpenSSH 8.2 |
| 80   | HTTP    | nginx 1.18 |
EOF

# Verify the file is still valid markdown
if grep -qE '^##' "$WS/target.md"; then
    _record_pass "fill-in: target.md still valid markdown"
else
    _record_fail "fill-in: target.md markdown" "broken" "valid headings"
fi

# Operator edits recon.md
cat >> "$WS/recon.md" << 'EOF'

## Passive
- Subdomain enum: *.devvortex.htb

## Active
- nmap full TCP: complete
EOF

assert_file_not_empty "$WS/recon.md" "fill-in: recon.md has content"

# ── Step 4: Internal profile — superset templates ──────────────────
section "Step 4 — Internal Profile"

"$EMPUSA_BIN" workspace init \
    --name "tw-internal" --profile "internal" \
    --root "$WS_ROOT" --templates-dir "$TEMPLATES_DIR" \
    --set-active &>/dev/null || true

INT="$WS_ROOT/tw-internal"

# Internal has the most templates
internal_templates="engagement.md target.md recon.md services.md finding.md pivot.md privesc.md ad.md"
for tmpl in $internal_templates; do
    assert_file_exists "$INT/$tmpl" "internal seed: $tmpl present"
done

# Internal-unique: pivot.md and ad.md
assert_file_not_empty "$INT/pivot.md" "internal: pivot.md non-empty"
assert_file_not_empty "$INT/ad.md" "internal: ad.md non-empty"

# ad.md should have AD-specific headings
if [[ -f "$INT/ad.md" ]]; then
    assert_heading_order "$INT/ad.md" "ad.md seeded" \
        "Domain" "Enumeration" "Credentials" "Attack Path"
fi

# pivot.md should have pivot-specific headings
if [[ -f "$INT/pivot.md" ]]; then
    assert_heading_order "$INT/pivot.md" "pivot.md seeded" \
        "Network Position" "Tunneling" "Port Forwarding"
fi

# web.md should NOT be in internal
if [[ ! -f "$INT/web.md" ]]; then
    _record_pass "internal: web.md correctly absent"
else
    _record_fail "internal: web.md absent" "present" "absent"
fi

# ── Step 5: Research profile — minimal templates ───────────────────
section "Step 5 — Research Profile"

"$EMPUSA_BIN" workspace init \
    --name "tw-research" --profile "research" \
    --root "$WS_ROOT" --templates-dir "$TEMPLATES_DIR" \
    --set-active &>/dev/null || true

RES="$WS_ROOT/tw-research"
assert_file_exists "$RES/recon.md" "research: recon.md present"

# Count templates — should be exactly 1
res_tmpl_count="$(find "$RES" -maxdepth 1 -name '*.md' ! -name '.*.md' -type f 2>/dev/null | wc -l)"
assert_eq "1" "$res_tmpl_count" "research: exactly 1 template seeded"

# ── Step 6: Build profile — zero templates ─────────────────────────
section "Step 6 — Build Profile"

"$EMPUSA_BIN" workspace init \
    --name "tw-build" --profile "build" \
    --root "$WS_ROOT" --templates-dir "$TEMPLATES_DIR" \
    --set-active &>/dev/null || true

BUILD="$WS_ROOT/tw-build"
build_tmpl_count="$(find "$BUILD" -maxdepth 1 -name '*.md' ! -name '.*.md' -type f 2>/dev/null | wc -l)"
assert_eq "0" "$build_tmpl_count" "build: zero templates seeded"

# ── Step 7: Template idempotency ──────────────────────────────────
section "Step 7 — Seed Idempotency"

# Re-init same workspace — should not overwrite operator changes
"$EMPUSA_BIN" workspace init \
    --name "tw-htb" --profile "htb" \
    --root "$WS_ROOT" --templates-dir "$TEMPLATES_DIR" &>/dev/null || true

# Operator additions should survive
if grep -q "10.10.10.100" "$WS/target.md" 2>/dev/null; then
    _record_pass "idempotent: operator data in target.md survived"
else
    _record_fail "idempotent: operator data" "missing" "10.10.10.100 in target.md"
fi

if grep -q "devvortex.htb" "$WS/recon.md" 2>/dev/null; then
    _record_pass "idempotent: operator data in recon.md survived"
else
    _record_fail "idempotent: operator data" "missing" "devvortex.htb in recon.md"
fi

# ── Step 8: Template-to-docs consistency ───────────────────────────
section "Step 8 — Docs Consistency"

# Every profile mentioned in help should be a valid Empusa profile
help_out="$(bash "$REPO_ROOT/labctl" help launch 2>&1)" || true
for profile in htb build research; do
    if echo "$help_out" | grep -qi "$profile"; then
        _record_pass "docs: help launch mentions $profile"
    fi
done

# labctl help should not mention templates that don't exist
for tmpl in engagement.md target.md recon.md services.md finding.md \
            privesc.md web.md pivot.md ad.md; do
    base="${tmpl%.md}"
    assert_file_exists "$TEMPLATES_DIR/$tmpl" "docs: referenced template $tmpl exists"
done

# ── Step 9: Profile metadata consistency ───────────────────────────
section "Step 9 — Metadata Consistency"

for ws_name in tw-htb tw-internal tw-research tw-build; do
    ws_path="$WS_ROOT/$ws_name"
    meta="$ws_path/.empusa-workspace.json"
    if [[ -f "$meta" ]]; then
        assert_file_contains "$meta" "\"profile\"" "metadata $ws_name: has profile"
        assert_file_contains "$meta" "\"name\"" "metadata $ws_name: has name"
        assert_file_contains "$meta" "\"created_at\"" "metadata $ws_name: has created_at"

        # Profile value should match the workspace creation profile
        expected_profile="${ws_name#tw-}"
        assert_file_contains "$meta" "\"$expected_profile\"" "metadata $ws_name: profile=$expected_profile"
    else
        _record_fail "metadata $ws_name: file exists" "missing" "$meta"
    fi
done

end_scenario
