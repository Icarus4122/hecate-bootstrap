# Platform Validation Suite (End-to-End)

Full-stack validation of the hecate-bootstrap + empusa platform.
Two-layer architecture: **stages** (subsystem validation) + **scenarios**
(named end-to-end operator journeys with fault injection and recovery).

Designed to run on a fresh Ubuntu 24.04 host or after any platform update.

## Quick Start

```bash
# Full validation — stages then scenarios (requires root)
sudo bash tests/e2e/run-validation.sh

# Stages only (no scenarios)
bash tests/e2e/run-validation.sh --stages-only

# Scenarios only (stages assumed passing)
bash tests/e2e/run-validation.sh --scenarios-only

# Single stage
bash tests/e2e/run-validation.sh --stage 3

# Single scenario by name
bash tests/e2e/run-validation.sh --scenario fresh-bootstrap

# Skip bootstrap (host already provisioned)
bash tests/e2e/run-validation.sh --skip-bootstrap

# Dry run (show what would be tested)
bash tests/e2e/run-validation.sh --dry-run
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Layer 2: Scenarios — Operator Journeys          │
│  ┌───────────────┐  ┌───────────────┐            │
│  │ sc_01 Fresh   │  │ sc_02 Research│  ...10 total│
│  │ Bootstrap     │  │ Workflow      │            │
│  └───────┬───────┘  └───────┬───────┘            │
│          │ require_stage()  │ require_docker()   │
├──────────┼──────────────────┼────────────────────┤
│  Layer 1: Stages — Subsystem Validation          │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐     │
│  │ S0 │ │ S1 │ │ S2 │ │ S3 │ │ S4 │ │ S5 │ ... │
│  │Host│ │Boot│ │Vfy │ │Bld │ │Run │ │Emp │     │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘     │
├──────────────────────────────────────────────────┤
│  Harness: e2e-helpers.sh                         │
│  TAP output · fault injection · docker inspect   │
│  state capture · output quality · heading order  │
└──────────────────────────────────────────────────┘
```

## Layer 1: Stages

| # | Name | Root? | Docker? | Network? | Description |
|---|------|-------|---------|----------|-------------|
| 0 | Host Prerequisites | No | No | No | OS, commands, kernel |
| 1 | Bootstrap | **Yes** | No | Yes (apt) | Full host provisioning |
| 2 | Verify & Sync | No | Yes | Yes (API) | Pre-flight + binary sync |
| 3 | Build & Compose | No | Yes | Yes (pull) | Image build, overlay stacking, docker inspect mounts, dual compose |
| 4 | Runtime Lifecycle | No | Yes | No | up/down/shell/status, idempotent reruns, re-entry, network inspect |
| 5 | Empusa | No | No | No | CLI, workspace, plugins, bus, perms, cycles, cascades, traversal, isolation |
| 6 | Templates | No | No | No | Seed, heading order, markdown structure, destination paths, profile fit, docs consistency |
| 7 | UX & Output | No | No | No | labctl output, banners, markers, help, errors |

## Layer 2: Scenarios

| # | Name | Root? | Docker? | Description |
|---|------|-------|---------|-------------|
| 1 | fresh-bootstrap | **Yes** | Yes | Zero-to-running-lab on fresh host |
| 2 | research-workflow | **Yes** | Yes | Create, work, re-enter, teardown research workspace |
| 3 | htb-workflow | **Yes** | Yes | Full HTB engagement: scaffold, simulate, restart, second target |
| 4 | builder-workflow | **Yes** | Yes | Builder sidecar compile → cross-container artifact access |
| 5 | persistence | **Yes** | Yes | Data survival across restart, recreate, prune |
| 6 | overlay-matrix | **Yes** | Yes | All overlay flag combinations (GPU, hostnet, builder) |
| 7 | partial-failure | **Yes** | Yes | Fault injection: missing .env, killed containers, corrupt manifests |
| 8 | plugin-failures | No | No | Plugin graph failures: deps, cycles, exceptions, refresh |
| 9 | hook-event-contracts | No | No | All 17 events, payload contracts, legacy hooks, subscriber isolation |
| 10 | template-workflow | No | No | Template seed through operator usage, per-profile, idempotency |

