#!/usr/bin/env python3
"""Docker fixture for launcher behavior; all state stays in a temporary directory."""
import hashlib
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[1:]
state_path = Path(os.environ['SANDBOX_TEST_STATE'])
state = json.loads(state_path.read_text())
state['calls'].append(args)


def finish(code=0, output=''):
    state_path.write_text(json.dumps(state))
    if output:
        print(output)
    sys.exit(code)


def option(name):
    return args[args.index(name) + 1]


if args[0] == 'version':
    finish(output='test Docker')
if args[0] == 'sandbox-invocation':
    finish()
if args[:2] == ['network', 'inspect']:
    finish(0 if args[2] in state['networks'] else 1)
if args[:2] == ['network', 'create']:
    state['networks'].append(args[2])
    finish(output=args[2])
if args[0] == 'compose':
    finish()
if args[:2] == ['image', 'inspect']:
    image = state['images'].get(args[-1])
    finish(0 if image else 1, image or '')
if args[0] == 'build':
    tag = option('-t')
    if tag.startswith('ai-sandbox-workspace:') and state.get('fail_build'):
        finish(17, 'simulated project build failure')
    time.sleep(state.get('build_delay', 0))
    digest = hashlib.sha256()
    if '--build-arg' in args:
        base = option('--build-arg').split('=', 1)[1]
        digest.update(state['images'][base].encode())
        for path in sorted(Path(args[-1]).rglob('*')):
            if path.is_file() and path.name in ('Dockerfile', 'install.sh'):
                digest.update(path.relative_to(args[-1]).as_posix().encode())
                digest.update(path.read_bytes())
    else:
        digest.update(str(len([call for call in state['calls'] if call[0] == 'build'])).encode())
    state['images'][tag] = 'sha256:' + digest.hexdigest()
    finish()
if args[0] == 'tag':
    state['images'][args[2]] = args[1]
    finish()
if args[0] == 'ps':
    name = option('--filter').removeprefix('name=').lstrip('^/').removesuffix('$')
    container = state['containers'].get(name)
    finish(output=name if container and ('-a' in args or container['running']) else '')
if args[0] == 'inspect':
    container = state['containers'][args[-1]]
    template = option('--format')
    if template == '{{.Image}}':
        finish(output=container['image'])
    if template == '{{ json .Config.Labels }}':
        finish(output=json.dumps(container['labels']))
    label = template.split('"')[1]
    finish(output=container['labels'].get(label, '<no value>'))
if args[0] == 'port':
    port = args[-1].split('/')[0]
    finish(output='127.64.1.1:' + port)
if args[:2] == ['volume', 'inspect']:
    finish(0 if args[-1] in state['volumes'] else 1)
if args[:2] == ['volume', 'ls']:
    name = option('--filter').removeprefix('name=').lstrip('^').removesuffix('$')
    finish(output=name if name in state['volumes'] else '')
if args[:2] == ['volume', 'create']:
    state['volumes'].append(args[-1])
    finish(output=args[-1])
if args[:2] == ['volume', 'rm']:
    state['volumes'] = [name for name in state['volumes'] if name not in args[2:]]
    finish()
if args[0] == 'run':
    name = option('--name')
    if name in state['containers']:
        finish(1, 'container already exists')
    labels = dict(args[index + 1].split('=', 1) for index, arg in enumerate(args) if arg == '--label')
    state['containers'][name] = {'image': state['images'][args[-2]], 'labels': labels, 'running': True}
    finish(output=name)
if args[0] == 'rm':
    state['containers'].pop(args[-1], None)
    finish()
if args[0] in ('stop', 'start'):
    state['containers'][args[-1]]['running'] = args[0] == 'start'
    finish()
if args[0] == 'exec':
    finish()
finish(99, 'Unexpected fixture command: ' + repr(args))
