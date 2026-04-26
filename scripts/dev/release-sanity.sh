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

# ── Pinned cross-repo contract version ─────────────────────────────
# Bump this in lockstep with Empusa releases. Mismatch with the
# supplied Empusa source tree fails release-sanity (see Task 2 below).
EXPECTED_EMPUSA_VERSION="2.3.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HECATE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Allow positional override:  release-sanity.sh /path/to/empusa
if [[ $# -ge 1 && -n "${1:-}" ]]; then
    EMPUSA_DIR="$1"
else
    EMPUSA_DIR="${EMPUSA_SRC:-$(dirname "$HECATE_DIR")/empusa}"
fi

if [[ ! -f "$EMPUSA_DIR/pyproject.toml" ]]; then
    echo "[FAIL] Empusa not found at $EMPUSA_DIR"
    echo "  Set EMPUSA_SRC or pass the path as the first argument."
    exit 1
fi

# ── Hecate-side contract reference ─────────────────────────────────
# A Hecate-owned doc must record the same expected Empusa contract
# version so doc/code drift is caught at release time.
HECATE_CONTRACT_DOC="$HECATE_DIR/docs/dev/cross-repo-contract-audit.md"
HECATE_CONTRACT_MARKER="**Expected Empusa contract version:** \`${EXPECTED_EMPUSA_VERSION}\`"
if [[ ! -f "$HECATE_CONTRACT_DOC" ]]; then
    echo "[FAIL] Hecate contract doc missing: $HECATE_CONTRACT_DOC"
    exit 1
fi
if grep -qF "$HECATE_CONTRACT_MARKER" "$HECATE_CONTRACT_DOC"; then
    echo "[PASS] Hecate doc pins Empusa contract version $EXPECTED_EMPUSA_VERSION"
else
    echo "[FAIL] Hecate contract reference missing in $HECATE_CONTRACT_DOC"
    echo "  expected line containing: $HECATE_CONTRACT_MARKER"
    exit 1
fi

# ── Static Empusa version checks (no import, no install needed) ────
echo "── Empusa contract version pin ──"

empusa_pyproject_version=$(grep -E '^version[[:space:]]*=' "$EMPUSA_DIR/pyproject.toml" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ "$empusa_pyproject_version" == "$EXPECTED_EMPUSA_VERSION" ]]; then
    echo "[PASS] Empusa pyproject.toml version = $empusa_pyproject_version"
else
    echo "[FAIL] Empusa pyproject.toml version mismatch"
    echo "  expected: $EXPECTED_EMPUSA_VERSION"
    echo "  actual:   ${empusa_pyproject_version:-<unset>}"
    exit 1
fi

empusa_init_version=$(grep -E '^__version__[[:space:]]*=' "$EMPUSA_DIR/empusa/__init__.py" \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ "$empusa_init_version" == "$EXPECTED_EMPUSA_VERSION" ]]; then
    echo "[PASS] Empusa __init__.py __version__ = $empusa_init_version"
else
    echo "[FAIL] Empusa empusa/__init__.py __version__ mismatch"
    echo "  expected: $EXPECTED_EMPUSA_VERSION"
    echo "  actual:   ${empusa_init_version:-<unset>}"
    exit 1
fi

if [[ ! -f "$EMPUSA_DIR/CHANGELOG.md" ]]; then
    echo "[FAIL] Empusa CHANGELOG.md missing at $EMPUSA_DIR/CHANGELOG.md"
    exit 1
fi
# Accept "## [2.3.0]" or "## 2.3.0" or "## v2.3.0" headings.
if grep -Eq "^#{1,3}[[:space:]]+\[?v?${EXPECTED_EMPUSA_VERSION//./\\.}\]?" \
        "$EMPUSA_DIR/CHANGELOG.md"; then
    echo "[PASS] Empusa CHANGELOG.md has heading for $EXPECTED_EMPUSA_VERSION"
else
    echo "[FAIL] Empusa CHANGELOG.md missing heading for $EXPECTED_EMPUSA_VERSION"
    exit 1
