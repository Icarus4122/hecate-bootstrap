#!/usr/bin/env bash
# tests/e2e/run-validation.sh - Orchestrate staged + scenario platform validation.
#
# Usage:
#   sudo bash tests/e2e/run-validation.sh               # Full run (stages + scenarios)
#   bash tests/e2e/run-validation.sh --skip-bootstrap
#   bash tests/e2e/run-validation.sh --stage 5           # Run single stage
#   bash tests/e2e/run-validation.sh --from 3            # Start from stage 3
#   bash tests/e2e/run-validation.sh --stages-only       # No scenarios
#   bash tests/e2e/run-validation.sh --scenarios-only    # No stages (requires prior stage run)
#   bash tests/e2e/run-validation.sh --scenario NAME     # Run single scenario
#   bash tests/e2e/run-validation.sh --dry-run           # Show plan, don't execute
#   bash tests/e2e/run-validation.sh --stop-on-fail      # Halt on first failure
set -uo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$E2E_DIR/e2e-helpers.sh"

# ── Parse arguments ───────────────────────────────────────────────
OPT_SKIP_BOOTSTRAP=0
OPT_SINGLE_STAGE=""
OPT_FROM_STAGE=0
OPT_DRY_RUN=0
OPT_STOP_ON_FAIL=0
OPT_STAGES_ONLY=0
OPT_SCENARIOS_ONLY=0
OPT_SINGLE_SCENARIO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-bootstrap)  OPT_SKIP_BOOTSTRAP=1; shift ;;
        --stage)           OPT_SINGLE_STAGE="$2"; shift 2 ;;
        --from)            OPT_FROM_STAGE="$2"; shift 2 ;;
        --dry-run)         OPT_DRY_RUN=1; shift ;;
        --stop-on-fail)    OPT_STOP_ON_FAIL=1; shift ;;
        --stages-only)     OPT_STAGES_ONLY=1; shift ;;
        --scenarios-only)  OPT_SCENARIOS_ONLY=1; shift ;;
        --scenario)        OPT_SINGLE_SCENARIO="$2"; shift 2 ;;
        *)
            echo "Unknown flag: $1" >&2
            echo "Usage: $0 [--skip-bootstrap] [--stage N] [--from N] [--stages-only] [--scenarios-only] [--scenario NAME] [--dry-run] [--stop-on-fail]" >&2
            exit 1
            ;;
    esac
done

export LAB_ROOT="${LAB_ROOT:-/opt/lab}"

# ── Stage definitions ─────────────────────────────────────────────
STAGE_FILES=(
    "stage_0_host.sh"
    "stage_1_bootstrap.sh"
    "stage_2_verify.sh"
    "stage_3_build.sh"
    "stage_4_runtime.sh"
    "stage_5_empusa.sh"
    "stage_6_templates.sh"
    "stage_7_ux.sh"
)
STAGE_NAMES=(
    "Host Prerequisites"
    "Bootstrap"
    "Verify & Sync"
    "Build & Compose"
    "Runtime Lifecycle"
    "Empusa Subsystem"
    "Templates"
    "UX & Output"
)
STAGE_NEEDS_ROOT=(0 1 0 0 0 0 0 0)
STAGE_NEEDS_DOCKER=(0 0 1 1 1 0 0 0)

# ── Scenario definitions ──────────────────────────────────────────
SCENARIO_DIR="$E2E_DIR/scenarios"
SCENARIO_FILES=(
    "sc_01_fresh_bootstrap.sh"
    "sc_02_research_workflow.sh"
    "sc_03_htb_workflow.sh"
    "sc_04_builder_workflow.sh"
    "sc_05_persistence.sh"
    "sc_06_overlay_matrix.sh"
    "sc_07_partial_failure.sh"
    "sc_08_plugin_failures.sh"
    "sc_09_hook_event_contracts.sh"
    "sc_10_template_workflow.sh"
)
SCENARIO_NAMES=(
    "fresh-bootstrap"
    "research-workflow"
    "htb-workflow"
    "builder-workflow"
    "persistence"
    "overlay-matrix"
    "partial-failure"
    "plugin-failures"
    "hook-event-contracts"
    "template-workflow"
)
SCENARIO_NEEDS_ROOT=(1 1 1 1 1 1 1 0 0 0)
SCENARIO_NEEDS_DOCKER=(1 1 1 1 1 1 1 0 0 0)

