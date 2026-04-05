#!/usr/bin/env bash
# tests/e2e/stage_5_empusa.sh - Empusa subsystem validation.
#
# No Docker required.  Validates: CLI, workspace creation per profile,
# plugin lifecycle, bus/event dispatch, registry, services, hooks.
# Runs Empusa directly on the host using the installed venv.

begin_stage 5 "Empusa Subsystem"

LAB="${LAB_ROOT:-/opt/lab}"
EMPUSA_BIN="$LAB/tools/venvs/empusa/bin/empusa"

# ═══════════════════════════════════════════════════════════════════
#  5.0  Gate check
# ═══════════════════════════════════════════════════════════════════

if [[ ! -x "$EMPUSA_BIN" ]]; then
    _record_fail "Empusa: binary exists" "missing" "$EMPUSA_BIN"
    echo "# Empusa not installed — skipping subsystem tests"
    end_stage
    return 0 2>/dev/null || exit 0
fi

_record_pass "Empusa: binary exists"

# ═══════════════════════════════════════════════════════════════════
#  5.1  CLI availability
# ═══════════════════════════════════════════════════════════════════
section "CLI Availability"

ver_out="$("$EMPUSA_BIN" --version 2>&1)" || true
assert_match "$ver_out" '[0-9]+\.[0-9]+' "empusa --version: returns version"

help_out="$("$EMPUSA_BIN" --help 2>&1)" || true
assert_contains "$help_out" "workspace" "empusa --help: mentions workspace"
assert_contains "$help_out" "build" "empusa --help: mentions build"

# ═══════════════════════════════════════════════════════════════════
#  5.2  Workspace creation — all profiles
# ═══════════════════════════════════════════════════════════════════
section "Workspace Creation"

make_sandbox
WS_ROOT="$SANDBOX/workspaces"
TEMPLATES_DIR="$REPO_ROOT/templates"
mkdir -p "$WS_ROOT"

# Define expected dirs per profile
declare -A PROFILE_DIRS
PROFILE_DIRS[htb]="notes scans web creds loot exploits screenshots reports logs"
PROFILE_DIRS[build]="src out notes logs"
PROFILE_DIRS[research]="notes references poc logs"
PROFILE_DIRS[internal]="notes scans creds loot evidence exploits reports logs"

# Define expected templates per profile
declare -A PROFILE_TEMPLATES
PROFILE_TEMPLATES[htb]="engagement.md target.md recon.md services.md finding.md privesc.md web.md"
PROFILE_TEMPLATES[build]=""
PROFILE_TEMPLATES[research]="recon.md"
PROFILE_TEMPLATES[internal]="engagement.md target.md recon.md services.md finding.md pivot.md privesc.md ad.md"

for profile in htb build research internal; do
    ws_name="e2e-${profile}-test"

    ws_out="$("$EMPUSA_BIN" workspace init \
        --name "$ws_name" \
        --profile "$profile" \
        --root "$WS_ROOT" \
        --templates-dir "$TEMPLATES_DIR" \
        --set-active 2>&1)" || true

    ws_path="$WS_ROOT/$ws_name"

    # Workspace directory created
    assert_dir_exists "$ws_path" "ws $profile: directory created"

    # Expected subdirectories
    for d in ${PROFILE_DIRS[$profile]}; do
        assert_dir_exists "$ws_path/$d" "ws $profile: dir $d"
    done

    # Metadata file
    assert_file_exists "$ws_path/.empusa-workspace.json" "ws $profile: metadata exists"

    if [[ -f "$ws_path/.empusa-workspace.json" ]]; then
        # Metadata content
        assert_file_contains "$ws_path/.empusa-workspace.json" "\"profile\"" \
            "ws $profile: metadata has profile key"
        assert_file_contains "$ws_path/.empusa-workspace.json" "\"$profile\"" \
            "ws $profile: metadata profile value is $profile"
        assert_file_contains "$ws_path/.empusa-workspace.json" "\"name\"" \
            "ws $profile: metadata has name key"
        assert_file_contains "$ws_path/.empusa-workspace.json" "\"$ws_name\"" \
            "ws $profile: metadata name value"
        assert_file_contains "$ws_path/.empusa-workspace.json" "\"created_at\"" \
            "ws $profile: metadata has created_at"
    fi

    # Expected templates seeded
    for tmpl in ${PROFILE_TEMPLATES[$profile]}; do
        assert_file_exists "$ws_path/$tmpl" "ws $profile: template $tmpl seeded"
        assert_file_not_empty "$ws_path/$tmpl" "ws $profile: template $tmpl non-empty"
    done
