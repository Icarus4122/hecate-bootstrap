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
    docker compose "${files[@]}" "$@"
}
