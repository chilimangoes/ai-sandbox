"""Verify host bootstrap reuse and generated mounts without starting SQL Server."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
WINDOWS = os.name == 'nt'

with tempfile.TemporaryDirectory(prefix='sandbox-sql-example-') as temporary:
    root = Path(temporary)
    home = root / 'home'
    shim = root / 'bin'
    home.mkdir()
    shim.mkdir()
    fixture = REPO / 'tests/launcher/fixtures/shared-sql-docker.py'
    for name, prefix in (('docker', ''), ('ai-sandbox', 'sandbox-invocation ')):
        if WINDOWS:
            (shim / (name + '.cmd')).write_text(f'@echo off\r\n"{sys.executable}" "{fixture}" {prefix}%*\r\n', encoding='ascii')
        else:
            (shim / name).write_text(f'#!/bin/sh\nexec "{sys.executable}" "{fixture}" {prefix}"$@"\n')
            (shim / name).chmod(0o755)
    state_path = root / 'docker.json'
    state_path.write_text(json.dumps({'calls': [], 'networks': [], 'containers': {}, 'leases': 0}))
    env = dict(os.environ, HOME=str(home), SANDBOX_TEST_STATE=str(state_path))
    env['PATH'] = str(shim) + os.pathsep + env['PATH']

    def bootstrap_command(checkout):
        if WINDOWS:
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            code = 'Set-Variable HOME -Value ' + quote(home) + ' -Force; & ' + quote(checkout / 'dev/sandbox.ps1') + ' t3; exit $LASTEXITCODE'
            return ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', code]
        return ['bash', str(checkout / 'dev/sandbox.sh'), 't3']

    original_connection = None
    checkouts = []
    for name in ('checkout one', 'checkout two'):
        checkout = root / name
        shutil.copytree(REPO / 'examples/shared-sql', checkout)
        mapping = checkout / '.ai-sandbox/supplemental-folders.config'
        mapping.write_text(mapping.read_text() + '/existing-folder|existing-mount|ro\n')
        original_mapping = mapping.read_text()
        checkouts.append(checkout)
        command = bootstrap_command(checkout)
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, result.stdout + result.stderr
        directory = checkout / '.local/test-sql'
        connection = json.loads((directory / 'client/connection.json').read_text())
        assert connection['server'] == 'test-sql,1433' and connection['user'] == 'sandbox_test'
        assert len(connection['password']) == 52
        assert 'TEST_SQL_PASSWORD=' + connection['password'] in (directory / 'server.env').read_text()
        assert original_connection is None or connection == original_connection
        original_connection = connection
        assert mapping.read_text() == original_mapping
        assert not (home / '.ai-sandbox/services').exists()
    connection_path = checkouts[-1] / '.local/test-sql/client/connection.json'
    connection_path.write_text('{}')
    (checkouts[-1] / '.local/test-sql/server.env').write_text('stale local credentials')
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(connection_path.read_text()) == original_connection
    current = json.loads(state_path.read_text())
    current['fail_init'] = True
    state_path.write_text(json.dumps(current))
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=90)
    assert result.returncode != 0
    current = json.loads(state_path.read_text())
    assert list(current['containers']) == ['sql-1'], 'Bootstrap lease must be released on failure'
    calls = json.loads(state_path.read_text())['calls']
    assert len([call for call in calls if call[:2] == ['network', 'create']]) == 1
    assert len([call for call in calls if call[0] == 'sandbox-invocation' and call[1:] == ['t3']]) == 3
    up = [call for call in calls if call[0] == 'compose' and 'up' in call]
    assert len(up) == 4 and all('--no-recreate' in call and '--wait' in call for call in up)
    assert len([call for call in calls if call[0] == 'compose' and 'init' in call]) == 4

    # Independent checkouts race to create one shared instance and receive matching credentials.
    for checkout in checkouts:
        (checkout / '.local/test-sql/server.env').unlink()
    state_path.write_text(json.dumps({'calls': [], 'networks': [], 'containers': {}, 'leases': 0}))
    processes = [subprocess.Popen(bootstrap_command(checkout), env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, text=True) for checkout in checkouts]
    for process in processes:
        output, _ = process.communicate(timeout=90)
        assert process.returncode == 0, output
    connections = [json.loads((checkout / '.local/test-sql/client/connection.json').read_text()) for checkout in checkouts]
    assert connections[0] == connections[1]
    current = json.loads(state_path.read_text())
    assert current['sql_creations'] == 1 and current['leases'] == 2
    assert list(current['containers']) == ['sql-1']
    print('shared-sql-example passed (' + ('PowerShell' if WINDOWS else 'Bash') + ')')
