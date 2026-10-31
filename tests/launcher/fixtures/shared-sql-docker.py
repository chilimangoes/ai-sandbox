#!/usr/bin/env python3
"""Stateful Docker fixture, serialized across concurrent bootstrap processes."""
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[1:]
path = Path(os.environ['SANDBOX_TEST_STATE'])
lock = open(str(path) + '.lock', 'a+b')
lock.write(b'0')
lock.flush()
lock.seek(0)
if os.name == 'nt':
    import msvcrt
    msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
else:
    import fcntl
    fcntl.flock(lock, fcntl.LOCK_EX)
state = json.loads(path.read_text())
state['calls'].append(args)


def finish(code=0, output=''):
    path.write_text(json.dumps(state))
    if output:
        print(output)
    sys.exit(code)


def option(key):
    return args[args.index(key) + 1]


if args[0] == 'sandbox-invocation':
    finish()
if args[:2] == ['image', 'ls'] or args[0] == 'pull':
    finish(output='sql-image')
if args[:2] == ['container', 'ls']:
    filters = [args[i + 1] for i, value in enumerate(args) if value == '--filter']
    containers = list(state['containers'].values())
    for value in filters:
        if value.startswith('label='):
            key, expected = value[6:].split('=', 1)
            containers = [c for c in containers if c['Config']['Labels'].get(key) == expected]
        else:
            name = value.removeprefix('name=').lstrip('^/').rstrip('$')
            containers = [c for c in containers if c['Name'] == name]
    finish(output='\n'.join(c['Id'] for c in containers))
if args[:2] == ['container', 'inspect']:
    container = state['containers'][args[-1]]
    if '--format' not in args:
        finish(output=json.dumps([container]))
    template = option('--format')
    if template == '{{.Image}}':
        finish(output=container['Image'])
    if '.Config.Env' in template:
        finish(output='\n'.join(container['Config']['Env']))
    finish(output=container['Config']['Labels'].get('ai-sandbox.shared-sql', ''))
if args[0] == 'run':
    name = option('--name')
    if any(c['Name'] == name for c in state['containers'].values()):
        finish(1)
    state['leases'] += 1
    identifier = 'lease-' + str(state['leases'])
    key, value = option('--label').split('=', 1)
    state['containers'][identifier] = {'Id': identifier, 'Name': name, 'Image': 'sql-image', 'Config': {'Labels': {key: value}, 'Env': []}}
    finish(output=identifier)
if args[0] == 'rm':
    state['containers'].pop(args[-1], None)
    finish()
if args[:2] == ['network', 'ls']:
    name = option('--filter').removeprefix('name=').lstrip('^').rstrip('$')
    finish(output=name if name in state['networks'] else '')
if args[:2] == ['network', 'create']:
    state['networks'].append(args[-1])
    finish(output=args[-1])
if args[0] == 'compose':
    group = option('--project-name')
    if 'up' in args:
        time.sleep(0.15)
        if 'sql-1' not in state['containers']:
            state['sql_creations'] = state.get('sql_creations', 0) + 1
            directory = Path(option('--file')).parent.parent / '.local/test-sql'
            state['containers']['sql-1'] = {'Id': 'sql-1', 'Name': group + '-sql-1', 'Image': 'sql-image', 'Config': {
                'Labels': {'com.docker.compose.project': group, 'com.docker.compose.service': 'sql'},
                'Env': (directory / 'server.env').read_text().splitlines(),
            }}
        print('Docker progress on stderr', file=sys.stderr)
        finish()
    if 'init' in args:
        finish(19 if state.get('fail_init') else 0)
finish(99, 'Unexpected fixture command: ' + repr(args))
