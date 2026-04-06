#!/usr/bin/env bash
# tests/e2e/stage_6_templates.sh - Template seed and content validation.
#
# No Docker, no root.  Validates: per-profile template correctness via
# Empusa workspace init, and repo template file quality directly.
#
# What this catches:
#   - Missing template files per profile
#   - Empty templates
#   - Broken {{PLACEHOLDER}} variables remaining after seed
#   - Missing expected markdown headings
#   - Inconsistent formatting across templates

begin_stage 6 "Templates"

LAB="${LAB_ROOT:-/opt/lab}"
TEMPLATES_DIR="$REPO_ROOT/templates"
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"

# ═══════════════════════════════════════════════════════════════════
#  6.1  Repo template file inventory
# ═══════════════════════════════════════════════════════════════════
section "Repo Template Inventory"

EXPECTED_TEMPLATES="ad.md engagement.md finding.md pivot.md privesc.md recon.md services.md target.md web.md"

for tmpl in $EXPECTED_TEMPLATES; do
    assert_file_exists "$TEMPLATES_DIR/$tmpl" "repo template: $tmpl exists"
    assert_file_not_empty "$TEMPLATES_DIR/$tmpl" "repo template: $tmpl non-empty"
done

# No unexpected files
actual_count="$(find "$TEMPLATES_DIR" -maxdepth 1 -name '*.md' -type f | wc -l)"
expected_count="$(echo $EXPECTED_TEMPLATES | wc -w)"
assert_eq "$expected_count" "$actual_count" \
    "repo templates: exactly $expected_count .md files (got $actual_count)"

# ═══════════════════════════════════════════════════════════════════
#  6.2  Template markdown headings
# ═══════════════════════════════════════════════════════════════════
section "Template Headings"

# Each template must have at least a # heading
for tmpl in $EXPECTED_TEMPLATES; do
    if grep -qE '^#' "$TEMPLATES_DIR/$tmpl"; then
        _record_pass "template $tmpl: has markdown heading"
    else
        _record_fail "template $tmpl: has markdown heading" "no # heading" "at least one"
    fi
done

# Specific heading checks per template
_check_headings() {
    local tmpl="$1"; shift
    for heading in "$@"; do
        if grep -qi "$heading" "$TEMPLATES_DIR/$tmpl"; then
            _record_pass "template $tmpl: heading '$heading'"
        else
            _record_fail "template $tmpl: heading '$heading'" "missing" "expected heading"
        fi
    done
}

_check_headings "engagement.md" "Scope" "Rules of Engagement" "Objectives" "Timeline"
_check_headings "target.md"     "Open Ports" "Credentials" "Attack Path"
_check_headings "recon.md"      "Passive" "Active" "Findings" "Next Steps"
_check_headings "services.md"   "SMB" "HTTP" "SSH"
_check_headings "finding.md"    "Description" "Evidence" "Impact" "Remediation"
_check_headings "privesc.md"    "Current Access" "Linux" "Windows" "Escalation Path"
_check_headings "web.md"        "Fingerprint" "Content Discovery" "Vulnerabilities"
_check_headings "pivot.md"      "Network Position" "Tunneling" "Port Forwarding"
_check_headings "ad.md"         "Domain" "Enumeration" "Credentials" "Attack Path"

# ═══════════════════════════════════════════════════════════════════
#  6.3  Template variables (raw repo files should have placeholders)
# ═══════════════════════════════════════════════════════════════════
section "Template Variables (Raw)"

# Templates should contain {{PLACEHOLDER}} patterns for substitution
templates_with_vars="engagement.md target.md recon.md finding.md privesc.md web.md pivot.md ad.md"
for tmpl in $templates_with_vars; do
    if grep -qE '\{\{[A-Z_]+\}\}' "$TEMPLATES_DIR/$tmpl"; then
        _record_pass "template $tmpl: has variable placeholders"
    else
        _record_fail "template $tmpl: has variable placeholders" "none found" "{{VAR}} patterns"
    fi
done

# build profile has no templates so nothing to check there.
# research only has recon.md which may or may not have vars.

# ═══════════════════════════════════════════════════════════════════
#  6.4  Template formatting consistency
# ═══════════════════════════════════════════════════════════════════
section "Template Formatting"

