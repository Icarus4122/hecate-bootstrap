#!/usr/bin/env bash
# scripts/lib/compose.sh - Shared Docker Compose file-stacking helper.
#
# Provides _compose() - assembles the -f chain from the base file plus
# any active overlays and forwards all arguments to `docker compose`.
#
# Requires:
#   REPO_DIR  - absolute path to the hecate-bootstrap repo root.
#
# Overlay env vars (all optional, default "0"):
#   LAB_GPU=1      - stack compose/docker-compose.gpu.yml
#   LAB_HOSTNET=1  - stack compose/docker-compose.hostnet.yml

_compose() {
    local files=("-f" "${REPO_DIR}/compose/docker-compose.yml")
    if [[ "${LAB_GPU:-0}" == "1" ]]; then
        files+=("-f" "${REPO_DIR}/compose/docker-compose.gpu.yml")
    fi
    if [[ "${LAB_HOSTNET:-0}" == "1" ]]; then
        files+=("-f" "${REPO_DIR}/compose/docker-compose.hostnet.yml")
    fi

    if docker compose version >/dev/null 2>&1; then
        docker compose "${files[@]}" "$@"
    elif command -v docker-compose &>/dev/null; then
        docker-compose "${files[@]}" "$@"
    else
        echo "[✗] Docker Compose is not installed." >&2
        echo "    Neither 'docker compose' (plugin) nor 'docker-compose' (standalone) was found." >&2
        echo "    Install the Compose plugin (recommended):" >&2
        echo "      sudo apt install docker-compose-plugin" >&2
        echo "" >&2
        echo "    Then verify:  docker compose version" >&2
        return 1
    fi
}
