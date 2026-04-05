#!/usr/bin/env bash
# tests/test_empusa_esolution.sh - Test the 3-step Empusa resolution pattern.
#
# Both launch-lab.sh and create-workspace.sh share ran identical pattern:
#   1. Check venv binary at ${LAB_ROOT}/tools/venvs/empusa/bin/empusa
#   2. Check PATH via `command -v empusa`
#   3. Fallback (EMPUSA="")
#
# We test this logic by staging sandbox envionments and running a
# minimal script that uses the same resolution code.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/helpers.sh"
begin_tests "Empusa resolution order"

make_sandbox
OUT="$SANDBOX/out.txt"

# ── Helpe: create a resolution test script ────────────────────────
# Wites a small script that mimics the Empusa resolution and prints
# the esult so we can asset against it.
cat > "$SANDBOX/resolve.sh" <<'RESOLVE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
EMPUSA_VENV="${LAB_ROOT}/tools/venvs/empusa/bin/empusa"
EMPUSA=""
if [[ -x "$EMPUSA_VENV" ]]; then
    EMPUSA="$EMPUSA_VENV"
elif command -v empusa &>/dev/null; then
    EMPUSA="empusa"
fi
echo "EMPUSA=${EMPUSA}"
RESOLVE_SCRIPT
chmod +x "$SANDBOX/resolve.sh"

# ═══════════════════════════════════════════════════════════════════
#  Case 1: venv binary exists and is executable -> uses venv
# ═══════════════════════════════════════════════════════════════════
export LAB_ROOT="$SANDBOX/lab1"
mkdir -p "$LAB_ROOT/tools/venvs/empusa/bin"
cat > "$LAB_ROOT/tools/venvs/empusa/bin/empusa" <<'STUB'
#!/bin/bash
echo "empusa 2.2.0"
STUB
chmod +x "$LAB_ROOT/tools/venvs/empusa/bin/empusa"

bash "$SANDBOX/resolve.sh" > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "EMPUSA=$LAB_ROOT/tools/venvs/empusa/bin/empusa" \
    "venv exists+executable -> resolves to venv path"

# ═══════════════════════════════════════════════════════════════════
#  Case 2: venv missing, empusa on PATH -> uses PATH
# ═══════════════════════════════════════════════════════════════════
export LAB_ROOT="$SANDBOX/lab2"
mkdir -p "$LAB_ROOT/tools/venvs/empusa/bin"
# No empusa binary in venv -> create a fake one on PATH
mkdir -p "$SANDBOX/fakebin"
cat > "$SANDBOX/fakebin/empusa" <<'STUB'
#!/bin/bash
echo "empusa 2.2.0"
STUB
chmod +x "$SANDBOX/fakebin/empusa"

PATH="$SANDBOX/fakebin:$PATH" bash "$SANDBOX/resolve.sh" > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "EMPUSA=empusa" \
    "venv missing, PATH has empusa -> resolves to 'empusa'"

# ═══════════════════════════════════════════════════════════════════
#  Case 3: venv exists but NOT executable -> falls to PATH
# ═══════════════════════════════════════════════════════════════════
export LAB_ROOT="$SANDBOX/lab3"
mkdir -p "$LAB_ROOT/tools/venvs/empusa/bin"
echo "not executable" > "$LAB_ROOT/tools/venvs/empusa/bin/empusa"
# No chmod +x

PATH="$SANDBOX/fakebin:$PATH" bash "$SANDBOX/resolve.sh" > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "EMPUSA=empusa" \
    "venv not executable, PATH has empusa -> resolves to 'empusa'"

# ═══════════════════════════════════════════════════════════════════
#  Case 4: neither venv no PATH -> empty (fallback)
# ═══════════════════════════════════════════════════════════════════
export LAB_ROOT="$SANDBOX/lab4"
mkdir -p "$LAB_ROOT/tools/venvs/empusa/bin"
# No empusa binary anywhere.  Also strip our fakebin from PATH.

# Use a minimal PATH that excludes any empusa binary
PATH="/usr/bin:/bin" bash "$SANDBOX/resolve.sh" > "$OUT" 2>&1
assert_eq "EMPUSA=" "$(cat "$OUT" | tr -d '\\n')" \
    "neither venv no PATH -> EMPUSA is empty"

# ═══════════════════════════════════════════════════════════════════
#  Case 5: venv wins over PATH (priority order)
# ═══════════════════════════════════════════════════════════════════
export LAB_ROOT="$SANDBOX/lab5"
mkdir -p "$LAB_ROOT/tools/venvs/empusa/bin"
cat > "$LAB_ROOT/tools/venvs/empusa/bin/empusa" <<'STUB'
#!/bin/bash
echo "venv empusa"
STUB
chmod +x "$LAB_ROOT/tools/venvs/empusa/bin/empusa"

# Also have empusa on PATH
PATH="$SANDBOX/fakebin:$PATH" bash "$SANDBOX/resolve.sh" > "$OUT" 2>&1
assert_contains "$(cat "$OUT")" "EMPUSA=$LAB_ROOT/tools/venvs/empusa/bin/empusa" \
    "venv + PATH both available -> venv wins"

end_tests