for tmpl in $EXPECTED_TEMPLATES; do
    path="$TEMPLATES_DIR/$tmpl"

    # No trailing whitespace on lines (formatting hygiene)
    trailing="$(grep -cE '[[:space:]]$' "$path" || true)"
    [[ -z "$trailing" ]] && trailing=0
    # This is advisory — not a hard fail
    if [[ "$trailing" -le 5 ]]; then
        _record_pass "template $tmpl: minimal trailing whitespace ($trailing lines)"
    else
        _record_fail "template $tmpl: trailing whitespace" "$trailing lines" "<=5 lines"
    fi

    # No Windows line endings (should be LF only)
    if file "$path" | grep -qi "CRLF"; then
        _record_fail "template $tmpl: line endings" "CRLF" "LF only"
    else
        _record_pass "template $tmpl: LF line endings"
    fi

    # File should be under 500 lines (templates are starting points, not books)
    line_count="$(wc -l < "$path")"
    if [[ "$line_count" -le 500 ]]; then
        _record_pass "template $tmpl: reasonable size ($line_count lines)"
    else
        _record_fail "template $tmpl: size" "$line_count lines" "<=500"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  6.5  Seeded template validation (via Empusa)
# ═══════════════════════════════════════════════════════════════════
section "Seeded Templates (Empusa)"

if [[ ! -x "$EMPUSA_BIN" ]]; then
    _record_pass "Empusa not installed — skip seed tests"
else
    make_sandbox
    WS_ROOT="$SANDBOX/workspaces"
    mkdir -p "$WS_ROOT"

    # htb profile — fullest template set
    "$EMPUSA_BIN" workspace init \
        --name "tmpl-test" \
        --profile "htb" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active &>/dev/null || true

    WS_PATH="$WS_ROOT/tmpl-test"

    # 6.5a  Correct files seeded
    for tmpl in engagement.md target.md recon.md services.md \
                finding.md privesc.md web.md; do
        assert_file_exists "$WS_PATH/$tmpl" "seeded htb: $tmpl present"
        assert_file_not_empty "$WS_PATH/$tmpl" "seeded htb: $tmpl non-empty"
    done

    # 6.5b  Templates NOT in htb profile should NOT be seeded
    for tmpl in pivot.md ad.md; do
        if [[ -f "$WS_PATH/$tmpl" ]]; then
            _record_fail "seeded htb: $tmpl should not exist" "present" "absent"
        else
            _record_pass "seeded htb: $tmpl correctly absent"
        fi
    done

    # 6.5c  No broken placeholders after seeding
    #       After substitution, {{NAME}} at minimum should be replaced
    broken=0
    for tmpl in engagement.md target.md recon.md services.md \
                finding.md privesc.md web.md; do
        if [[ -f "$WS_PATH/$tmpl" ]]; then
            # Check for {{NAME}} specifically (should be replaced with workspace name)
            if grep -q '{{NAME}}' "$WS_PATH/$tmpl"; then
                _record_fail "seeded htb: $tmpl no {{NAME}} remaining" "found {{NAME}}" "substituted"
                broken=$((broken + 1))
            fi
        fi
    done
    if [[ $broken -eq 0 ]]; then
        _record_pass "seeded htb: no {{NAME}} placeholders remaining"
    fi

    # 6.5d  Seeded templates still have valid markdown
    for tmpl in engagement.md target.md recon.md; do
        if [[ -f "$WS_PATH/$tmpl" ]]; then
            if grep -qE '^#' "$WS_PATH/$tmpl"; then
                _record_pass "seeded $tmpl: retains markdown headings"
            else
                _record_fail "seeded $tmpl: markdown headings" "missing" "# heading"
            fi
        fi
    done

    # 6.5e  internal profile — unique templates (pivot.md, ad.md)
    "$EMPUSA_BIN" workspace init \
        --name "tmpl-internal" \
        --profile "internal" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active &>/dev/null || true

    INT_PATH="$WS_ROOT/tmpl-internal"

    for tmpl in engagement.md target.md recon.md services.md \
                finding.md pivot.md privesc.md ad.md; do
        assert_file_exists "$INT_PATH/$tmpl" "seeded internal: $tmpl present"
    done

    # web.md should NOT be in internal
    if [[ -f "$INT_PATH/web.md" ]]; then
        _record_fail "seeded internal: web.md should not exist" "present" "absent"
    else
        _record_pass "seeded internal: web.md correctly absent"
    fi

    # 6.5f  research profile — only recon.md
    "$EMPUSA_BIN" workspace init \
        --name "tmpl-research" \
        --profile "research" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active &>/dev/null || true

    RES_PATH="$WS_ROOT/tmpl-research"
    assert_file_exists "$RES_PATH/recon.md" "seeded research: recon.md present"

    # Other templates should NOT be in research
    for tmpl in engagement.md target.md services.md finding.md \
                privesc.md web.md pivot.md ad.md; do
        if [[ -f "$RES_PATH/$tmpl" ]]; then
            _record_fail "seeded research: $tmpl should not exist" "present" "absent"
        else
            _record_pass "seeded research: $tmpl correctly absent"
        fi
    done

    # 6.5g  build profile — no templates at all
    "$EMPUSA_BIN" workspace init \
        --name "tmpl-build" \
        --profile "build" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active &>/dev/null || true

    BUILD_PATH="$WS_ROOT/tmpl-build"
    for tmpl in $EXPECTED_TEMPLATES; do
        if [[ -f "$BUILD_PATH/$tmpl" ]]; then
            _record_fail "seeded build: $tmpl should not exist" "present" "absent"
        else
            _record_pass "seeded build: $tmpl correctly absent"
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  6.6  Metadata records seeded templates
# ═══════════════════════════════════════════════════════════════════
section "Metadata Template Tracking"

