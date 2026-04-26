#!/usr/bin/env bash
# scripts/dev/release-sanity.sh — Read-only release readiness check.
#
# Validates version consistency, changelog alignment, lint, and test
# health across both Empusa (sibling repo) and Hecate-bootstrap.
#
# Used by: VSCode "Cross-repo: Release sanity" task.
# This script is READ-ONLY — it never creates tags, mutates files,
# or publishes anything.
#
# Why a helper script?  The version/changelog checks require nested
# quoting (Python -c inside bash inside JSON) that makes an inline
# task command brittle and unreadable.  Keeping it here makes the
# logic transparent, testable, and versionable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HECATE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
EMPUSA_DIR="${EMPUSA_SRC:-$(dirname "$HECATE_DIR")/empusa}"

if [[ ! -f "$EMPUSA_DIR/pyproject.toml" ]]; then
    echo "[FAIL] Empusa not found at $EMPUSA_DIR"
    echo "  Set EMPUSA_SRC to override."
    exit 1
fi

# ── Python detection ───────────────────────────────────────────────
PY="${PYTHON:-}"
if [[ -z "$PY" ]]; then
    if   command -v python3 &>/dev/null; then PY=python3
    elif command -v python  &>/dev/null; then PY=python
    else echo "[FAIL] python not found"; exit 1
    fi
fi

# ── Activate venv if present (needed when running outside VS Code
#    activated terminal, e.g. plain bash) ───────────────────────────
if [[ -f "$EMPUSA_DIR/.venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source "$EMPUSA_DIR/.venv/bin/activate"
elif [[ -f "$EMPUSA_DIR/.venv/Scripts/activate" ]]; then
    # shellcheck disable=SC1091
    source "$EMPUSA_DIR/.venv/Scripts/activate"
fi

echo "── Empusa ($EMPUSA_DIR) ──"
cd "$EMPUSA_DIR"

# Version consistency: __init__.py vs pyproject.toml
V=$(grep '__version__' empusa/__init__.py | head -1 | sed 's/.*"\(.*\)".*/\1/')
TV=$(grep '^version = ' pyproject.toml | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [[ "$V" != "$TV" ]]; then
    echo "[FAIL] version mismatch: __init__=$V  pyproject.toml=$TV"
    exit 1
fi
echo "[PASS] version $V consistent"

# Changelog
if grep -qF "[$V]" CHANGELOG.md; then
    echo "[PASS] [$V] in CHANGELOG.md"
else
    echo "[FAIL] [$V] not found in CHANGELOG.md"
    exit 1
fi

# Tag (advisory — not a hard failure)
if git tag -l "v$V" | grep -q .; then
    echo "[PASS] tag v$V exists"
else
    echo "[WARN] tag v$V not found (pre-release)"
fi

# Lint
echo ""
$PY -m ruff check empusa/ tests/ && echo "[PASS] ruff clean"

# Tests
echo ""
$PY -m pytest --tb=short -q

echo ""
echo "── Hecate ($HECATE_DIR) ──"
cd "$HECATE_DIR"
bash tests/run-all.sh

echo ""
echo "── Release sanity passed ──"