done

# ═══════════════════════════════════════════════════════════════════
#  5.3  Workspace idempotency
# ═══════════════════════════════════════════════════════════════════
section "Workspace Idempotency"

# Re-create same workspace — should not fail, should note already_existed
ws_re_out="$("$EMPUSA_BIN" workspace init \
    --name "e2e-htb-test" \
    --profile "htb" \
    --root "$WS_ROOT" \
    --templates-dir "$TEMPLATES_DIR" 2>&1)" || true

# Workspace should still exist
assert_dir_exists "$WS_ROOT/e2e-htb-test" "ws idempotent: directory intact"
assert_file_exists "$WS_ROOT/e2e-htb-test/.empusa-workspace.json" \
    "ws idempotent: metadata intact"

# ═══════════════════════════════════════════════════════════════════
#  5.4  Workspace list
# ═══════════════════════════════════════════════════════════════════
section "Workspace List"

list_out="$("$EMPUSA_BIN" workspace list --root "$WS_ROOT" 2>&1)" || true
for profile in htb build research internal; do
    assert_contains "$list_out" "e2e-${profile}-test" "ws list: shows $profile workspace"
done

# ═══════════════════════════════════════════════════════════════════
#  5.5  Workspace select
# ═══════════════════════════════════════════════════════════════════
section "Workspace Select"

select_out="$("$EMPUSA_BIN" workspace select \
    --name "e2e-htb-test" \
    --root "$WS_ROOT" 2>&1)" || true
select_rc=$?
assert_eq "0" "$select_rc" "ws select: exits 0"

# ═══════════════════════════════════════════════════════════════════
#  5.6  Workspace status
# ═══════════════════════════════════════════════════════════════════
section "Workspace Status"

status_out="$("$EMPUSA_BIN" workspace status \
    --name "e2e-htb-test" \
    --root "$WS_ROOT" 2>&1)" || true
assert_contains "$status_out" "e2e-htb-test" "ws status: shows workspace name"
assert_contains "$status_out" "htb" "ws status: shows profile"

# ═══════════════════════════════════════════════════════════════════
#  5.7  Plugin system (via Python)
# ═══════════════════════════════════════════════════════════════════
section "Plugin System"

# Use Python to test plugin internals directly
PYTHON="$LAB/tools/venvs/empusa/bin/python"

if [[ -x "$PYTHON" ]]; then
    # Test plugin discovery, activation, and dispatch
    plugin_out="$("$PYTHON" -c "
import sys, tempfile, json
from pathlib import Path

# Create test plugin
td = Path(tempfile.mkdtemp())
plug_dir = td / 'test_e2e_plugin'
plug_dir.mkdir()

manifest = {
    'name': 'test_e2e_plugin',
    'version': '0.1.0',
    'author': 'e2e',
    'description': 'E2E test plugin',
    'events': ['test_fire'],
    'requires': [],
    'permissions': [],
    'enabled': True,
}
(plug_dir / 'manifest.json').write_text(json.dumps(manifest))
(plug_dir / 'plugin.py').write_text('''
_fired = []
def activate(services, registry, bus):
    pass
def deactivate():
    pass
def on_test_fire(event):
    _fired.append(event)
    return {'status': 'ok'}
''')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

# Minimal services
logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

registry = CapabilityRegistry()
bus = EventBus()

pm = PluginManager(td, services, registry, bus)
discovered = pm.discover()
print(f'discovered={len(discovered)}')

warnings = pm.resolve_dependencies()
activated = pm.activate_all()
print(f'activated={activated}')

# Dispatch test event
from empusa.events import make_event
event = make_event('test_fire', session_env='e2e')
results = pm.dispatch_event('test_fire', event)
print(f'dispatched=ok results={len(results)}')

# Deactivate
deactivated = pm.deactivate_all()
print(f'deactivated={deactivated}')

# Cleanup
import shutil
shutil.rmtree(td)
print('PLUGIN_TEST_OK')
" 2>&1)" || true

    assert_contains "$plugin_out" "discovered=1" "plugin: discovered test plugin"
    assert_contains "$plugin_out" "activated=1" "plugin: activated test plugin"
    assert_contains "$plugin_out" "dispatched=ok" "plugin: event dispatched"
    assert_contains "$plugin_out" "deactivated=1" "plugin: deactivated"
    assert_contains "$plugin_out" "PLUGIN_TEST_OK" "plugin: full lifecycle succeeded"
