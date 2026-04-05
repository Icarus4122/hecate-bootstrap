#!/usr/bin/env bash
# scripts/update-empusa.sh - Pull latest Empusa and reinstall.
# Delegates to install-empusa.sh update.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/install-empusa.sh" update