if [[ -x "$EMPUSA_BIN" ]] && [[ -f "$WS_PATH/.empusa-workspace.json" ]]; then
    # htb metadata should list seeded templates
    assert_file_contains "$WS_PATH/.empusa-workspace.json" "templates_seeded" \
        "metadata: has templates_seeded key"
    for tmpl in engagement.md target.md recon.md services.md \
                finding.md privesc.md web.md; do
        assert_file_contains "$WS_PATH/.empusa-workspace.json" "$tmpl" \
            "metadata: lists $tmpl in templates_seeded"
    done
else
    _record_pass "metadata template tracking: skip (no Empusa or no workspace)"
fi

# ═══════════════════════════════════════════════════════════════════
#  6.7  Section order validation
# ═══════════════════════════════════════════════════════════════════
section "Section Order"

# engagement.md sections must appear in logical order
assert_heading_order "$TEMPLATES_DIR/engagement.md" "engagement.md" \
    "Scope" "Rules" "Objectives" "Timeline"

# target.md: info before attack path
assert_heading_order "$TEMPLATES_DIR/target.md" "target.md" \
    "Open Ports" "Credentials" "Attack Path"

# finding.md: description before remediation
assert_heading_order "$TEMPLATES_DIR/finding.md" "finding.md" \
    "Description" "Evidence" "Impact" "Remediation"

# privesc.md: current access before escalation
assert_heading_order "$TEMPLATES_DIR/privesc.md" "privesc.md" \
    "Current Access" "Linux" "Windows" "Escalation Path"

# recon.md: passive before active
assert_heading_order "$TEMPLATES_DIR/recon.md" "recon.md" \
    "Passive" "Active" "Findings" "Next Steps"

# ═══════════════════════════════════════════════════════════════════
#  6.8  Markdown structure validation
# ═══════════════════════════════════════════════════════════════════
section "Markdown Structure"

for tmpl in $EXPECTED_TEMPLATES; do
    path="$TEMPLATES_DIR/$tmpl"

    # Must start with a top-level heading (# Title)
    first_heading="$(grep -nE '^#' "$path" | head -1)"
    if echo "$first_heading" | grep -qE '^[0-9]+:# '; then
        _record_pass "template $tmpl: starts with # heading"
    else
        _record_fail "template $tmpl: starts with #" "first heading: $first_heading" "# Title"
    fi

    # No orphan headings (heading followed immediately by heading, no content)
    orphan_count="$(awk '/^#{1,4} / { if (prev_was_heading) count++ } { prev_was_heading = /^#{1,4} / } END { print count+0 }' "$path")"
    if [[ "$orphan_count" -le 2 ]]; then
        _record_pass "template $tmpl: minimal orphan headings ($orphan_count)"
    else
        _record_fail "template $tmpl: orphan headings" "$orphan_count" "<=2"
    fi

    # No broken markdown links [text](broken)
    broken_links="$(grep -cE '\[.*\]\(\s*\)' "$path" || true)"
    [[ -z "$broken_links" ]] && broken_links=0
    if [[ "$broken_links" -eq 0 ]]; then
        _record_pass "template $tmpl: no broken links"
    else
        _record_fail "template $tmpl: broken links" "$broken_links" "0"
    fi
