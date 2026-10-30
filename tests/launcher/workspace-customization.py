"""Exercise both host launchers with Docker replaced by a stateful fixture."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
WINDOWS = os.name == 'nt'


def main():
    with tempfile.TemporaryDirectory(prefix='sandbox-launcher-') as temporary:
        root = Path(temporary)
        home = root / 'home'
        workspace = root / 'project with spaces'
        config = workspace / '.ai-sandbox'
        shim = root / 'bin'
        for path in (home, config, shim):
            path.mkdir(parents=True)
        fixture = REPO / 'tests/launcher/fixtures/workspace-docker.py'
        if WINDOWS:
            (shim / 'docker.cmd').write_text(f'@echo off\r\n"{sys.executable}" "{fixture}" %*\r\n', encoding='ascii')
        else:
            shutil.copy(fixture, shim / 'docker')
            (shim / 'docker').chmod(0o755)
        state_path = root / 'docker.json'
        state_path.write_text(json.dumps({
            'calls': [], 'images': {'ai-sandbox:latest': 'sha256:' + 'a' * 64},
            'containers': {}, 'volumes': [], 'networks': ['project-test', 'second-network'],
        }))
        env = dict(os.environ, HOME=str(home), SANDBOX_TEST_STATE=str(state_path))
        env['PATH'] = str(shim) + os.pathsep + env['PATH']

        def command(*arguments):
            if WINDOWS:
                quote = lambda value: "'" + str(value).replace("'", "''") + "'"
                invocation = f"Set-Variable HOME -Value {quote(home)} -Force; & {quote(REPO / 'bin/ai-sandbox.ps1')} "
                invocation += ' '.join(quote(arg) for arg in arguments)
                invocation += '; exit $LASTEXITCODE'
                return ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', invocation]
            return ['bash', str(REPO / 'bin/ai-sandbox'), *arguments]

        def launch(*arguments, success=True):
            result = subprocess.run(command(*arguments), cwd=workspace, env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
            assert (result.returncode == 0) == success, result.stdout
            return result.stdout

        def state():
            return json.loads(state_path.read_text())

        def calls():
            return state()['calls']

        def update(**values):
            current = state()
            current.update(values)
            state_path.write_text(json.dumps(current))

        # Standard workspaces keep using the shared base image.
        launch('doctor')
        initial_run = next(call for call in calls() if call[0] == 'run')
        assert initial_run[-2] == 'ai-sandbox:latest'
        assert not any(call[0] == 'build' for call in calls())
        original_volumes = state()['volumes'][:]

        # Tool flags belong to T3, including flags that also name launcher options.
        for arguments in [('t3', 'auth', 'session', 'list', '--json'),
                          ('t3', '--help'), ('t3', 'future-command', '--update')]:
            count = len(calls())
            launch(*arguments)
            invoked = calls()[count:]
            execution = next(call for call in invoked if call[0] == 'exec')
            assert execution[-len(arguments):] == list(arguments), execution
            assert '-i' in execution and '-it' not in execution, execution
            assert not any(call[0] == 'build' for call in invoked)

        (config / 'Dockerfile').write_text('ARG AI_SANDBOX_BASE_IMAGE\nFROM ${AI_SANDBOX_BASE_IMAGE}\nCOPY install.sh /tmp/install.sh\n')
        (config / 'install.sh').write_text('echo project dependencies\n')
        assert 'ai-sandbox trust' in launch('doctor', success=False)
        assert not any(call[0] == 'build' for call in calls())
        launch('trust')
        launch('doctor')
        builds = [call for call in calls() if call[0] == 'build']
        assert len(builds) == 1 and '--pull' not in builds[0] and '--no-cache' not in builds[0]
        assert Path(builds[0][-1]).resolve() == config.resolve(), repr(builds[0])
        assert 'AI_SANDBOX_BASE_IMAGE=ai-sandbox-base:' + 'a' * 64 in builds[0]
        assert state()['volumes'] == original_volumes
        runs = len([call for call in calls() if call[0] == 'run'])
        launch('doctor')
        assert len([call for call in calls() if call[0] == 'run']) == runs

        # Helper edits are picked up under the existing workspace approval.
        (config / 'install.sh').write_text('echo updated dependencies\n')
        launch('doctor')
        assert len([call for call in calls() if call[0] == 'run']) == runs + 1

        # Failed builds preserve both the previous container and persisted volumes.
        update(fail_build=True)
        before = state()['containers']
        assert 'build failed' in launch('--rebuild', 'doctor', success=False)
        assert state()['containers'] == before and state()['volumes'] == original_volumes
        update(fail_build=False)

        credentials = root / 'shared credentials'
        credentials.mkdir()
        (config / 'supplemental-folders.config').write_text(f'{credentials}|test-sql|ro\n')
        settings = 'network=project-test\nnetwork=second-network\nport=05001\nport=8080\nenv=PROJECT_SQL_CONFIG=/supplemental/test-sql/connection.json\nenv=PROJECT_TEXT=value with spaces=and equals\nenv=EMPTY=\n'
        (config / 'workspace.config').write_bytes(b'\xef\xbb\xbf' + settings.replace('\n', '\r\n').encode())
        launch('doctor')
        run = [call for call in calls() if call[0] == 'run'][-1]
        assert run.count('--network') == 2
        assert 'project-test' in run and 'second-network' in run
        assert any(value.endswith(':5001:5001') for value in run)
        assert len([value for value in run if value.endswith(':8080:8080')]) == 1
        assert 'PROJECT_TEXT=value with spaces=and equals' in run and 'EMPTY=' in run
        assert any(value.endswith(':/supplemental/test-sql:ro') and Path(value[:-len(':/supplemental/test-sql:ro')]).resolve() == credentials.resolve() for value in run)
        runs = len([call for call in calls() if call[0] == 'run'])
        (config / 'workspace.config').write_text('\n'.join(reversed(settings.splitlines())) + '\n')
        launch('doctor')
        assert len([call for call in calls() if call[0] == 'run']) == runs
        (config / 'workspace.config').write_text(settings.replace('env=EMPTY=', 'env=EMPTY=changed'))
        image = next(iter(state()['containers'].values()))['image']
        launch('doctor')
        assert len([call for call in calls() if call[0] == 'run']) == runs + 1
        assert next(iter(state()['containers'].values()))['image'] == image

        # Missing networks and invalid settings fail before builds or replacement.
        for text in ('network=missing\n', 'port=65536\n', 'port=5000\nport=05000\n', 'env=HOME=/tmp\n',
                     'network=host\n', 'env=1INVALID=value\n', 'unknown=value\n'):
            (config / 'workspace.config').write_text(text)
            count = len(calls())
            launch('doctor', success=False)
            assert not any(call[0] in ('build', 'rm', 'run') for call in calls()[count:])

        # Maintenance and revocation work even with broken definitions and mounts.
        (config / 'supplemental-folders.config').write_text('/missing/folder|bad|ro\n')
        count = len(calls())
        launch('stop')
        launch('rm')
        launch('untrust')
        assert not any(call[0] in ('build', 'run', 'network') for call in calls()[count:])
        launch('doctor', success=False)
        launch('trust')
        (config / 'workspace.config').unlink()
        (config / 'supplemental-folders.config').unlink()
        launch('--update', 'doctor')
        builds = [call for call in calls() if call[0] == 'build'][-2:]
        assert '--pull' in builds[0] and '--no-cache' in builds[0]
        assert '--pull' not in builds[1] and '--no-cache' in builds[1]

        # Parallel launches serialize build and container creation, then release locks.
        launch('rm')
        update(build_delay=0.3)
        count = len(calls())
        processes = [subprocess.Popen(command('doctor'), cwd=workspace, env=env, stdin=subprocess.DEVNULL,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) for _ in range(2)]
        for process in processes:
            output, _ = process.communicate(timeout=45)
            assert process.returncode == 0, output
        assert len([call for call in calls()[count:] if call[0] == 'run']) == 1
        assert not any(call[:2] == ['volume', 'rm'] for call in calls())
        print('workspace-customization passed (' + ('PowerShell' if WINDOWS else 'Bash') + ')')


if __name__ == '__main__':
    main()