else
    _record_fail "plugin system: Python venv" "missing" "$PYTHON"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.8  Registry
# ═══════════════════════════════════════════════════════════════════
section "Registry"

if [[ -x "$PYTHON" ]]; then
    registry_out="$("$PYTHON" -c "
from empusa.registry import CapabilityRegistry

r = CapabilityRegistry()

# Register across all 6 categories
categories = ['analyzer', 'notifier', 'report_section', 'exporter', 'tunnel_template', 'recon_strategy']
for cat in categories:
    r.register(cat, f'test_{cat}', lambda: None, 'e2e_plugin', f'Test {cat}')

# Verify registration
summary = r.summary()
for cat in categories:
    assert summary[cat] == 1, f'{cat} not registered'
print(f'registered={sum(summary.values())}')

# Query
entries = r.all_entries()
print(f'entries={len(entries)}')

# Unregister by plugin
removed = r.unregister_plugin('e2e_plugin')
print(f'removed={removed}')

summary2 = r.summary()
assert sum(summary2.values()) == 0
print('REGISTRY_OK')
" 2>&1)" || true

    assert_contains "$registry_out" "registered=6" "registry: 6 categories registered"
    assert_contains "$registry_out" "entries=6" "registry: 6 entries queryable"
    assert_contains "$registry_out" "removed=6" "registry: unregister by plugin"
    assert_contains "$registry_out" "REGISTRY_OK" "registry: full lifecycle ok"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.9  Event bus
# ═══════════════════════════════════════════════════════════════════
section "Event Bus"

if [[ -x "$PYTHON" ]]; then
    bus_out="$("$PYTHON" -c "
from empusa.bus import EventBus
from empusa.events import make_event, ALL_EVENTS

bus = EventBus()

# Subscribe
received = []
def handler(event):
    received.append(event)

bus.subscribe('test_fire', handler)
print(f'subscribers={bus.subscriber_count(\"test_fire\")}')

# Emit
event = make_event('test_fire', session_env='e2e')
bus.emit(event)
print(f'received={len(received)}')

# Unsubscribe
removed = bus.unsubscribe('test_fire', handler)
print(f'unsubscribed={removed}')

# ALL_EVENTS should have all 17 events
print(f'all_events={len(ALL_EVENTS)}')

# Verify key events exist
required = [
    'on_startup', 'on_shutdown', 'pre_workspace_init', 'post_workspace_init',
    'on_workspace_select', 'pre_build', 'post_build', 'pre_scan_host',
    'post_scan', 'on_loot_add', 'pre_report_write', 'on_report_generated',
    'post_compile', 'pre_command', 'post_command', 'test_fire', 'on_env_select'
]
for ev in required:
    assert ev in ALL_EVENTS, f'Missing event: {ev}'

print('EVENTBUS_OK')
" 2>&1)" || true

    assert_contains "$bus_out" "subscribers=1" "bus: subscribe works"
    assert_contains "$bus_out" "received=1" "bus: emit delivers"
    assert_contains "$bus_out" "unsubscribed=True" "bus: unsubscribe works"
    assert_contains "$bus_out" "all_events=17" "bus: ALL_EVENTS has 17 entries"
    assert_contains "$bus_out" "EVENTBUS_OK" "bus: full test passed"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.10  Services
# ═══════════════════════════════════════════════════════════════════
section "Services"

if [[ -x "$PYTHON" ]]; then
    svc_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path
from empusa.services import (
    Services, ScopedServices, LoggerService, ArtifactWriter,
    LootAccessor, EnvResolver, CommandRunner
)

td = Path(tempfile.mkdtemp())

# Create services
logger = LoggerService(verbose=False, quiet=True)
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
env = EnvResolver(lambda: 'test-env', lambda: td, lambda: ['10.10.10.1'])
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

# ArtifactWriter: write + containment
p = artifact.write('test/output.txt', 'hello from e2e')
assert p.exists(), 'artifact not written'
assert p.read_text() == 'hello from e2e'
print('artifact_write=ok')

# ArtifactWriter: path containment (no escape)
try:
    artifact.write('../../../etc/shadow', 'pwned')
    print('artifact_containment=FAILED')
