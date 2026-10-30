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
    fixture = REPO / 'tests/launcher/fixtures/workspace-docker.py'
    for name, prefix in (('docker', ''), ('ai-sandbox', 'sandbox-invocation ')):
        if WINDOWS:
            (shim / (name + '.cmd')).write_text(f'@echo off\r\n"{sys.executable}" "{fixture}" {prefix}%*\r\n', encoding='ascii')
        else:
            (shim / name).write_text(f'#!/bin/sh\nexec "{sys.executable}" "{fixture}" {prefix}"$@"\n')
            (shim / name).chmod(0o755)
    state_path = root / 'docker.json'
    state_path.write_text(json.dumps({'calls': [], 'networks': []}))
    env = dict(os.environ, HOME=str(home), SANDBOX_TEST_STATE=str(state_path))
    env['PATH'] = str(shim) + os.pathsep + env['PATH']
    original_connection = None
    for name in ('checkout one', 'checkout two'):
        checkout = root / name
        shutil.copytree(REPO / 'examples/shared-sql', checkout)
        mapping = checkout / '.ai-sandbox/supplemental-folders.config'
        mapping.write_text('/existing-folder|existing-mount|ro\n')
        if WINDOWS:
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            code = 'Set-Variable HOME -Value ' + quote(home) + ' -Force; & ' + quote(checkout / 'dev/sandbox.ps1') + ' t3; exit $LASTEXITCODE'
            command = ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', code]
        else:
            command = ['bash', str(checkout / 'dev/sandbox.sh'), 't3']
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stdout + result.stderr
        directory = home / '.ai-sandbox/services/example-project-test-sql'
        connection = json.loads((directory / 'client/connection.json').read_text())
        assert connection['server'] == 'test-sql,1433' and connection['user'] == 'sandbox_test'
        assert len(connection['password']) == 52
        assert 'TEST_SQL_PASSWORD=' + connection['password'] in (directory / 'server.env').read_text()
        assert original_connection is None or connection == original_connection
        original_connection = connection
        lines = mapping.read_text().splitlines()
        assert lines[0] == '/existing-folder|existing-mount|ro'
        assert len(lines) == 2 and lines[1].endswith('|test-sql|ro')
    calls = json.loads(state_path.read_text())['calls']
    assert len([call for call in calls if call[:2] == ['network', 'create']]) == 1
    assert len([call for call in calls if call[0] == 'sandbox-invocation' and call[1:] == ['t3']]) == 2
    up = [call for call in calls if call[0] == 'compose' and 'up' in call]
    assert len(up) == 2 and all('--no-recreate' in call and '--wait' in call for call in up)
    assert len([call for call in calls if call[0] == 'compose' and 'init' in call]) == 2
    print('shared-sql-example passed (' + ('PowerShell' if WINDOWS else 'Bash') + ')')
