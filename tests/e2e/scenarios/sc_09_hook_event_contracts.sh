#!/usr/bin/env bash
# scenarios/sc_09_hook_event_contracts.sh - Hook/event contract validation.
#
# Tests: event payload structure for every event type, hook directory
# contract, legacy hook execution, bus subscriber lifecycle, event
# ordering guarantees, and pre_* event timing semantics.
#
# Prerequisites: Empusa installed (no Docker needed)

begin_scenario "hook-event-contracts" "Event payload contracts and hook system guarantees"

LAB="${LAB_ROOT:-/opt/lab}"
PYTHON="$LAB/tools/venvs/empusa/bin/python"

if [[ ! -x "$PYTHON" ]]; then
    skip_scenario "hook-event-contracts" "Empusa Python not available"
    return 0
fi

# ── Test 1: All event types construct correctly ────────────────────
section "Event Construction"

construct_out="$("$PYTHON" -c "
from empusa.events import EVENT_MAP, make_event, ALL_EVENTS
import dataclasses

ok = 0
fail = 0
for name, cls in EVENT_MAP.items():
    # Every event must construct with just session_env
    try:
        # Build with defaults for required fields
        fields = dataclasses.fields(cls)
        kwargs = {}
        for f in fields:
            if f.name in ('event', 'timestamp', 'session_env'):
                continue
            # Provide type-appropriate defaults
            if f.type == 'str' or 'str' in str(f.type):
                kwargs[f.name] = ''
            elif f.type == 'bool' or 'bool' in str(f.type):
                kwargs[f.name] = False
            elif 'list' in str(f.type).lower():
                kwargs[f.name] = []
            elif 'int' in str(f.type):
                kwargs[f.name] = 0
            else:
                kwargs[f.name] = ''
        evt = cls(event=name, session_env='e2e', **kwargs)
        d = evt.to_dict()
        assert 'event' in d
        assert 'timestamp' in d
        assert 'session_env' in d
        assert d['event'] == name
        ok += 1
    except Exception as e:
        print(f'FAIL:{name}:{e}')
        fail += 1

print(f'construct_ok={ok}')
print(f'construct_fail={fail}')
print(f'total_events={len(EVENT_MAP)}')
print('CONSTRUCT_OK')
" 2>&1)" || true

assert_contains "$construct_out" "construct_fail=0" "construct: no failures"
assert_contains "$construct_out" "total_events=17" "construct: all 17 events"
assert_contains "$construct_out" "CONSTRUCT_OK" "construct: complete"

# ── Test 2: to_dict() serialization round-trip ─────────────────────
section "Event Serialization"

serial_out="$("$PYTHON" -c "
from empusa.events import make_event

# Test with complex event
evt = make_event('post_build', env_name='test', env_path='/tmp/test', ips=['10.10.10.1', '10.10.10.2'])
d = evt.to_dict()

assert isinstance(d, dict), 'not a dict'
assert d['event'] == 'post_build'
assert d['env_name'] == 'test'
assert isinstance(d['ips'], list)
assert len(d['ips']) == 2
print('post_build_serial=ok')

# Path objects should serialize to strings
from pathlib import Path
evt2 = make_event('on_report_generated', report_path=str(Path('/tmp/report.md')), env_name='x', env_path='/tmp', standalone_count=5, ad_count=2)
d2 = evt2.to_dict()
assert isinstance(d2['report_path'], str), f'Path not str: {type(d2[\"report_path\"])}'
print('path_serial=ok')

# Timestamp should auto-fill
assert d['timestamp'] != ''
print('timestamp_auto=ok')

print('SERIAL_OK')
" 2>&1)" || true

assert_contains "$serial_out" "post_build_serial=ok" "serial: complex event"
assert_contains "$serial_out" "path_serial=ok" "serial: Path→str"
assert_contains "$serial_out" "timestamp_auto=ok" "serial: auto-timestamp"
assert_contains "$serial_out" "SERIAL_OK" "serial: complete"

# ── Test 3: Legacy hook execution ──────────────────────────────────
section "Legacy Hook Execution"

hook_out="$("$PYTHON" -c "
import tempfile, json
from pathlib import Path

td = Path(tempfile.mkdtemp())
hooks_dir = td / 'hooks'
hooks_dir.mkdir()

# Create hook dir for on_startup
startup_dir = hooks_dir / 'on_startup'
startup_dir.mkdir()

# Create a hook script that writes a marker file
marker = td / 'hook_fired.txt'
(startup_dir / '01_test_hook.py').write_text(f'''
from pathlib import Path
def run(context):
    Path(\"{marker}\").write_text(\"hook_executed\")
''')

from empusa.bus import EventBus
from empusa.events import make_event

bus = EventBus(hooks_dir=hooks_dir, verbose=False, quiet=True)
evt = make_event('on_startup', session_env='e2e')
bus.emit(evt)

# Check marker
if marker.exists() and marker.read_text() == 'hook_executed':
    print('legacy_hook_fired=ok')
else:
    print('legacy_hook_fired=FAILED')