done

# ═══════════════════════════════════════════════════════════════════
#  6.9  Template destination path correctness
# ═══════════════════════════════════════════════════════════════════
section "Destination Paths"

if [[ -x "$EMPUSA_BIN" ]] && [[ -d "$WS_PATH" ]]; then
    # Templates should be seeded at workspace root, not in subdirectories
    for tmpl in engagement.md target.md recon.md services.md \
                finding.md privesc.md web.md; do
        if [[ -f "$WS_PATH/$tmpl" ]]; then
            _record_pass "dest: $tmpl at workspace root"
        else
            # Check if it ended up in a subdirectory by mistake
            found="$(find "$WS_PATH" -name "$tmpl" -type f 2>/dev/null | head -1)"
            if [[ -n "$found" ]]; then
                _record_fail "dest: $tmpl location" "$found" "$WS_PATH/$tmpl"
            else
                _record_fail "dest: $tmpl missing" "not found" "$WS_PATH/$tmpl"
            fi
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  6.10  Profile-template fit matrix
# ═══════════════════════════════════════════════════════════════════
section "Profile-Template Fit"

# Verify that no profile gets templates it shouldn't have
# htb: should NOT get pivot.md or ad.md (those are internal-only)
# internal: should NOT get web.md (that's htb-only)
# research: should ONLY get recon.md
# build: should get NO templates

if [[ -x "$EMPUSA_BIN" ]]; then
    declare -A FORBIDDEN_TEMPLATES
    FORBIDDEN_TEMPLATES[htb]="pivot.md ad.md"
    FORBIDDEN_TEMPLATES[internal]="web.md"
    FORBIDDEN_TEMPLATES[research]="engagement.md target.md services.md finding.md privesc.md web.md pivot.md ad.md"
    FORBIDDEN_TEMPLATES[build]="engagement.md target.md recon.md services.md finding.md privesc.md web.md pivot.md ad.md"

    for profile in htb internal research build; do
        ws_check="$WS_ROOT/tmpl-${profile}"
        [[ "$profile" == "htb" ]] && ws_check="$WS_PATH"  # reuse htb workspace
        if [[ -d "$ws_check" ]]; then
            for tmpl in ${FORBIDDEN_TEMPLATES[$profile]}; do
                if [[ -f "$ws_check/$tmpl" ]]; then
                    _record_fail "fit: $profile should not have $tmpl" "present" "absent"
                else
                    _record_pass "fit: $profile correctly lacks $tmpl"
                fi
            done
        fi
    done
fi

# ═══════════════════════════════════════════════════════════════════
#  6.11  Template-to-help consistency
# ═══════════════════════════════════════════════════════════════════
section "Template-Help Consistency"

# Templates referenced in help/docs should actually exist
if [[ -f "$REPO_ROOT/docs/labctl.md" ]]; then
    for tmpl in $EXPECTED_TEMPLATES; do
        base="${tmpl%.md}"
        # If docs mention this template name, verify template exists
        if grep -qi "$base" "$REPO_ROOT/docs/labctl.md" 2>/dev/null; then
            assert_file_exists "$TEMPLATES_DIR/$tmpl" \
                "consistency: docs mentions $base, template exists"
        fi
    done
fi

# labctl help output mentions templates → templates dir must be valid
help_out="$(bash "$REPO_ROOT/labctl" help 2>&1)" || true
if echo "$help_out" | grep -qi "template"; then
    assert_dir_exists "$TEMPLATES_DIR" "consistency: help mentions templates, dir exists"
    tmpl_count="$(find "$TEMPLATES_DIR" -name '*.md' -type f | wc -l)"
    if [[ "$tmpl_count" -ge 9 ]]; then
        _record_pass "consistency: templates dir has $tmpl_count files"
    else
        _record_fail "consistency: templates dir count" "$tmpl_count" ">=9"
    fi
fi

end_stage