# ── Dry run ───────────────────────────────────────────────────────
if [[ $OPT_DRY_RUN -eq 1 ]]; then
    echo ""
    echo "Platform Validation — Dry Run"
    echo ""
    if [[ $OPT_SCENARIOS_ONLY -eq 0 ]]; then
        echo "  STAGES"
        for i in "${!STAGE_FILES[@]}"; do
            local_skip=""
            [[ $i -eq 1 && $OPT_SKIP_BOOTSTRAP -eq 1 ]] && local_skip=" (SKIP: --skip-bootstrap)"
            [[ -n "$OPT_SINGLE_STAGE" && "$i" != "$OPT_SINGLE_STAGE" ]] && local_skip=" (SKIP: --stage $OPT_SINGLE_STAGE)"
            [[ $i -lt $OPT_FROM_STAGE ]] && local_skip=" (SKIP: --from $OPT_FROM_STAGE)"
            root=""
            [[ ${STAGE_NEEDS_ROOT[$i]} -eq 1 ]] && root=" [root]"
            docker=""
            [[ ${STAGE_NEEDS_DOCKER[$i]} -eq 1 ]] && docker=" [docker]"
            echo "    Stage $i: ${STAGE_NAMES[$i]}${root}${docker}${local_skip}"
        done
    fi
    if [[ $OPT_STAGES_ONLY -eq 0 ]]; then
        echo ""
        echo "  SCENARIOS"
        for i in "${!SCENARIO_FILES[@]}"; do
            local_skip=""
            [[ -n "$OPT_SINGLE_SCENARIO" && "${SCENARIO_NAMES[$i]}" != "$OPT_SINGLE_SCENARIO" ]] && \
                local_skip=" (SKIP: --scenario $OPT_SINGLE_SCENARIO)"
            root=""
            [[ ${SCENARIO_NEEDS_ROOT[$i]} -eq 1 ]] && root=" [root]"
            docker=""
            [[ ${SCENARIO_NEEDS_DOCKER[$i]} -eq 1 ]] && docker=" [docker]"
            echo "    Scenario: ${SCENARIO_NAMES[$i]}${root}${docker}${local_skip}"
        done
    fi
    echo ""
    exit 0
fi

# ── Initialize report ─────────────────────────────────────────────
init_report

# ── Run stages ────────────────────────────────────────────────────
if [[ $OPT_SCENARIOS_ONLY -eq 0 ]]; then
for i in "${!STAGE_FILES[@]}"; do
    stage_file="${E2E_DIR}/${STAGE_FILES[$i]}"
    stage_name="${STAGE_NAMES[$i]}"

    # Skip logic
    if [[ -n "$OPT_SINGLE_STAGE" && "$i" != "$OPT_SINGLE_STAGE" ]]; then
        skip_stage "$i" "$stage_name" "not selected (--stage $OPT_SINGLE_STAGE)"
        continue
    fi
    if [[ $i -lt $OPT_FROM_STAGE ]]; then
        skip_stage "$i" "$stage_name" "below --from $OPT_FROM_STAGE"
        continue
    fi
    if [[ $i -eq 1 && $OPT_SKIP_BOOTSTRAP -eq 1 ]]; then
        skip_stage "$i" "$stage_name" "--skip-bootstrap"
        continue
    fi

    # Gate checks
    if [[ ${STAGE_NEEDS_ROOT[$i]} -eq 1 ]] && ! is_root; then
        skip_stage "$i" "$stage_name" "requires root (run with sudo)"
        continue
    fi
    if [[ ${STAGE_NEEDS_DOCKER[$i]} -eq 1 ]] && ! has_docker; then
        skip_stage "$i" "$stage_name" "Docker not available"
        continue
    fi

    # Existence check
    if [[ ! -f "$stage_file" ]]; then
        skip_stage "$i" "$stage_name" "file missing: ${STAGE_FILES[$i]}"
        continue
    fi

    # Execute stage
    stage_rc=0
    source "$stage_file" || stage_rc=$?

    if [[ $OPT_STOP_ON_FAIL -eq 1 && $stage_rc -ne 0 ]]; then
        echo "" | tee -a "$E2E_REPORT_FILE"
        echo "# STOPPED: Stage $i failed and --stop-on-fail is set" | tee -a "$E2E_REPORT_FILE"
        print_final_report
        exit 1
    fi
done
fi  # end stages

# ── Run scenarios ─────────────────────────────────────────────────
if [[ $OPT_STAGES_ONLY -eq 0 ]]; then
{
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  SCENARIO LAYER"
    echo "══════════════════════════════════════════════════════════════"
} | tee -a "$E2E_REPORT_FILE"

for i in "${!SCENARIO_FILES[@]}"; do
    scenario_file="${SCENARIO_DIR}/${SCENARIO_FILES[$i]}"
    scenario_name="${SCENARIO_NAMES[$i]}"

    # Single scenario filter
    if [[ -n "$OPT_SINGLE_SCENARIO" && "$scenario_name" != "$OPT_SINGLE_SCENARIO" ]]; then
        skip_scenario "$scenario_name" "not selected (--scenario $OPT_SINGLE_SCENARIO)"
        continue
    fi

    # Gate checks
    if [[ ${SCENARIO_NEEDS_ROOT[$i]} -eq 1 ]] && ! is_root; then
        skip_scenario "$scenario_name" "requires root"
        continue
    fi
    if [[ ${SCENARIO_NEEDS_DOCKER[$i]} -eq 1 ]] && ! has_docker; then
        skip_scenario "$scenario_name" "Docker not available"
        continue
    fi

    # Existence check
    if [[ ! -f "$scenario_file" ]]; then
        skip_scenario "$scenario_name" "file missing: ${SCENARIO_FILES[$i]}"
        continue
    fi

    # Execute scenario
    scenario_rc=0
    source "$scenario_file" || scenario_rc=$?

    if [[ $OPT_STOP_ON_FAIL -eq 1 && $scenario_rc -ne 0 ]]; then
        echo "" | tee -a "$E2E_REPORT_FILE"
        echo "# STOPPED: Scenario '$scenario_name' failed and --stop-on-fail is set" | tee -a "$E2E_REPORT_FILE"
        print_final_report
        exit 1
    fi
done
fi  # end scenarios

# ── Final report ──────────────────────────────────────────────────
print_final_report

if [[ $E2E_STAGES_FAILED -gt 0 || $E2E_SCENARIOS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
