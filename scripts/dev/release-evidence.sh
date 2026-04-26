#!/usr/bin/env bash
# scripts/dev/release-evidence.sh — Collect reproducible release evidence.
#
# Read-only.  Captures:
#   - Hecate git commit SHA, branch/tag, dirty/clean status
#   - Docker / Compose versions if installed
#   - Docker base image refs from Dockerfiles (warns on mutable :latest)
#   - Optional local image digests when docker is available
#   - Empusa expected contract version (from release-sanity.sh)
#   - Empusa source version (when EMPUSA_SRC or positional arg supplied)
#   - STRICT_CHECKSUMS status + binaries.tsv checksum summary
#
# Usage:
#   scripts/dev/release-evidence.sh                       # report to stdout
#   scripts/dev/release-evidence.sh --out FILE            # also write to FILE
#   scripts/dev/release-evidence.sh --strict              # fail on dirty worktree,
#                                                         # not-in-git, missing
#                                                         # release-sanity.sh, or
#                                                         # Empusa contract mismatch
#   scripts/dev/release-evidence.sh /path/to/empusa       # include Empusa version
#   EMPUSA_SRC=/path/to/empusa scripts/dev/release-evidence.sh
#
# Does NOT require Docker.  Does NOT require network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HECATE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

OUT_FILE=""
STRICT=0
EMPUSA_DIR=""
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            [[ -z "${2:-}" ]] && { echo "[FAIL] --out requires a file path" >&2; exit 1; }
            OUT_FILE="$2"; shift 2 ;;
        --strict) STRICT=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0"; exit 0 ;;
        *)
            EMPUSA_DIR="$1"; shift ;;
    esac
done

if [[ -z "$EMPUSA_DIR" && -n "${EMPUSA_SRC:-}" ]]; then
    EMPUSA_DIR="$EMPUSA_SRC"
fi

# ── Output buffer (mirrored to stdout and optionally a file) ───────
TMPOUT="$(mktemp)"
trap 'rm -f "$TMPOUT"' EXIT

emit() { echo "$1" | tee -a "$TMPOUT"; }
section() { emit ""; emit "── $1 ──"; }

emit "# Hecate release evidence"
emit "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
emit "Repo: $HECATE_DIR"

