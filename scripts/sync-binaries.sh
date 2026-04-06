#!/usr/bin/env bash
# scripts/sync-binaries.sh - Manifest-driven download of pinned external binaries.
# Reads manifests/binaries.tsv -> writes to ${LAB_ROOT}/tools/binaries/.
#
# Usage:
#   sync-binaries.sh                    Sync all manifest entries
#   sync-binaries.sh --name chisel      Sync only the entry named "chisel"
#   sync-binaries.sh --dry-run          Preview without downloading
#
# Requires: curl, jq, file
# Optional: GITHUB_TOKEN env var for higher API rate limits (60 -> 5000 req/h)
set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/lib/ui.sh"
MANIFEST="${REPO_DIR}/manifests/binaries.tsv"
BIN_DIR="${LAB_ROOT:-/opt/lab}/tools/binaries"

# ── State ──────────────────────────────────────────────────────────────────────
DRY_RUN=false
FILTER=""
ERRORS=0
SYNCED=0
SKIPPED=0

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: sync-binaries.sh [OPTIONS]

Download pinned external binaries listed in manifests/binaries.tsv
into ${LAB_ROOT}/tools/binaries/.

Options:
  -n, --name NAME   Sync only the named manifest entry
  --dry-run         Preview what would be downloaded (no writes)
  -h, --help        Show this help

Environment:
  LAB_ROOT          Base lab directory       (default: /opt/lab)
  GITHUB_TOKEN      GitHub PAT - raises API rate limit from 60 to 5 000 req/h
EOF
    exit 0
}

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)
            [[ -z "${2:-}" ]] && { ui_fail "--name requires an argument"; exit 1; }
            FILTER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) ui_fail "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
missing=()
for cmd in curl jq file; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    ui_fail "Missing required commands: ${missing[*]}"
    ui_fix "sudo apt install ${missing[*]}"
    exit 1
fi

