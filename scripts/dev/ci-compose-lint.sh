#!/usr/bin/env bash
# scripts/dev/ci-compose-lint.sh — Validate Docker Compose files parse correctly.
#
# Runs `docker-compose config` on each compose file combination to catch
# YAML errors, duplicate keys, invalid references, and stacking issues.
#
# Requires docker-compose (legacy) or docker compose (plugin) on PATH.
# Does NOT require a running Docker daemon — config validation is offline.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_DIR="$REPO/compose"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }

# Detect compose command
COMPOSE_CMD=""
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "✗ Neither 'docker compose' nor 'docker-compose' found"
    exit 1
fi
echo "Using: $COMPOSE_CMD"
echo ""

echo "── Compose config validation ──"

# Test 1: Base file alone
echo ""
echo "Base config:"
if $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" config -q 2>/dev/null; then
    pass "docker-compose.yml (base)"
else
    fail "docker-compose.yml (base)"
    $COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" config 2>&1 | head -5 | sed 's/^/    /'
fi

# Test 2: Base + GPU overlay
echo ""
echo "GPU overlay:"
if $COMPOSE_CMD \
    -f "$COMPOSE_DIR/docker-compose.yml" \
    -f "$COMPOSE_DIR/docker-compose.gpu.yml" \
    config -q 2>/dev/null; then
    pass "base + gpu overlay"
else
    fail "base + gpu overlay"
fi

# Test 3: Base + hostnet overlay
echo ""
echo "Hostnet overlay:"
if $COMPOSE_CMD \
    -f "$COMPOSE_DIR/docker-compose.yml" \
    -f "$COMPOSE_DIR/docker-compose.hostnet.yml" \
    config -q 2>/dev/null; then
    pass "base + hostnet overlay"
else
    fail "base + hostnet overlay"
fi

# Test 4: All overlays stacked
echo ""
echo "All overlays:"
if $COMPOSE_CMD \
    -f "$COMPOSE_DIR/docker-compose.yml" \
    -f "$COMPOSE_DIR/docker-compose.gpu.yml" \
    -f "$COMPOSE_DIR/docker-compose.hostnet.yml" \
    config -q 2>/dev/null; then
    pass "base + gpu + hostnet"
else
    fail "base + gpu + hostnet"
fi

# Test 5: Services present in base config
echo ""
echo "Service inventory:"
services="$($COMPOSE_CMD -f "$COMPOSE_DIR/docker-compose.yml" config --services 2>/dev/null)"
for svc in kali-main builder; do
    if echo "$services" | grep -qx "$svc"; then
        pass "service: $svc"
    else
        fail "service: $svc (missing)"
    fi
done

# Summary
echo ""
echo "── ${PASS} passed, ${FAIL} failed ──"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