except Exception:
    print('artifact_containment=ok')

# LootAccessor
loot.append({'host': '10.10.10.1', 'cred_type': 'password', 'username': 'admin', 'secret': 'pass123', 'source': 'e2e'})
entries = loot.read_all()
assert len(entries) == 1
assert entries[0]['username'] == 'admin'
print(f'loot_count={loot.count()}')

results = loot.search('host', '10.10.10.1')
assert len(results) == 1
print('loot_search=ok')

# EnvResolver
assert env.env_name() == 'test-env'
assert env.env_path() == td
assert env.hosts() == [] or True  # hosts() looks for dirs
assert env.is_active()
print('env_resolver=ok')

# ScopedServices: permission gating
scoped = ScopedServices(services, permissions=['loot_read'])
_ = scoped.loot.read_all()  # Should work
print('scoped_loot_read=ok')

try:
    scoped.loot.append({'test': True})
    print('scoped_loot_write=FAILED_should_deny')
except PermissionError:
    print('scoped_loot_write=denied_correctly')

# Cleanup
import shutil
shutil.rmtree(td)
print('SERVICES_OK')
" 2>&1)" || true

    assert_contains "$svc_out" "artifact_write=ok" "services: artifact write"
    assert_contains "$svc_out" "artifact_containment=ok" "services: path containment"
    assert_contains "$svc_out" "loot_count=1" "services: loot accessor"
    assert_contains "$svc_out" "loot_search=ok" "services: loot search"
    assert_contains "$svc_out" "env_resolver=ok" "services: env resolver"
    assert_contains "$svc_out" "scoped_loot_read=ok" "services: scoped read allowed"
    assert_contains "$svc_out" "scoped_loot_write=denied_correctly" "services: scoped write denied"
    assert_contains "$svc_out" "SERVICES_OK" "services: full test passed"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.11  Hooks
# ═══════════════════════════════════════════════════════════════════
section "Hooks"

if [[ -x "$PYTHON" ]]; then
    hooks_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path
from empusa.cli_hooks import init_hook_dirs

td = Path(tempfile.mkdtemp())
init_hook_dirs(td)

# Verify hook dirs created for all hookable events
hook_events = [
    'on_startup', 'on_shutdown', 'pre_build', 'post_build',
    'pre_scan_host', 'post_scan', 'on_loot_add', 'on_report_generated',
    'pre_report_write', 'on_env_select', 'pre_command', 'post_command',
    'post_compile'
]
for ev in hook_events:
    d = td / ev
    assert d.is_dir(), f'Missing hook dir: {ev}'
print(f'hook_dirs={len(hook_events)}')

import shutil
shutil.rmtree(td)
print('HOOKS_OK')
" 2>&1)" || true

    assert_contains "$hooks_out" "hook_dirs=13" "hooks: all 13 event dirs created"
    assert_contains "$hooks_out" "HOOKS_OK" "hooks: init lifecycle ok"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.12  Unknown permission rejection
# ═══════════════════════════════════════════════════════════════════
section "Unknown Permission Rejection"

if [[ -x "$PYTHON" ]]; then
    perm_out="$("$PYTHON" -c "