# ── GitHub API helpers ─────────────────────────────────────────────────────────
gh_curl_opts=(-fsSL -H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    gh_curl_opts+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

declare -A _release_cache

# Fetch and cache release JSON for a given repo + tag.
fetch_release() {
    local repo="$1" tag="$2"
    local key="${repo}@${tag}"

    if [[ -v _release_cache["$key"] ]]; then
        printf '%s' "${_release_cache[$key]}"
        return 0
    fi

    local url="https://api.github.com/repos/${repo}/releases/tags/${tag}"
    local json
    if ! json="$(curl "${gh_curl_opts[@]}" "$url")"; then
        echo "    [FAIL] GitHub API request failed: ${url}" >&2
        if [[ -z "${GITHUB_TOKEN:-}" ]]; then
            echo "       Rate-limited?  Set GITHUB_TOKEN for 5 000 req/h (vs 60 anonymous)." >&2
            echo "       Fix: export GITHUB_TOKEN=ghp_..." >&2
        fi
        return 1
    fi

    if ! printf '%s' "$json" | jq -e '.assets' &>/dev/null; then
        echo "    [FAIL] Unexpected API response — no .assets array" >&2
        echo "       URL: ${url}" >&2
        return 1
    fi

    _release_cache["$key"]="$json"
    printf '%s' "$json"
}

# ── File validation ────────────────────────────────────────────────────────────
# Inspect a downloaded file with file(1) and reject bogus content.
#   $1 = path   $2 = "true" to permit text/JSON content
validate_download() {
    local fpath="$1" allow_text="${2:-false}"
    local ftype
    ftype="$(file -b "$fpath")"

    # HTML is always rejected - strong indicator of a redirect or error page.
    if [[ "$ftype" == *"HTML document"* ]]; then
        echo "    [FAIL] Rejected: HTML document (download likely returned an error page)"
        echo "       file(1): ${ftype}"
        return 1
    fi

    # XML is always rejected for the same reason.
    if [[ "$ftype" == *"XML document"* ]]; then
        echo "    [FAIL] Rejected: XML document"
        echo "       file(1): ${ftype}"
        return 1
    fi

    # Text / JSON rejected unless the caller explicitly allows it.
    if [[ "$allow_text" != "true" ]]; then
        if [[ "$ftype" == *"text"* || "$ftype" == *"JSON"* ]]; then
            echo "    [FAIL] Rejected: file identified as text, not binary/archive"
            echo "       file(1): ${ftype}"
            return 1
        fi
    fi

    return 0
}

# ── Download a single file ─────────────────────────────────────────────────────
#   $1=url  $2=dest_path  $3=allow_text  $4=make_executable
download_one() {
    local url="$1" dest="$2" allow_text="$3" make_exec="$4"
    local tmp="${dest}.tmp.$$"

    if ! curl -fsSL -o "$tmp" "$url"; then
        echo "    [FAIL] Download failed"
        echo "       URL: ${url}"
        rm -f "$tmp"
        return 1
    fi

    if ! validate_download "$tmp" "$allow_text"; then
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$dest"

    if [[ "$make_exec" == "true" ]]; then
        chmod +x "$dest"
    fi

    local desc
    desc="$(file -b "$dest" | head -c 72)"
    echo "    [PASS] ${desc}"
    return 0
}

# ── File size (bytes) ──────────────────────────────────────────────────────────
file_size() { stat --format='%s' "$1" 2>/dev/null; }

# ── Process one manifest entry ─────────────────────────────────────────────────
process_entry() {
    local name="$1" type="$2" repo="$3" tag="$4" mode="$5" dest="$6" flags="$7"
    local target_dir="${BIN_DIR}/${dest}"

    # Parse flags
    local allow_text=false make_exec=false
    [[ "$flags" == *allow-text* ]] && allow_text=true
    [[ "$flags" == *executable* ]] && make_exec=true

    case "$type" in
        github-release)
            ui_info "${name}  (${repo} @ ${tag},  mode=${mode})"

            local json
            json="$(fetch_release "$repo" "$tag")" || { ERRORS=$((ERRORS + 1)); return; }

            if [[ "$mode" == "all-assets" ]]; then
                # Download every release asset into dest/.
                # all-assets implies allow-text - checksums and signatures are expected.
                local asset_allow_text=true

                mkdir -p "$target_dir"

                local asset_count
                asset_count="$(printf '%s' "$json" | jq '.assets | length')"
                echo "    [INFO] ${asset_count} asset(s) in release"

                local -a lines
                mapfile -t lines < <(printf '%s' "$json" | jq -r \
                    '.assets[] | [.name, .browser_download_url, (.size | tostring)] | @tsv')

                if [[ ${#lines[@]} -eq 0 ]]; then
                    echo "    [FAIL] Release has no downloadable assets"
                    ERRORS=$((ERRORS + 1))
                    return
                fi

                for line in "${lines[@]}"; do
                    [[ -z "$line" ]] && continue
                    local a_name a_url a_size
                    IFS=$'\t' read -r a_name a_url a_size <<< "$line"
                    local a_dest="${target_dir}/${a_name}"

                    # Idempotency: skip if file exists with matching size.
                    if [[ -f "$a_dest" ]]; then
                        local existing
                        existing="$(file_size "$a_dest")"
                        if [[ "$existing" == "$a_size" ]]; then
                            echo "    [INFO] ${a_name}  (${a_size} B)  exists"
                            SKIPPED=$((SKIPPED + 1))
                            continue
                        fi
                        echo "    [INFO] ${a_name}  size differs - re-downloading"
                        rm -f "$a_dest"
                    fi

                    echo "    [PASS] ${a_name}  (${a_size} B)"

                    if $DRY_RUN; then
                        echo "        -> ${a_dest}"
                        continue
                    fi

                    if download_one "$a_url" "$a_dest" "$asset_allow_text" "$make_exec"; then
                        SYNCED=$((SYNCED + 1))
                    else
                        ERRORS=$((ERRORS + 1))
                    fi
                done

            else
                # mode = exact asset filename - download that single file.
                mkdir -p "$target_dir"

                local a_info
                a_info="$(printf '%s' "$json" | jq -r --arg pat "$mode" \
                    '.assets[] | select(.name == $pat) | [.name, .browser_download_url, (.size | tostring)] | @tsv')"

                if [[ -z "$a_info" ]]; then
                    echo "    [FAIL] Asset not found: ${mode}"
                    echo "       Available assets:"
                    printf '%s' "$json" | jq -r '.assets[].name' | sed 's/^/         /'
                    ERRORS=$((ERRORS + 1))
                    return
                fi

                local a_name a_url a_size
                IFS=$'\t' read -r a_name a_url a_size <<< "$a_info"
                local a_dest="${target_dir}/${a_name}"

                if [[ -f "$a_dest" ]]; then
                    local existing
                    existing="$(file_size "$a_dest")"
                    if [[ "$existing" == "$a_size" ]]; then
                        echo "    [INFO] ${a_name}  (${a_size} B)  exists"
                        SKIPPED=$((SKIPPED + 1))
                        return
                    fi
                    echo "    [INFO] ${a_name}  size differs - re-downloading"
                    rm -f "$a_dest"
                fi

                echo "    [PASS] ${a_name}  (${a_size} B)"

                if $DRY_RUN; then
                    echo "        -> ${a_dest}"
                    return
                fi

                if download_one "$a_url" "$a_dest" "$allow_text" "$make_exec"; then
                    SYNCED=$((SYNCED + 1))
                else
                    ERRORS=$((ERRORS + 1))
                fi
            fi
            ;;

        *)
            echo "[FAIL] Unknown source type '${type}' for entry '${name}'" >&2
            ERRORS=$((ERRORS + 1))
            ;;
    esac
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    if [[ ! -f "$MANIFEST" ]]; then
        ui_fail "Manifest not found: ${MANIFEST}"
        ui_note "Expected at: manifests/binaries.tsv"
        ui_note "Is this the hecate-bootstrap repo root?"
        exit 1
    fi

    $DRY_RUN || mkdir -p "$BIN_DIR"

    ui_banner "Hecate" "Binary sync"
    echo ""
    ui_info "Syncing pinned binaries → ${BIN_DIR}"
    $DRY_RUN && ui_info "DRY-RUN — no files will be written"
    echo ""

    local matched=0

    while IFS=$'\t' read -r f_name f_type f_repo f_tag f_mode f_dest f_flags || [[ -n "${f_name:-}" ]]; do
        # Skip blanks, comments, header row.
        [[ -z "$f_name" || "$f_name" =~ ^[[:space:]]*# || "$f_name" == "name" ]] && continue

        f_flags="${f_flags:--}"

        # Apply --name filter.
        if [[ -n "$FILTER" && "$f_name" != "$FILTER" ]]; then
            continue
        fi

        matched=$((matched + 1))
        process_entry "$f_name" "$f_type" "$f_repo" "$f_tag" "$f_mode" "$f_dest" "$f_flags"
        echo ""
    done < "$MANIFEST"

    # ── Summary ────────────────────────────────────────────────────────────────
    if [[ -n "$FILTER" && "$matched" -eq 0 ]]; then
        ui_fail "No manifest entry named '${FILTER}'"
        exit 1
    fi

    ui_summary_line
    ui_kv "Entries" "$matched"
    ui_kv "Downloaded" "$SYNCED"
    ui_kv "Skipped" "$SKIPPED"
    ui_kv "Errors" "$ERRORS"

    if [[ "$ERRORS" -gt 0 ]]; then
        echo ""
        echo "  Result: Sync completed with ${ERRORS} error(s) — review output above."

        ui_next_block \
            "labctl sync --name <entry>    Retry a specific entry" \
            "labctl sync --dry-run         Preview what would be fetched"
        exit 1
    fi

    echo ""
    echo "  Result: Sync complete."
    echo ""
}

main "$@"
