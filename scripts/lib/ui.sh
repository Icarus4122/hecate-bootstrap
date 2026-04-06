#!/usr/bin/env bash
# scripts/lib/ui.sh - Shared terminal UI primitives for Hecate.
#
# Implements the canonical vocabulary from docs/dev/terminal-ui-style-guide.md:
#   [PASS]  [WARN]  [FAIL]  [INFO]  [ACTION]
#
# Layout primitives:
#   ui_banner       - box banner at command entry
#   ui_section      - section header (── ... ──)
#   ui_pass         - [PASS]  success / valid / healthy
#   ui_warn         - [WARN]  usable but caution
#   ui_fail         - [FAIL]  blocked / must fix
#   ui_info         - [INFO]  neutral context
#   ui_action       - [ACTION] next-step / recommended command
#   ui_fix          - indented fix line under a fail/warn
#   ui_note         - indented explanation line
#   ui_kv           - aligned key-value row
#   ui_summary_line - header for summary block
#   ui_next_block   - [ACTION] Next block with commands
#
# Color support:
#   Respects NO_COLOR env var (https://no-color.org/).
#   Hecate accent: cyan.

# Guard against double-sourcing.
[[ -n "${_UI_SH_LOADED:-}" ]] && return 0
_UI_SH_LOADED=1

# ── ANSI color codes ──────────────────────────────────────────────
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    _C_RESET="" _C_BOLD="" _C_DIM=""
    _C_RED="" _C_GREEN="" _C_YELLOW="" _C_CYAN="" _C_WHITE=""
else
    _C_RESET=$'\033[0m'  _C_BOLD=$'\033[1m'  _C_DIM=$'\033[2m'
    _C_RED=$'\033[1;31m' _C_GREEN=$'\033[1;32m' _C_YELLOW=$'\033[1;33m'
    _C_CYAN=$'\033[1;36m' _C_WHITE=$'\033[1;37m'
fi

# ── Status markers ─────────────────────────────────────────────────

ui_pass() {
    printf "  ${_C_GREEN}[PASS]${_C_RESET}  %s\n" "$*"
}

ui_warn() {
    printf "  ${_C_YELLOW}[WARN]${_C_RESET}  %s\n" "$*"
}

ui_fail() {
    printf "  ${_C_RED}[FAIL]${_C_RESET}  %s\n" "$*" >&2
}

ui_info() {
    printf "  ${_C_WHITE}[INFO]${_C_RESET}  %s\n" "$*"
}

ui_action() {
    printf "  ${_C_CYAN}[ACTION]${_C_RESET}  %s\n" "$*"
}

# ── Indented detail lines ──────────────────────────────────────────

ui_fix() {
    printf "          Fix: %s\n" "$*"
}

ui_note() {
    printf "          %s\n" "$*"
}

# ── Layout primitives ──────────────────────────────────────────────

ui_banner() {
    # Usage: ui_banner "Hecate" "Host verification" ["2026-04-05"]
    local product="${1:-Hecate}" surface="${2:-}" date_str="${3:-$(date +%F)}"
    local title="${product}"
    [[ -n "$surface" ]] && title="${product} · ${surface}"
    [[ -n "$date_str" ]] && title="${title} · ${date_str}"
    local width=60
    local pad=$(( width - ${#title} - 4 ))
    (( pad < 1 )) && pad=1
    echo "${_C_CYAN}╔$(printf '═%.0s' $(seq 1 $width))╗${_C_RESET}"
    printf "${_C_CYAN}║${_C_RESET}  %-*s${_C_CYAN}║${_C_RESET}\n" "$((width - 2))" "$title"
    echo "${_C_CYAN}╚$(printf '═%.0s' $(seq 1 $width))╝${_C_RESET}"
}

ui_section() {
    # Usage: ui_section "Docker health"
    echo ""
    echo "${_C_CYAN}──${_C_RESET} $1 ${_C_CYAN}──${_C_RESET}"
}

ui_kv() {
    # Usage: ui_kv "Label" "value"
    printf "  %-14s %s\n" "$1" "$2"
}

ui_summary_line() {
    echo ""
    echo "${_C_CYAN}──${_C_RESET} Summary ${_C_CYAN}──${_C_RESET}"
}

ui_next_block() {
    # Usage: ui_next_block "labctl shell" "labctl status" ...
    echo ""
    printf "  ${_C_CYAN}[ACTION]${_C_RESET} Next\n"
    for cmd in "$@"; do
        printf "      %s\n" "$cmd"
    done
    echo ""
}

ui_error_block() {
    # Usage: ui_error_block "what failed" "why it matters" "likely cause" "fix command"
    local what="${1:-}" why="${2:-}" cause="${3:-}" fix="${4:-}"
    echo "" >&2
    ui_fail "$what"
    [[ -n "$why" ]]   && ui_note "Why: $why" >&2
    [[ -n "$cause" ]] && ui_note "Cause: $cause" >&2
    [[ -n "$fix" ]]   && ui_fix "$fix" >&2
}
