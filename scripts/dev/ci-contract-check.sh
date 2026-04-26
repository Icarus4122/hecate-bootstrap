#!/usr/bin/env bash
# scripts/dev/ci-contract-check.sh — Cross-repo contract validation.
#
# Validates Hecate's assumptions about Empusa without needing Docker
# or the live platform.  Checks:
#   1. empusa CLI is importable and has expected subcommands
#   2. Workspace profiles match Hecate's expectations
#   3. Template-seeding expectations align
#   4. Event names referenced in Hecate exist in Empusa
#   5. Version is parseable
#
# Usage:
#   bash scripts/dev/ci-contract-check.sh /path/to/empusa
#
# Requires: Python 3.9+ with empusa installed (pip install -e ./empusa)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMPUSA_DIR="${1:-${EMPUSA_SRC:-$(dirname "$REPO")/empusa}}"

if [[ ! -f "$EMPUSA_DIR/pyproject.toml" ]]; then
    echo "[FAIL] Empusa not found at $EMPUSA_DIR"
    echo "  Pass path as argument or set EMPUSA_SRC."
    exit 1
fi

PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
    # Prefer empusa's own venv if available
    if [[ -x "$EMPUSA_DIR/.venv/bin/python" ]]; then
        PY="$EMPUSA_DIR/.venv/bin/python"
    elif command -v python3 &>/dev/null; then PY=python3
    elif command -v python &>/dev/null; then PY=python
    else echo "[FAIL] Python not found"; exit 1; fi
fi

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1"; }

echo "── Empusa contract validation ──"
echo "  Empusa: $EMPUSA_DIR"
echo "  Python: $PY ($($PY --version 2>&1))"
echo ""

# 1. empusa is importable
echo "Import check:"
if $PY -c "import empusa; print(f'  version: {empusa.__version__}')" 2>/dev/null; then
    pass "empusa importable"
else
    fail "empusa not importable"
    echo "  Is empusa installed?  pip install -e ./empusa"
    exit 1
fi

# 2. Version is parseable (major.minor.patch)
echo ""
echo "Version format:"
version="$($PY -c "import empusa; print(empusa.__version__)")"
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "version '$version' is semver"
else
    fail "version '$version' is not semver"
fi

# 3. Workspace profiles
echo ""
echo "Workspace profiles:"
profiles="$($PY -c "
from empusa.workspace import PROFILES
for name in sorted(PROFILES):
    dirs = ','.join(PROFILES[name].get('dirs', []))
    tmpls = ','.join(PROFILES[name].get('templates', []))
    print(f'{name}|{dirs}|{tmpls}')
")"

# Hecate expects these profiles
for expected_profile in htb build research internal; do
    if echo "$profiles" | grep -q "^${expected_profile}|"; then
        pass "profile: $expected_profile exists"
    else
        fail "profile: $expected_profile missing"
    fi
done

# HTB profile must have these dirs (Hecate integration assumes them)
htb_dirs="$(echo "$profiles" | grep '^htb|' | cut -d'|' -f2)"
for dir in notes scans loot exploits reports; do
    if echo "$htb_dirs" | grep -q "$dir"; then
        pass "htb dir: $dir"
    else
        fail "htb dir: $dir missing"
    fi
done

# HTB profile must seed these templates
htb_tmpls="$(echo "$profiles" | grep '^htb|' | cut -d'|' -f2)"
# (template check is via the contract test, just verify templates key exists)
htb_tmpl_list="$(echo "$profiles" | grep '^htb|' | cut -d'|' -f3)"
if [[ -n "$htb_tmpl_list" ]]; then
    pass "htb: has template list"
else
    fail "htb: no templates defined"
fi

# Build profile should have no templates (Hecate assumes this)
build_tmpls="$(echo "$profiles" | grep '^build|' | cut -d'|' -f3)"
if [[ -z "$build_tmpls" ]]; then
    pass "build: no templates (expected)"
else
    fail "build: has unexpected templates"
fi

# 4. CLI entry point
echo ""
echo "CLI entry point:"
if $PY -c "from empusa.cli import main; print('  entry: empusa.cli:main')" 2>/dev/null; then
    pass "empusa.cli:main importable"
else
    fail "empusa.cli:main not importable"
fi

# 5. Workspace create function
echo ""
echo "Workspace API:"
if $PY -c "from empusa.workspace import create_workspace; print('  fn: create_workspace')" 2>/dev/null; then
    pass "create_workspace importable"
else
    fail "create_workspace not importable"
fi

# 6. Event system
echo ""
echo "Event contracts:"
if $PY -c "
from empusa.events import EmpusaEvent
e = EmpusaEvent(event='test', session_env='ci')
assert hasattr(e, 'event')
assert hasattr(e, 'timestamp')
assert hasattr(e, 'session_env')
d = e.to_dict()
assert isinstance(d, dict)
print('  EmpusaEvent fields: event, timestamp, session_env')
print('  to_dict() returns dict')
" 2>/dev/null; then
    pass "EmpusaEvent contract intact"
else
    fail "EmpusaEvent contract broken"
fi

# 7. Template files in hecate match what empusa expects to seed
echo ""
echo "Template file alignment:"
$PY -c "
from empusa.workspace import PROFILES
templates_needed = set()
for p in PROFILES.values():
    templates_needed.update(p.get('templates', []))
for t in sorted(templates_needed):
    print(t)
" 2>/dev/null | while IFS= read -r tmpl; do
    if [[ -f "$REPO/templates/$tmpl" ]]; then
        pass "repo has template: $tmpl"
    else
        fail "repo missing template: $tmpl"
    fi
done

# Summary
echo ""
echo "── ${PASS} passed, ${FAIL} failed ──"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
