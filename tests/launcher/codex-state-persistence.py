"""Check Codex migration, user dispatch, archiving, and container recreation."""

import json
import os
from pathlib import Path
import selectors
import sqlite3
import subprocess
import sys
import time
import uuid


def docker(*args):
    result = subprocess.run(['docker', *args], capture_output=True, text=True, encoding='utf-8', errors='replace')
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout.strip()


def check_cli_startup():
    import pwd
    import signal
    import socket

    path = Path('/home/sandbox/.codex/app-server-control/verification.sock')
    process = subprocess.Popen(
        ['codex', 'app-server', '--listen', f'unix://{path}'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not path.exists() and process.poll() is None:
            time.sleep(0.1)
        assert path.exists(), 'Codex CLI did not create its socket'
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(str(path))
        assert path.stat().st_uid == pwd.getpwnam('sandbox').pw_uid
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        path.unlink(missing_ok=True)
    print('Codex CLI socket startup passed')


def inside(mode):
    import pwd

    home = Path('/home/sandbox/.codex')
    state = Path('/state/data/codex')
    if mode == 'migrate':
        home.mkdir()
        (state / 'sessions').mkdir(parents=True)
        (state / 'sessions/legacy-marker').write_text('session')
        (home / 'sessions').symlink_to(state / 'sessions')
        (home / '.migration-marker').write_text('home')
        (home / 'app-server-control').mkdir(mode=0o700)
        (home / 'app-server-control/startup.lock').touch()
        (home / 'thread-writer-locks').mkdir()
        with sqlite3.connect(home / 'persistence.sqlite') as db:
            db.execute('CREATE TABLE marker (value TEXT)')
            db.execute("INSERT INTO marker VALUES ('database')")
        (home / 'conflict-marker').write_text('local')
        (state / 'conflict-marker').write_text('persistent')
        conflict = subprocess.run(['/opt/ai-sandbox/entrypoint.sh', 'codex', '--version'],
                                  capture_output=True, text=True)
        assert conflict.returncode != 0 and 'Cannot migrate Codex state' in conflict.stderr
        assert (home / 'conflict-marker').read_text() == 'local'
        assert (state / 'conflict-marker').read_text() == 'persistent'
        (home / 'conflict-marker').unlink()
        (state / 'conflict-marker').unlink()
        subprocess.run(['/opt/ai-sandbox/entrypoint.sh', 'codex', '--version'], check=True)

    assert home.is_symlink() and home.resolve() == state
    assert not (home / 'sessions').is_symlink()
    assert (home / 'sessions/legacy-marker').read_text() == 'session'
    assert (home / '.migration-marker').read_text() == 'home'
    assert (home / 'config.toml').resolve() == Path('/state/config/codex/config.toml')
    assert (home / 'auth.json').is_symlink()
    with sqlite3.connect(home / 'persistence.sqlite') as db:
        assert db.execute('SELECT value FROM marker').fetchone() == ('database',)
    sandbox_uid = pwd.getpwnam('sandbox').pw_uid
    for path in [state, home / 'app-server-control', home / 'thread-writer-locks']:
        assert path.stat().st_uid == sandbox_uid, path

    if mode == 'verify':
        thread_id = (home / 'verification-thread').read_text()
        with sqlite3.connect(home / 'state_5.sqlite') as db:
            assert db.execute('SELECT archived FROM threads WHERE id=?', (thread_id,)).fetchone() == (1,)
        assert list((home / 'archived_sessions').glob(f'*{thread_id}.jsonl'))
        print('Codex state survived container recreation')
        check_cli_startup()
        return

    # Observe the public command's user and arguments without invoking inference.
    binary = Path('/opt/ai-sandbox/bin/codex')
    original_target = os.readlink(binary)
    native = Path(original_target).resolve()
    binary.unlink()
    binary.write_text('#!/bin/sh\nid -u\nprintf "%s\\n" "$HOME" "$@"\n')
    binary.chmod(0o755)
    try:
        result = subprocess.run(['codex', 'argument with spaces'], check=True, capture_output=True, text=True)
        assert result.stdout.splitlines() == [str(sandbox_uid), '/home/sandbox', 'argument with spaces'], result.stdout
    finally:
        binary.unlink()
        binary.symlink_to(original_target)

    # T3 invokes the native app-server as sandbox through this same protocol.
    process = subprocess.Popen(
        ['runuser', '-u', 'sandbox', '--', 'env', 'HOME=/home/sandbox', str(native), 'app-server'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0,
    )
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    def request(identifier, method, params):
        process.stdin.write((json.dumps({'id': identifier, 'method': method, 'params': params}) + '\n').encode())
        process.stdin.flush()
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if selector.select(0.2):
                line = process.stdout.readline()
                assert line, f'app-server exited during {method}'
                response = json.loads(line)
                if response.get('id') == identifier:
                    assert 'error' not in response, response
                    return response['result']
        raise AssertionError(f'app-server timed out during {method}')

    try:
        request(1, 'initialize', {'clientInfo': {'name': 'codex-state-test', 'version': '1'}})
        process.stdin.write(b'{"method":"initialized"}\n')
        process.stdin.flush()
        result = request(2, 'thread/start', {'cwd': '/workspace', 'approvalPolicy': 'never', 'sandbox': 'read-only'})
        thread_id = result['thread']['id']
        request(3, 'thread/archive', {'threadId': thread_id})
        (home / 'verification-thread').write_text(thread_id)
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    print('Codex migration, dispatch, thread creation, and archiving passed')


def main():
    repo = Path(__file__).resolve().parents[2]
    suffix = uuid.uuid4().hex
    container = f'ai-sandbox-codex-test-{suffix}'
    volumes = []
    created = False
    try:
        for kind in ['config', 'auth', 'data', 'cache']:
            name = f'{container}-{kind}'
            docker('volume', 'create', name)
            volumes.append(name)
        mounts = ['-v', f'{repo}:/repo:ro',
                  '-v', f'{repo}/docker/entrypoint.sh:/opt/ai-sandbox/entrypoint.sh:ro',
                  '-v', f'{repo}/docker/bootstrap:/opt/ai-sandbox/bootstrap:ro']
        for kind, name in zip(['config', 'auth', 'data', 'cache'], volumes):
            mounts.extend(['-v', f'{name}:/state/{kind}'])
        image = os.environ.get('AI_SANDBOX_TEST_IMAGE', 'ai-sandbox:latest')
        docker('run', '-d', '--name', container, *mounts, '--entrypoint', 'sleep', image, 'infinity')
        created = True
        print(docker('exec', container, 'python3', '/repo/tests/launcher/codex-state-persistence.py', '--inside', 'migrate'))
        print(docker('exec', container, 'python3', '/repo/tests/launcher/codex-runtime-ownership.py'))
        docker('rm', '-f', container)
        created = False
        docker('run', '-d', '--name', container, *mounts, '-e', 'LOCAL_UID=12345', '-e', 'LOCAL_GID=12345',
               '--entrypoint', 'bash', image,
               '/opt/ai-sandbox/entrypoint.sh', 'daemon')
        created = True
        docker('exec', container, '/opt/ai-sandbox/entrypoint.sh', 'codex', '--version')
        print(docker('exec', container, 'python3', '/repo/tests/launcher/codex-state-persistence.py', '--inside', 'verify'))
    finally:
        if created:
            docker('rm', '-f', container)
        for volume in volumes:
            docker('volume', 'rm', volume)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--inside':
        inside(sys.argv[2])
    else:
        main()