## Report

Results written to `tests/e2e/reports/validation-<timestamp>.txt`

Stage and scenario results are reported separately: stages first, then
scenarios. The final summary shows pass/fail/skip counts for both layers.

## Files

```
tests/e2e/
├── README.md                          # This file
├── e2e-helpers.sh                     # Extended harness (stages, scenarios, assertions)
├── run-validation.sh                  # Two-layer orchestrator
├── stage_0_host.sh                    # Host prerequisite checks
├── stage_1_bootstrap.sh               # Bootstrap validation
├── stage_2_verify.sh                  # Verify + sync validation
├── stage_3_build.sh                   # Build + compose + docker inspect
├── stage_4_runtime.sh                 # Container lifecycle + idempotency
├── stage_5_empusa.sh                  # Empusa subsystem + failure modes
├── stage_6_templates.sh               # Template structure + profile fit
├── stage_7_ux.sh                      # UX output validation
├── reports/                           # Generated reports
└── scenarios/
    ├── sc_01_fresh_bootstrap.sh       # Day-one operator journey
    ├── sc_02_research_workflow.sh      # Research topic lifecycle
    ├── sc_03_htb_workflow.sh           # Full HTB engagement
    ├── sc_04_builder_workflow.sh       # Builder sidecar workflow
    ├── sc_05_persistence.sh           # Data persistence
    ├── sc_06_overlay_matrix.sh        # Overlay flag combinations
    ├── sc_07_partial_failure.sh       # Fault injection + recovery
    ├── sc_08_plugin_failures.sh       # Plugin graph failures
    ├── sc_09_hook_event_contracts.sh  # Event/hook contracts
    └── sc_10_template_workflow.sh     # Template-to-workflow
```

## Helpers Reference

### Stage Primitives
- `begin_stage N "Name"` / `end_stage` — bracket stage execution
- `section "title"` — group related assertions
- `assert_*` — TAP assertions (eq, contains, file_exists, etc.)

### Scenario Primitives
- `begin_scenario "name" "desc"` / `end_scenario` — bracket scenario execution
- `require_stage N` / `require_root` / `require_docker` / `require_empusa` — gate checks
- `skip_scenario "name" "reason"` — skip with explanation

### Fault Injection
- `inject_fault "rename_file" PATH` — rename file to .bak
- `inject_fault "break_manifest" PATH` — corrupt JSON manifest
- `inject_fault "stop_container" NAME` — docker stop
- `inject_fault "break_permission" PATH` — chmod 000
- `restore_fault TYPE PATH` — reverse the injection

### Docker Assertions
- `assert_docker_mount CONTAINER SRC DST MODE LABEL` — verify bind mount via docker inspect
- `assert_docker_network CONTAINER MODE LABEL` — verify network mode
- `assert_docker_env CONTAINER VAR VALUE LABEL` — verify environment variable
- `assert_docker_restart CONTAINER POLICY LABEL` — verify restart policy
- `assert_dual_compose LABEL ARGS...` — verify both docker compose variants succeed

### State Management
- `capture_state TAG` — fingerprint directories for later comparison
- `assert_state_unchanged TAG` / `assert_state_changed TAG` — compare against capture
- `assert_idempotent LABEL CMD...` — run twice, assert same exit + no errors
- `assert_reentry LABEL CMD...` — run against existing state, assert clean behavior

### Output Quality
- `assert_output_quality TEXT LABEL +REQUIRED -FORBIDDEN...` — check output patterns
- `assert_structured_output TEXT LABEL MARKER...` — verify section markers
- `assert_heading_order FILE LABEL H1 H2 H3...` — verify markdown heading sequence
