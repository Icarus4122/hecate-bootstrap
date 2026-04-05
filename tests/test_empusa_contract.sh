#!/usr/bin/env bash
# tests/test_empusa_contract.sh — Cross-repo workspace contract validation.
#
# Validates that Hecate's integration assumptions match the real Empusa
# workspace module.  Source of truth: empusa/workspace.py
#
# Prerequisites:
#   - python3 (≥ 3.9) or python
#   - Empusa source tree (sibling at ../empusa or EMPUSA_SRC env var)
#
# Skips gracefully when prerequisites are missing.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "Empusa workspace contract"

REPO_DIR="$(dirname "$TESTS_DIR")"
TEMPLATES_DIR="$REPO_DIR/templates"

# ── Python detection ───────────────────────────────────────────────
PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
    if   command -v python3 &>/dev/null; then PY=python3
    elif command -v python  &>/dev/null; then PY=python
    fi
fi

if [[ -z "$PY" ]]; then
    echo "# SKIP: python not found"
    end_tests
    exit 0
fi

# ── Locate Empusa source ──────────────────────────────────────────
EMPUSA_SRC="${EMPUSA_SRC:-}"
if [[ -z "$EMPUSA_SRC" ]]; then
    candidate="$(cd "$REPO_DIR/.." && pwd)/empusa"
    if [[ -f "$candidate/empusa/workspace.py" ]]; then
        EMPUSA_SRC="$candidate"
    fi
fi

if [[ -z "$EMPUSA_SRC" || ! -f "$EMPUSA_SRC/empusa/workspace.py" ]]; then
    echo "# SKIP: Empusa source not found (set EMPUSA_SRC or clone as sibling)"
    end_tests
    exit 0
fi

# ── Path helpers ───────────────────────────────────────────────────
# Git Bash on Windows needs cygpath for paths passed to Python.
_pypath() {
    if command -v cygpath &>/dev/null; then cygpath -m "$1"; else echo "$1"; fi
}

# Run a python -c snippet and strip Windows \r from output.
_pyrun() { "$PY" -c "$1" | tr -d '\r'; }

# PYTHONPATH separator: ; on Windows, : elsewhere.
_empusa_pypath="$(_pypath "$EMPUSA_SRC")"
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
    export PYTHONPATH="${_empusa_pypath}${PYTHONPATH:+;$PYTHONPATH}"
else
    export PYTHONPATH="${_empusa_pypath}${PYTHONPATH:+:$PYTHONPATH}"
fi

if ! "$PY" -c "from empusa.workspace import PROFILES, METADATA_FILENAME" 2>/dev/null; then
    echo "# SKIP: cannot import empusa.workspace (Python >= 3.9 required)"
    end_tests
    exit 0
fi

make_sandbox
WS_ROOT="$SANDBOX/workspaces"
mkdir -p "$WS_ROOT"

_py_ws="$(_pypath "$WS_ROOT")"
_py_tpl="$(_pypath "$TEMPLATES_DIR")"

# ═══════════════════════════════════════════════════════════════════
#  1. Contract constants
# ═══════════════════════════════════════════════════════════════════