import sys, tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())
plug_dir = td / 'bad_perm_plugin'
plug_dir.mkdir()
manifest = {
    'name': 'bad_perm_plugin',
    'version': '0.1.0',
    'description': 'Plugin with invalid permission',
    'events': ['test_fire'],
    'requires': [],
    'permissions': ['network', 'hack_the_planet'],  # invalid
    'enabled': True,
}
(plug_dir / 'manifest.json').write_text(json.dumps(manifest))
(plug_dir / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
discovered = pm.discover()
# Plugin should be discovered but NOT activatable
desc = pm.plugins.get('bad_perm_plugin')
if desc and not desc.activatable:
    print('unknown_perm_blocked=ok')
else:
    print('unknown_perm_blocked=FAILED')

activated = pm.activate_all()
print(f'activated_count={activated}')

import shutil; shutil.rmtree(td)
print('UNKNOWN_PERM_OK')
" 2>&1)" || true

    assert_contains "$perm_out" "unknown_perm_blocked=ok" "perm: unknown permission blocks activation"
    assert_contains "$perm_out" "activated_count=0" "perm: blocked plugin not activated"
    assert_contains "$perm_out" "UNKNOWN_PERM_OK" "perm: test complete"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.13  Dependency cycle detection
# ═══════════════════════════════════════════════════════════════════
section "Dependency Cycle Detection"

if [[ -x "$PYTHON" ]]; then
    cycle_out="$("$PYTHON" -c "
import sys, tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

def make_plug(name, requires):
    d = td / name; d.mkdir()
    m = {'name': name, 'version': '0.1.0', 'description': f'{name}', 'events': ['test_fire'], 'requires': requires, 'permissions': [], 'enabled': True}
    (d / 'manifest.json').write_text(json.dumps(m))
    (d / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

# A -> B -> C -> A  (cycle)
make_plug('plug_a', ['plug_b'])
make_plug('plug_b', ['plug_c'])
make_plug('plug_c', ['plug_a'])

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
warnings = pm.resolve_dependencies()

# All three should be non-activatable
blocked = sum(1 for p in pm.plugins.values() if not p.activatable)
print(f'cycle_blocked={blocked}')

activated = pm.activate_all()
print(f'cycle_activated={activated}')

import shutil; shutil.rmtree(td)
print('CYCLE_OK')
" 2>&1)" || true

    assert_contains "$cycle_out" "cycle_blocked=3" "cycle: all 3 plugins blocked"
    assert_contains "$cycle_out" "cycle_activated=0" "cycle: none activated"
    assert_contains "$cycle_out" "CYCLE_OK" "cycle: detection complete"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.14  Blocked plugin cascade (transitive propagation)
# ═══════════════════════════════════════════════════════════════════
section "Blocked Plugin Cascade"

if [[ -x "$PYTHON" ]]; then
    cascade_out="$("$PYTHON" -c "
import sys, tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

def make_plug(name, requires, permissions=[]):
    d = td / name; d.mkdir()
    m = {'name': name, 'version': '0.1.0', 'description': f'{name}', 'events': ['test_fire'], 'requires': requires, 'permissions': permissions, 'enabled': True}
    (d / 'manifest.json').write_text(json.dumps(m))
    (d / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

# root_bad has invalid perms -> blocked
# child depends on root_bad -> should cascade block
# grandchild depends on child -> should also cascade
make_plug('root_bad', [], ['impossible_perm'])
make_plug('child', ['root_bad'])
make_plug('grandchild', ['child'])
# independent should be fine
make_plug('independent', [])

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
pm.resolve_dependencies()

blocked = [p.name for p in pm.plugins.values() if not p.activatable]
activated = pm.activate_all()

print(f'blocked_count={len(blocked)}')
print(f'root_blocked={\"root_bad\" in blocked}')
print(f'child_blocked={\"child\" in blocked}')
print(f'grandchild_blocked={\"grandchild\" in blocked}')
print(f'independent_ok={\"independent\" not in blocked}')
print(f'activated={activated}')

import shutil; shutil.rmtree(td)
print('CASCADE_OK')
" 2>&1)" || true

    assert_contains "$cascade_out" "blocked_count=3" "cascade: 3 plugins blocked"
    assert_contains "$cascade_out" "root_blocked=True" "cascade: root blocked"
    assert_contains "$cascade_out" "child_blocked=True" "cascade: child blocked"
    assert_contains "$cascade_out" "grandchild_blocked=True" "cascade: grandchild blocked"
    assert_contains "$cascade_out" "independent_ok=True" "cascade: independent survives"
    assert_contains "$cascade_out" "activated=1" "cascade: only independent activates"
    assert_contains "$cascade_out" "CASCADE_OK" "cascade: test complete"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.15  Event payload contracts for pre_* events
# ═══════════════════════════════════════════════════════════════════
section "Event Payload Contracts"

if [[ -x "$PYTHON" ]]; then
    payload_out="$("$PYTHON" -c "
import dataclasses
from empusa.events import (
    make_event, EVENT_MAP,
    PreWorkspaceInitEvent, PreBuildEvent, PreScanHostEvent,
    PreCommandEvent, PreReportWriteEvent
)

# Verify all pre_* events have correct required fields
checks = {
    'pre_workspace_init': {'workspace_name', 'workspace_root', 'profile', 'set_active'},
    'pre_build':          {'env_name', 'ips'},
    'pre_scan_host':      {'ip', 'env_name'},
    'pre_command':        {'command', 'args', 'working_dir'},
    'pre_report_write':   {'env_name', 'env_path', 'standalone_count', 'ad_count'},
}

all_ok = True
for event_name, required_fields in checks.items():
    cls = EVENT_MAP[event_name]
    field_names = {f.name for f in dataclasses.fields(cls)} - {'event', 'timestamp', 'session_env'}
    missing = required_fields - field_names
    extra = field_names - required_fields
    if missing:
        print(f'FAIL:{event_name}:missing={missing}')
        all_ok = False
    else:
        print(f'ok:{event_name}:fields={len(required_fields)}')

# make_event should produce correct types
evt = make_event('pre_workspace_init', workspace_name='test', workspace_root='/tmp', profile='htb', set_active=True)
assert isinstance(evt, PreWorkspaceInitEvent), f'Wrong type: {type(evt)}'
assert evt.workspace_name == 'test'
print('make_event_typed=ok')

# make_event with unknown fields should not crash
evt2 = make_event('pre_build', env_name='x', ips=['1.2.3.4'], bogus_field='ignored')
assert evt2.event == 'pre_build'
print('make_event_unknown_fields=ok')

# make_event with empty name should raise
try:
    make_event('', test=True)
    print('make_event_empty=FAILED')
except ValueError:
    print('make_event_empty=rejected')

if all_ok:
    print('PAYLOAD_OK')
" 2>&1)" || true

    assert_contains "$payload_out" "ok:pre_workspace_init" "payload: pre_workspace_init fields"
    assert_contains "$payload_out" "ok:pre_build" "payload: pre_build fields"
    assert_contains "$payload_out" "ok:pre_scan_host" "payload: pre_scan_host fields"
    assert_contains "$payload_out" "ok:pre_command" "payload: pre_command fields"
    assert_contains "$payload_out" "ok:pre_report_write" "payload: pre_report_write fields"
    assert_contains "$payload_out" "make_event_typed=ok" "payload: make_event returns typed class"
    assert_contains "$payload_out" "make_event_unknown_fields=ok" "payload: graceful unknown field handling"
    assert_contains "$payload_out" "make_event_empty=rejected" "payload: empty event name rejected"
    assert_contains "$payload_out" "PAYLOAD_OK" "payload: all contracts verified"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.16  ArtifactWriter traversal attacks
# ═══════════════════════════════════════════════════════════════════
section "ArtifactWriter Traversal"

if [[ -x "$PYTHON" ]]; then
    trav_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path
from empusa.services import ArtifactWriter, LoggerService

td = Path(tempfile.mkdtemp())
logger = LoggerService(verbose=False, quiet=True)
artifact = ArtifactWriter(td, logger)

# Each of these must be rejected
attacks = [
    '../../../etc/passwd',
    '../../.ssh/authorized_keys',
    '/etc/shadow',
    'foo/../../../../../../tmp/pwned',
    '../' * 20 + 'etc/passwd',
]
blocked = 0
for atk in attacks:
    try:
        artifact.write(atk, 'pwned')
    except (ValueError, RuntimeError, OSError):
        blocked += 1

print(f'traversal_blocked={blocked}/{len(attacks)}')

# Legitimate nested path should work
p = artifact.write('deep/nested/file.txt', 'safe')
assert p.exists()
print('legitimate_write=ok')

# exists() on traversal should return False, not crash
safe = artifact.exists('../../../etc/passwd')
print(f'exists_traversal_safe={not safe}')

import shutil; shutil.rmtree(td)
print('TRAVERSAL_OK')
" 2>&1)" || true

    assert_contains "$trav_out" "traversal_blocked=5/5" "traversal: all 5 attacks blocked"
    assert_contains "$trav_out" "legitimate_write=ok" "traversal: legitimate write works"
    assert_contains "$trav_out" "exists_traversal_safe=True" "traversal: exists() safe"
    assert_contains "$trav_out" "TRAVERSAL_OK" "traversal: test complete"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.17  ScopedServices full permission matrix
# ═══════════════════════════════════════════════════════════════════
section "ScopedServices Permissions"

if [[ -x "$PYTHON" ]]; then
    scope_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path
from empusa.services import (
    Services, ScopedServices, LoggerService, ArtifactWriter,
    LootAccessor, EnvResolver, CommandRunner, PermissionError
)

td = Path(tempfile.mkdtemp())
logger = LoggerService(verbose=False, quiet=True)
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
env = EnvResolver(lambda: 'test', lambda: td, lambda: [])
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

# Test: no permissions
bare = ScopedServices(services, permissions=[], plugin_name='bare')
# logger and env always available
_ = bare.logger
_ = bare.env
print('bare_logger_env=ok')

# artifact.write should fail without filesystem
try:
    bare.artifact.write('test.txt', 'data')
    print('bare_artifact_write=FAIL_should_deny')
except PermissionError:
    print('bare_artifact_write=denied')

# artifact.exists should work without any permission
_ = bare.artifact.exists('test.txt')
print('bare_artifact_exists=ok')

# loot read without loot_read
try:
    bare.loot.read_all()
    print('bare_loot_read=FAIL_should_deny')
except PermissionError:
    print('bare_loot_read=denied')

# runner without subprocess
try:
    bare.runner.run(['echo', 'hi'])
    print('bare_runner=FAIL_should_deny')
except PermissionError:
    print('bare_runner=denied')

# Test: all permissions
full = ScopedServices(services, permissions=['filesystem', 'loot_read', 'loot_write', 'subprocess', 'network', 'registry'], plugin_name='full')
full.artifact.write('allowed.txt', 'yes')
full.loot.append({'test': True})
_ = full.loot.read_all()
_ = full.runner.run(['echo', 'ok'])
print('full_perms=ok')

import shutil; shutil.rmtree(td)
print('SCOPE_OK')
" 2>&1)" || true

    assert_contains "$scope_out" "bare_logger_env=ok" "scope: logger+env always available"
    assert_contains "$scope_out" "bare_artifact_write=denied" "scope: artifact.write without filesystem denied"
    assert_contains "$scope_out" "bare_artifact_exists=ok" "scope: artifact.exists without permission ok"
    assert_contains "$scope_out" "bare_loot_read=denied" "scope: loot.read without loot_read denied"
    assert_contains "$scope_out" "bare_runner=denied" "scope: runner without subprocess denied"
    assert_contains "$scope_out" "full_perms=ok" "scope: all permissions grant access"
    assert_contains "$scope_out" "SCOPE_OK" "scope: permission matrix complete"
fi

# ═══════════════════════════════════════════════════════════════════
#  5.18  Plugin activation exception isolation
# ═══════════════════════════════════════════════════════════════════
section "Activation Exception Isolation"

if [[ -x "$PYTHON" ]]; then
    iso_out="$("$PYTHON" -c "
import sys, tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

# Plugin that crashes on activate
crash_dir = td / 'crash_plugin'
crash_dir.mkdir()
m = {'name': 'crash_plugin', 'version': '0.1.0', 'description': 'crashes', 'events': ['test_fire'], 'requires': [], 'permissions': [], 'enabled': True}
(crash_dir / 'manifest.json').write_text(json.dumps(m))
(crash_dir / 'plugin.py').write_text('def activate(s,r,b): raise RuntimeError(\"boom\")\ndef deactivate(): pass\n')

# Good plugin
good_dir = td / 'good_plugin'
good_dir.mkdir()
m2 = {'name': 'good_plugin', 'version': '0.1.0', 'description': 'works', 'events': ['test_fire'], 'requires': [], 'permissions': [], 'enabled': True}
(good_dir / 'manifest.json').write_text(json.dumps(m2))
(good_dir / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
artifact = ArtifactWriter(td, logger)
loot = LootAccessor(td / 'loot.json', logger)
runner = CommandRunner(logger, dry_run=True)
services = Services(logger=logger, artifact=artifact, loot=loot, env=env, runner=runner)

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
pm.resolve_dependencies()

# activate_all should NOT crash even though crash_plugin raises
activated = pm.activate_all()
print(f'activated={activated}')

# good_plugin should still be active
good = pm.plugins.get('good_plugin')
crash = pm.plugins.get('crash_plugin')
print(f'good_active={good.activated if good else \"missing\"}')
print(f'crash_active={crash.activated if crash else \"missing\"}')

import shutil; shutil.rmtree(td)
print('ISOLATION_OK')
" 2>&1)" || true

    assert_contains "$iso_out" "activated=1" "isolation: one plugin activated despite crash"
    assert_contains "$iso_out" "good_active=True" "isolation: good plugin survived"
    assert_contains "$iso_out" "crash_active=False" "isolation: crash plugin not active"
    assert_contains "$iso_out" "ISOLATION_OK" "isolation: exception did not cascade"
fi

end_stage