# ── Git ────────────────────────────────────────────────────────────
section "Git"
if git -C "$HECATE_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    sha="$(git -C "$HECATE_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    branch="$(git -C "$HECATE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    tag="$(git -C "$HECATE_DIR" describe --tags --exact-match 2>/dev/null || echo "")"
    dirty="clean"
    if [[ -n "$(git -C "$HECATE_DIR" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi
    emit "[INFO] commit:  $sha"
    emit "[INFO] branch:  $branch"
    if [[ -n "$tag" ]]; then
        emit "[INFO] tag:     $tag"
    else
        emit "[INFO] tag:     (none — not on a tagged commit)"
    fi
    if [[ "$dirty" == "clean" ]]; then
        emit "[PASS] worktree clean"
    else
        if [[ "$STRICT" == "1" ]]; then
            emit "[FAIL] worktree dirty (strict mode)"
            EXIT_CODE=1
        else
            emit "[WARN] worktree dirty (uncommitted changes present)"
        fi
    fi
else
    if [[ "$STRICT" == "1" ]]; then
        emit "[FAIL] not a git repository (strict mode)"
        EXIT_CODE=1
    else
        emit "[WARN] not a git repository — git evidence unavailable"
    fi
fi

# ── Docker ─────────────────────────────────────────────────────────
section "Docker"
if command -v docker >/dev/null 2>&1; then
    dv="$(docker --version 2>/dev/null || echo unknown)"
    emit "[INFO] $dv"
    if docker compose version >/dev/null 2>&1; then
        cv="$(docker compose version 2>/dev/null | head -1)"
        emit "[INFO] $cv"
    elif command -v docker-compose >/dev/null 2>&1; then
        cv="$(docker-compose --version 2>/dev/null | head -1)"
        emit "[INFO] $cv"
    else
        emit "[WARN] docker compose not found"
    fi
else
    emit "[WARN] docker not installed — image digests unavailable"
fi

# ── Docker base image evidence ─────────────────────────────────────
section "Docker base image evidence"
mapfile -t DOCKERFILES < <(find "$HECATE_DIR/docker" -name Dockerfile -type f 2>/dev/null | sort)
if command -v docker >/dev/null 2>&1; then
    DOCKER_OK=1
else
    DOCKER_OK=0
    emit "[WARN] docker unavailable; digest evidence skipped"
fi
if [[ ${#DOCKERFILES[@]} -eq 0 ]]; then
    emit "[WARN] no Dockerfiles found under docker/"
else
    for df in "${DOCKERFILES[@]}"; do
        rel="${df#"$HECATE_DIR/"}"
        # Read first FROM line
        from_line="$(grep -E '^FROM[[:space:]]' "$df" | head -1 || true)"
        if [[ -z "$from_line" ]]; then
            emit "[WARN] $rel: no FROM line"
            continue
        fi
        image="$(echo "$from_line" | awk '{print $2}')"
        emit "[INFO] $rel -> FROM $image"
        # Mutable tag detection
        if [[ "$image" == *"@sha256:"* ]]; then
            emit "[PASS]   digest pinned"
        elif [[ "$image" == *":latest" ]]; then
            emit "[WARN]   uses mutable tag :latest (not reproducible)"
        elif [[ "$image" != *":"* ]]; then
            emit "[WARN]   no tag specified (defaults to :latest, not reproducible)"
        else
            emit "[WARN]   tag-based reference (consider @sha256:<digest> for full reproducibility)"
        fi
        # Optional local digest evidence (no network pulls)
        if [[ "$DOCKER_OK" == "1" ]]; then
            digest="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image" 2>/dev/null || true)"
            digest="$(printf '%s' "$digest" | sed '/^$/d')"
            if [[ -n "$digest" ]]; then
                while IFS= read -r d; do
                    emit "[INFO]   local RepoDigest: $d"
                done <<< "$digest"
            else
                emit "[WARN]   digest unavailable locally (image not pulled; no auto-pull)"
            fi
        fi
    done
fi

# ── Empusa contract pin ────────────────────────────────────────────
section "Empusa contract"
SANITY="$HECATE_DIR/scripts/dev/release-sanity.sh"
if [[ -f "$SANITY" ]]; then
    expected="$(grep -E '^EXPECTED_EMPUSA_VERSION=' "$SANITY" | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/')"
    emit "[INFO] expected Empusa contract version: ${expected:-unknown}"
else
    if [[ "$STRICT" == "1" ]]; then
        emit "[FAIL] release-sanity.sh not found — cannot read contract pin (strict mode)"
        EXIT_CODE=1
    else
        emit "[WARN] release-sanity.sh not found — cannot read contract pin"
    fi
fi

if [[ -n "$EMPUSA_DIR" ]]; then
    if [[ -f "$EMPUSA_DIR/pyproject.toml" ]]; then
        emp_v="$(grep -E '^version[[:space:]]*=' "$EMPUSA_DIR/pyproject.toml" \
            | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
        emit "[INFO] Empusa source version (pyproject.toml): ${emp_v:-unknown}"
        if [[ -n "${expected:-}" && "$emp_v" == "${expected:-}" ]]; then
            emit "[PASS] Empusa source matches expected contract version"
        elif [[ -n "${expected:-}" ]]; then
            if [[ "$STRICT" == "1" ]]; then
                emit "[FAIL] Empusa source version ${emp_v} != expected ${expected} (strict mode)"
                EXIT_CODE=1
            else
                emit "[WARN] Empusa source version ${emp_v} != expected ${expected}"
            fi
        fi
    else
        emit "[WARN] Empusa pyproject.toml not found at $EMPUSA_DIR"
    fi
else
    emit "[INFO] Empusa source not supplied (set EMPUSA_SRC or pass path)"
fi

# ── Binary checksum summary ────────────────────────────────────────
section "Binary checksums"
emit "[INFO] STRICT_CHECKSUMS=${STRICT_CHECKSUMS:-0}"
MANIFEST="$HECATE_DIR/manifests/binaries.tsv"
if [[ ! -f "$MANIFEST" ]]; then
    emit "[WARN] manifest not found: $MANIFEST"
else
    total=0; pinned=0; todo=0; bad=0; allassets_todo=0
    while IFS=$'\t' read -r f_name f_type f_repo f_tag f_mode f_dest f_flags f_sha256 || [[ -n "${f_name:-}" ]]; do
        [[ -z "${f_name:-}" || "${f_name:0:1}" == "#" ]] && continue
        [[ "$f_name" == "name" ]] && continue
        total=$((total + 1))
        f_sha256="${f_sha256:-TODO_SHA256}"
        # Tolerate stray CR on manifests checked out with autocrlf.
        f_sha256="${f_sha256%$'\r'}"
        f_mode="${f_mode%$'\r'}"
        if [[ "$f_sha256" == "TODO_SHA256" ]]; then
            todo=$((todo + 1))
            if [[ "$f_mode" == "all-assets" ]]; then
                allassets_todo=$((allassets_todo + 1))
                emit "[WARN] ${f_name}: TODO_SHA256 (mode=all-assets — per-asset checksums not supported)"
            else
                emit "[WARN] ${f_name}: TODO_SHA256 (unpinned)"
            fi
        elif [[ "$f_sha256" =~ ^[a-f0-9]{64}$ ]]; then
            pinned=$((pinned + 1))
            emit "[PASS] ${f_name}: sha256 pinned"
        else
            bad=$((bad + 1))
            emit "[FAIL] ${f_name}: malformed sha256"
        fi
    done < "$MANIFEST"
    emit "[INFO] manifest summary: ${total} rows, ${pinned} pinned, ${todo} TODO_SHA256 (${allassets_todo} all-assets), ${bad} malformed"
fi

# ── Final ──────────────────────────────────────────────────────────
section "Result"
if [[ "$EXIT_CODE" -eq 0 ]]; then
    emit "[PASS] release evidence collected"
else
    emit "[FAIL] release evidence collection reported blockers"
fi

# ── Optional file output ───────────────────────────────────────────
if [[ -n "$OUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUT_FILE")"
    cp "$TMPOUT" "$OUT_FILE"
    echo "[INFO] evidence written to: $OUT_FILE"
fi

exit "$EXIT_CODE"