META_FILENAME=$(_pyrun "
from empusa.workspace import METADATA_FILENAME
print(METADATA_FILENAME)
")
assert_eq ".empusa-workspace.json" "$META_FILENAME" \
    "constant: METADATA_FILENAME"

DEFAULT_ROOT=$(_pyrun "
from empusa.workspace import DEFAULT_WORKSPACE_ROOT
print(DEFAULT_WORKSPACE_ROOT.as_posix())
")
assert_eq "/opt/lab/workspaces" "$DEFAULT_ROOT" \
    "constant: DEFAULT_WORKSPACE_ROOT"

PROFILE_LIST=$(_pyrun "
from empusa.workspace import PROFILES
print(' '.join(sorted(PROFILES)))
")
assert_eq "build htb internal research" "$PROFILE_LIST" \
    "profiles: build, htb, internal, research"

# ═══════════════════════════════════════════════════════════════════
#  2. Per-profile workspace creation + validation
# ═══════════════════════════════════════════════════════════════════

validate_profile() {
    local profile="$1"

    # Extract expected dirs
    local expected_dirs
    expected_dirs=$(_pyrun "
from empusa.workspace import PROFILES
for d in PROFILES['${profile}']['dirs']:
    print(d)
")

    # Extract expected templates
    local expected_templates
    expected_templates=$(_pyrun "
from empusa.workspace import PROFILES
for t in PROFILES['${profile}'].get('templates', []):
    print(t)
")

    # Create workspace via real Empusa code
    "$PY" -c "
from pathlib import Path
from empusa.workspace import create_workspace
create_workspace(
    name='test-${profile}',
    profile='${profile}',
    root=Path('${_py_ws}'),
    templates_dir=Path('${_py_tpl}'),
    set_active=True,
    template_vars={
        'NAME': 'test-${profile}',
        'PROFILE': '${profile}',
        'DATE': '2026-01-01',
    },
)
"

    local ws="$WS_ROOT/test-${profile}"

    # -- Directories -------------------------------------------------
    assert_dir_exists "$ws" "${profile}: workspace root"

    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        assert_dir_exists "$ws/$d" "${profile}: dir ${d}/"
    done <<< "$expected_dirs"

    # -- Templates ---------------------------------------------------
    while IFS= read -r t; do
        [[ -n "$t" ]] || continue
        assert_file_exists "$ws/$t" "${profile}: template ${t}"
    done <<< "$expected_templates"

    # -- Metadata file -----------------------------------------------
    assert_file_exists "$ws/$META_FILENAME" "${profile}: metadata file"

    # Validate required metadata keys
    local meta_keys_ok
    meta_keys_ok=$(_pyrun "
import json; from pathlib import Path
meta = json.loads(Path('$(_pypath "$ws/$META_FILENAME")').read_text())
need = {'profile', 'name', 'path', 'created_at', 'templates_seeded'}
missing = need - set(meta.keys())
print('ok' if not missing else 'missing: ' + ', '.join(sorted(missing)))
")
    assert_eq "ok" "$meta_keys_ok" "${profile}: metadata keys complete"

    # Validate metadata profile value
    local meta_profile
    meta_profile=$(_pyrun "
import json; from pathlib import Path
print(json.loads(Path('$(_pypath "$ws/$META_FILENAME")').read_text())['profile'])
")
    assert_eq "$profile" "$meta_profile" "${profile}: metadata profile value"
}

for p in htb build research internal; do
    validate_profile "$p"
done

# ═══════════════════════════════════════════════════════════════════
#  3. Idempotency — re-creating existing workspace
# ═══════════════════════════════════════════════════════════════════

already=$(_pyrun "
from pathlib import Path
from empusa.workspace import create_workspace
r = create_workspace(name='test-htb', profile='htb', root=Path('${_py_ws}'))
print(r.already_existed)
")
assert_eq "True" "$already" \
    "idempotent: already_existed=True on re-create"

# ═══════════════════════════════════════════════════════════════════
#  4. Template availability in Hecate repo
# ═══════════════════════════════════════════════════════════════════
# Every template referenced by any Empusa profile must exist in
# hecate-bootstrap/templates/ — otherwise workspace creation would
# report templates_missing.

ALL_TPL=$(_pyrun "
from empusa.workspace import PROFILES
seen = set()
for p in PROFILES.values():
    for t in p.get('templates', []):
        if t not in seen:
            seen.add(t)
            print(t)
")
while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    assert_file_exists "$TEMPLATES_DIR/$t" "hecate has template: ${t}"
done <<< "$ALL_TPL"

# ═══════════════════════════════════════════════════════════════════
#  5. Fallback dirs ⊆ htb profile
# ═══════════════════════════════════════════════════════════════════
# Hecate's shell fallback (no Empusa) creates: notes, scans, loot, logs.
# These must all be present in the htb profile (default profile in
# create-workspace.sh) so the fallback is a strict subset.

for fb in notes scans loot logs; do
    in_htb=$(_pyrun "
from empusa.workspace import PROFILES
print('yes' if '${fb}' in PROFILES['htb']['dirs'] else 'no')
")
    assert_eq "yes" "$in_htb" "fallback dir '${fb}' in htb profile"
done

# ═══════════════════════════════════════════════════════════════════
#  6. set_active=True does not error
# ═══════════════════════════════════════════════════════════════════

rc=0
"$PY" -c "
from pathlib import Path
from empusa.workspace import create_workspace
create_workspace(
    name='active-test',
    profile='htb',
    root=Path('${_py_ws}'),
    set_active=True,
)
" 2>/dev/null || rc=$?
assert_eq "0" "$rc" "set_active=True: no error"

end_tests