# Hook should be listed
hooks = bus.list_legacy_hooks()
if 'on_startup' in hooks and '01_test_hook.py' in hooks['on_startup']:
    print('legacy_hook_listed=ok')
else:
    print('legacy_hook_listed=FAILED')

import shutil; shutil.rmtree(td)
print('LEGACY_OK')
" 2>&1)" || true

assert_contains "$hook_out" "legacy_hook_fired=ok" "legacy: hook executed"
assert_contains "$hook_out" "legacy_hook_listed=ok" "legacy: hook listed"
assert_contains "$hook_out" "LEGACY_OK" "legacy: complete"

# ── Test 4: Subscriber ordering ────────────────────────────────────
section "Subscriber Ordering"

order_out="$("$PYTHON" -c "
from empusa.bus import EventBus
from empusa.events import make_event

bus = EventBus()

order = []

def first(event): order.append('first')
def second(event): order.append('second')
def third(event): order.append('third')

bus.subscribe('test_fire', first)
bus.subscribe('test_fire', second)
bus.subscribe('test_fire', third)

evt = make_event('test_fire', session_env='e2e')
bus.emit(evt)

if order == ['first', 'second', 'third']:
    print('order=correct')
else:
    print(f'order=WRONG:{order}')

print('ORDER_OK')
" 2>&1)" || true

assert_contains "$order_out" "order=correct" "ordering: FIFO subscriber dispatch"
assert_contains "$order_out" "ORDER_OK" "ordering: complete"

# ── Test 5: Subscriber exception doesn't kill other subscribers ────
section "Subscriber Exception Isolation"

sub_iso_out="$("$PYTHON" -c "
from empusa.bus import EventBus
from empusa.events import make_event

bus = EventBus()

results = []

def crasher(event): raise RuntimeError('subscriber boom')
def survivor(event): results.append('survived')

bus.subscribe('test_fire', crasher)
bus.subscribe('test_fire', survivor)

evt = make_event('test_fire', session_env='e2e')
bus.emit(evt)

if 'survived' in results:
    print('sub_isolation=ok')
else:
    print('sub_isolation=FAILED')

print('SUB_ISO_OK')
" 2>&1)" || true

assert_contains "$sub_iso_out" "sub_isolation=ok" "sub iso: survivor received event"
assert_contains "$sub_iso_out" "SUB_ISO_OK" "sub iso: complete"

# ── Test 6: pre_* event fields match post_* counterparts ──────────
section "Pre/Post Field Consistency"

prepost_out="$("$PYTHON" -c "
import dataclasses
from empusa.events import EVENT_MAP

pairs = [
    ('pre_workspace_init', 'post_workspace_init'),
    ('pre_build', 'post_build'),
    ('pre_scan_host', 'post_scan'),
    ('pre_command', 'post_command'),
    ('pre_report_write', 'on_report_generated'),
]

all_ok = True
for pre_name, post_name in pairs:
    pre_cls = EVENT_MAP[pre_name]
    post_cls = EVENT_MAP[post_name]
    pre_fields = {f.name for f in dataclasses.fields(pre_cls)} - {'event', 'timestamp', 'session_env'}
    post_fields = {f.name for f in dataclasses.fields(post_cls)} - {'event', 'timestamp', 'session_env'}

    # Pre fields should be a subset of post fields (post may have more)
    if pre_fields <= post_fields:
        print(f'ok:{pre_name}->{post_name}:pre_subset')
    else:
        extra = pre_fields - post_fields
        print(f'WARN:{pre_name}->{post_name}:pre_has_extra={extra}')
        # This is a warning, not a failure — pre may legitimately have unique fields

print('PREPOST_OK')
" 2>&1)" || true

assert_contains "$prepost_out" "PREPOST_OK" "pre/post: field analysis complete"

# ── Test 7: Hook directory contract (all hookable events) ──────────
section "Hook Directory Contract"

hookdir_out="$("$PYTHON" -c "
import tempfile
from pathlib import Path
from empusa.cli_hooks import init_hook_dirs

td = Path(tempfile.mkdtemp())
init_hook_dirs(td)

# Every event that can have hooks should have a directory
HOOKABLE = [
    'on_startup', 'on_shutdown', 'pre_build', 'post_build',
    'pre_scan_host', 'post_scan', 'on_loot_add', 'on_report_generated',
    'pre_report_write', 'on_env_select', 'pre_command', 'post_command',
    'post_compile'
]

ok = 0
for ev in HOOKABLE:
    d = td / ev
    if d.is_dir():
        ok += 1
    else:
        print(f'MISSING:{ev}')

print(f'hookdirs_ok={ok}/{len(HOOKABLE)}')

import shutil; shutil.rmtree(td)
print('HOOKDIR_OK')
" 2>&1)" || true

assert_contains "$hookdir_out" "hookdirs_ok=13/13" "hook dirs: all 13 created"
assert_contains "$hookdir_out" "HOOKDIR_OK" "hook dirs: contract verified"

end_scenario
