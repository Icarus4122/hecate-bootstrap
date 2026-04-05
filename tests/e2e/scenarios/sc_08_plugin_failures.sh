#!/usr/bin/env bash
# scenarios/sc_08_plugin_failures.sh - Plugin graph failure modes.
#
# Tests: blocked plugin cascades, dependency cycles, unknown permissions,
# activation exceptions, dispatch exceptions, disabled plugins,
# and the full refresh lifecycle.
#
# Prerequisites: Empusa installed (no Docker needed)

begin_scenario "plugin-failures" "Plugin system failure modes and exception isolation"

LAB="${LAB_ROOT:-/opt/lab}"
PYTHON="$LAB/tools/venvs/empusa/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    skip_scenario "plugin-failures" "Empusa Python not available"
    return 0
fi

# ── Test 1: Missing dependency blocks dependent ────────────────────
section "Missing Dependency"

missing_out="$("$PYTHON" -c "
import tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

def make(name, requires=[], permissions=[]):
    d = td / name; d.mkdir()
    m = {'name': name, 'version': '0.1.0', 'description': name, 'events': ['test_fire'], 'requires': requires, 'permissions': permissions, 'enabled': True}
    (d / 'manifest.json').write_text(json.dumps(m))
    (d / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

# depends_on_ghost requires 'ghost' which doesn't exist
make('depends_on_ghost', requires=['ghost'])
make('standalone')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
services = Services(logger=logger, artifact=ArtifactWriter(td, logger), loot=LootAccessor(td/'l.json', logger), env=env, runner=CommandRunner(logger, dry_run=True))

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
pm.resolve_dependencies()

ghost_dep = pm.plugins.get('depends_on_ghost')
standalone = pm.plugins.get('standalone')
print(f'ghost_dep_blocked={not ghost_dep.activatable}')
print(f'standalone_ok={standalone.activatable}')

activated = pm.activate_all()
print(f'activated={activated}')

import shutil; shutil.rmtree(td)
print('MISSING_DEP_OK')
" 2>&1)" || true

assert_contains "$missing_out" "ghost_dep_blocked=True" "missing dep: blocked"
assert_contains "$missing_out" "standalone_ok=True" "missing dep: standalone ok"
assert_contains "$missing_out" "activated=1" "missing dep: only standalone activates"
assert_contains "$missing_out" "MISSING_DEP_OK" "missing dep: test complete"

# ── Test 2: Dispatch exception doesn't kill other plugins ─────────
section "Dispatch Exception Isolation"

dispatch_out="$("$PYTHON" -c "
import tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

def make(name, code):
    d = td / name; d.mkdir()
    m = {'name': name, 'version': '0.1.0', 'description': name, 'events': ['test_fire'], 'requires': [], 'permissions': [], 'enabled': True}
    (d / 'manifest.json').write_text(json.dumps(m))
    (d / 'plugin.py').write_text(code)

# Crasher raises during dispatch
make('crasher', '''
def activate(s,r,b): pass
def deactivate(): pass
def on_test_fire(event):
    raise RuntimeError('dispatch boom')
''')

# Good handler returns data
make('good_handler', '''
results = []
def activate(s,r,b): pass
def deactivate(): pass
def on_test_fire(event):
    return {'status': 'ok', 'plugin': 'good_handler'}
''')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner
from empusa.events import make_event

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
services = Services(logger=logger, artifact=ArtifactWriter(td, logger), loot=LootAccessor(td/'l.json', logger), env=env, runner=CommandRunner(logger, dry_run=True))

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
pm.resolve_dependencies()
pm.activate_all()

# Dispatch should not crash despite crasher
evt = make_event('test_fire', session_env='e2e')
results = pm.dispatch_event('test_fire', evt)

# good_handler result should be present
good_results = [r for r in results if r.get('plugin') == 'good_handler']
print(f'good_result_count={len(good_results)}')
print(f'total_results={len(results)}')

import shutil; shutil.rmtree(td)
print('DISPATCH_ISO_OK')
" 2>&1)" || true

assert_contains "$dispatch_out" "good_result_count=1" "dispatch iso: good handler survived"
assert_contains "$dispatch_out" "DISPATCH_ISO_OK" "dispatch iso: test complete"

# ── Test 3: Disabled plugin is not activated ───────────────────────
section "Disabled Plugin"

disabled_out="$("$PYTHON" -c "
import tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

d = td / 'disabled_plug'
d.mkdir()
m = {'name': 'disabled_plug', 'version': '0.1.0', 'description': 'x', 'events': ['test_fire'], 'requires': [], 'permissions': [], 'enabled': False}
(d / 'manifest.json').write_text(json.dumps(m))
(d / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
services = Services(logger=logger, artifact=ArtifactWriter(td, logger), loot=LootAccessor(td/'l.json', logger), env=env, runner=CommandRunner(logger, dry_run=True))

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
pm.discover()
pm.resolve_dependencies()
activated = pm.activate_all()

desc = pm.plugins.get('disabled_plug')
print(f'activated_count={activated}')
print(f'is_activated={desc.activated}')
print(f'is_enabled={desc.enabled}')

import shutil; shutil.rmtree(td)
print('DISABLED_OK')
" 2>&1)" || true

assert_contains "$disabled_out" "activated_count=0" "disabled: not activated"
assert_contains "$disabled_out" "is_activated=False" "disabled: activated=False"
assert_contains "$disabled_out" "is_enabled=False" "disabled: enabled=False"
assert_contains "$disabled_out" "DISABLED_OK" "disabled: test complete"

# ── Test 4: Refresh lifecycle (full reset + rediscovery) ───────────
section "Plugin Refresh Lifecycle"

refresh_out="$("$PYTHON" -c "
import tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())

def make(name):
    d = td / name; d.mkdir()
    m = {'name': name, 'version': '0.1.0', 'description': name, 'events': ['test_fire'], 'requires': [], 'permissions': [], 'enabled': True}
    (d / 'manifest.json').write_text(json.dumps(m))
    (d / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

make('alpha')
make('beta')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
services = Services(logger=logger, artifact=ArtifactWriter(td, logger), loot=LootAccessor(td/'l.json', logger), env=env, runner=CommandRunner(logger, dry_run=True))

reg = CapabilityRegistry()
pm = PluginManager(td, services, reg, EventBus())
pm.discover(); pm.resolve_dependencies(); pm.activate_all()
print(f'initial_active={pm.active_count()}')

# Add a new plugin at runtime
make('gamma')

# Refresh should pick it up
warnings = pm.refresh()
print(f'post_refresh_active={pm.active_count()}')
print(f'gamma_active={pm.plugins.get(\"gamma\", None) and pm.plugins[\"gamma\"].activated}')

import shutil; shutil.rmtree(td)
print('REFRESH_OK')
" 2>&1)" || true

assert_contains "$refresh_out" "initial_active=2" "refresh: started with 2"
assert_contains "$refresh_out" "post_refresh_active=3" "refresh: picked up gamma"
assert_contains "$refresh_out" "gamma_active=True" "refresh: gamma activated"
assert_contains "$refresh_out" "REFRESH_OK" "refresh: lifecycle complete"

# ── Test 5: Bad manifest JSON is skipped ───────────────────────────
section "Bad Manifest"

badmanifest_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path

td = Path(tempfile.mkdtemp())

# Valid plugin
d1 = td / 'valid'
d1.mkdir()
(d1 / 'manifest.json').write_text('{\"name\":\"valid\",\"version\":\"0.1.0\",\"description\":\"ok\",\"events\":[\"test_fire\"]}')
(d1 / 'plugin.py').write_text('def activate(s,r,b): pass\ndef deactivate(): pass\n')

# Bad JSON
d2 = td / 'badjson'
d2.mkdir()
(d2 / 'manifest.json').write_text('NOT VALID JSON {{{')
(d2 / 'plugin.py').write_text('def activate(s,r,b): pass\n')

# Missing required field
d3 = td / 'incomplete'
d3.mkdir()
(d3 / 'manifest.json').write_text('{\"name\":\"incomplete\"}')
(d3 / 'plugin.py').write_text('def activate(s,r,b): pass\n')

from empusa.plugins import PluginManager
from empusa.bus import EventBus
from empusa.registry import CapabilityRegistry
from empusa.services import Services, LoggerService, ArtifactWriter, LootAccessor, EnvResolver, CommandRunner

logger = LoggerService(verbose=False, quiet=True)
env = EnvResolver(lambda: '', lambda: None, lambda: [])
services = Services(logger=logger, artifact=ArtifactWriter(td, logger), loot=LootAccessor(td/'l.json', logger), env=env, runner=CommandRunner(logger, dry_run=True))

pm = PluginManager(td, services, CapabilityRegistry(), EventBus())
discovered = pm.discover()
print(f'discovered={len(discovered)}')

pm.resolve_dependencies()
activated = pm.activate_all()
print(f'activated={activated}')

import shutil; shutil.rmtree(td)
print('BADMANIFEST_OK')
" 2>&1)" || true

assert_contains "$badmanifest_out" "discovered=1" "bad manifest: only valid discovered"
assert_contains "$badmanifest_out" "activated=1" "bad manifest: only valid activated"
assert_contains "$badmanifest_out" "BADMANIFEST_OK" "bad manifest: test complete"

end_scenario