fi

# Allow callers (tests) to stop after the static contract checks.
if [[ "${RELEASE_SANITY_VERSION_ONLY:-0}" == "1" ]]; then
    echo "── Version-only mode: contract checks passed ──"
    exit 0
fi

# ── Strict checksum gate ──────────────────────────────────────────
# Release-grade sync requires every active binary row in
# manifests/binaries.tsv to carry a real lowercase 64-hex sha256.
# TODO_SHA256 entries are accepted in dev mode but block a release.
#
# Per-asset checksums are not supported for mode=all-assets rows
# (sync-binaries.sh enforces this).  Such rows therefore cannot pass
# strict checksum validation until they are narrowed to a single
# deterministic asset filename and pinned.
#
# Skip with RELEASE_SANITY_SKIP_CHECKSUMS=1 when intentionally
# building a non-release / dev snapshot.
echo ""
echo "── Strict binary checksum gate ──"
HECATE_MANIFEST="$HECATE_DIR/manifests/binaries.tsv"
if [[ "${RELEASE_SANITY_SKIP_CHECKSUMS:-0}" == "1" ]]; then
    echo "[WARN] Strict checksum gate skipped (RELEASE_SANITY_SKIP_CHECKSUMS=1)"
elif [[ ! -f "$HECATE_MANIFEST" ]]; then
    echo "[FAIL] Manifest not found: $HECATE_MANIFEST"
    exit 1
else
    checksum_failures=0
    checksum_rows=0
    while IFS=$'\t' read -r f_name f_type f_repo f_tag f_mode f_dest f_flags f_sha256 || [[ -n "${f_name:-}" ]]; do
        # Skip blanks / comments
        [[ -z "${f_name:-}" || "${f_name:0:1}" == "#" ]] && continue
        [[ "$f_name" == "name" ]] && continue
        checksum_rows=$((checksum_rows + 1))
        f_sha256="${f_sha256:-TODO_SHA256}"
        # Tolerate stray CR on manifests checked out with autocrlf.
        f_sha256="${f_sha256%$'\r'}"
        f_mode="${f_mode%$'\r'}"
        if [[ "$f_sha256" == "TODO_SHA256" ]]; then
            if [[ "$f_mode" == "all-assets" ]]; then
                echo "[FAIL] ${f_name}: mode=all-assets cannot be strictly pinned"
                echo "       Per-asset checksums are not supported for all-assets rows."
                echo "       Narrow the row to a single asset filename, then pin its sha256."
            else
                echo "[FAIL] ${f_name}: TODO_SHA256 (unpinned) — pin in manifests/binaries.tsv"
            fi
            checksum_failures=$((checksum_failures + 1))
        elif [[ ! "$f_sha256" =~ ^[a-f0-9]{64}$ ]]; then
            echo "[FAIL] ${f_name}: malformed sha256 (expected 64 lowercase hex): ${f_sha256}"
            checksum_failures=$((checksum_failures + 1))
        else
            echo "[PASS] ${f_name}: sha256 pinned"
        fi
    done < "$HECATE_MANIFEST"
    if [[ $checksum_failures -gt 0 ]]; then
        echo "[FAIL] ${checksum_failures}/${checksum_rows} binary rows fail strict checksum gate"
        echo "       Set RELEASE_SANITY_SKIP_CHECKSUMS=1 only for non-release dev snapshots."
        exit 1
    fi
    echo "[PASS] All ${checksum_rows} active binary row(s) pass strict checksum gate"
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

# Re-confirm version consistency between __init__.py and pyproject.toml
# (already validated against the pin above; this preserves the original
# free-form report for operators).
V="$empusa_init_version"
TV="$empusa_pyproject_version"
if [[ "$V" != "$TV" ]]; then
    echo "[FAIL] version mismatch: __init__=$V  pyproject.toml=$TV"
    exit 1
fi
echo "[PASS] version $V consistent"

# Changelog (legacy "[X]" check kept for backward-compat operator output)
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
