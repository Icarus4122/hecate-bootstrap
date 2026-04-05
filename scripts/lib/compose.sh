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
        echo "Error: neither 'docker compose' nor 'docker-compose' found." >&2
        echo "Please install Docker Compose and ensure it's on your PATH." >&2
        return 1
    fi
    docker compose "${files[@]}" "$@"
}
