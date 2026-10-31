"""Real Docker check: opening another session must preserve a custom-image container.

Requires the installed ai-sandbox:latest image. Uses only disposable test resources.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]


def docker(*args, check=True):
    return subprocess.run(['docker', *args], capture_output=True, text=True, check=check, timeout=120)


def main():
    base_before = json.loads(docker('image', 'inspect', 'ai-sandbox:latest').stdout)[0]['Id']
    with tempfile.TemporaryDirectory(prefix='sandbox-session-check-') as temporary:
        root = Path(temporary).resolve()
        workspace = root / 'workspace'
        config = workspace / '.ai-sandbox'
        host_state = root / 'host-state'
        config.mkdir(parents=True)
        host_state.mkdir()
        dockerfile = config / 'Dockerfile'
        dockerfile.write_text('ARG AI_SANDBOX_BASE_IMAGE=ai-sandbox:latest\nFROM ${AI_SANDBOX_BASE_IMAGE}\nRUN echo first > /opt/ai-sandbox/session-test\n')
        containers = set()
        images = set()
        tags = set()
        volumes = set()

        def launch(command):
            if os.name == 'nt':
                quote = lambda value: "'" + str(value).replace("'", "''") + "'"
                script = 'Set-Variable HOME -Value ' + quote(host_state) + ' -Force; & ' + quote(REPO / 'bin/ai-sandbox.ps1') + ' ' + command
                args = ['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', script]
                env = None
            else:
                args = ['bash', str(REPO / 'bin/ai-sandbox'), command]
                env = dict(os.environ, HOME=str(host_state))
            result = subprocess.run(args, cwd=workspace, env=env, capture_output=True, text=True, timeout=180)
            assert result.returncode == 0, result.stdout + result.stderr
            return result.stdout + result.stderr

        def inspect():
            ids = docker('ps', '-aq', '--filter', 'label=ai-sandbox.workspace=' + str(workspace)).stdout.split()
            assert len(ids) == 1, 'Expected exactly one isolated workspace container'
            info = json.loads(docker('inspect', ids[0]).stdout)[0]
            containers.add(info['Id'])
            tags.add(info['Config']['Image'])
            image = json.loads(docker('image', 'inspect', info['Config']['Image']).stdout)[0]
            images.add(image['Id'])
            volumes.update(mount['Name'] for mount in info['Mounts'] if mount['Type'] == 'volume')
            return info, image

        try:
            launch('trust')
            launch('reset-config')
            first, first_image = inspect()
            docker('exec', '-d', first['Id'], '/bin/sleep', '300')
            output = launch('reset-config')
            second, second_image = inspect()
            print('First image:', first_image['Id'])
            print('Second image:', second_image['Id'])
            print('First container image:', first['Image'])
            print('Runtime configuration unchanged:', first_image['Config'] == second_image['Config'])
            print('Filesystem layers unchanged:', first_image['RootFS'] == second_image['RootFS'])
            print('Launch settings unchanged:', first['Config']['Labels'] == second['Config']['Labels'])
            print('Base image unchanged:', base_before == json.loads(docker('image', 'inspect', 'ai-sandbox:latest').stdout)[0]['Id'])
            assert second['Id'] == first['Id'], 'Opening another session replaced the existing container after an unchanged cached build'
            assert 'Replacing the workspace container' not in output
            dockerfile.write_text(dockerfile.read_text().replace('echo first', 'echo second'))
            launch('reset-config')
            changed, _ = inspect()
            assert changed['Id'] != first['Id'], 'Changed image must replace the container'
            assert docker('exec', changed['Id'], 'cat', '/opt/ai-sandbox/session-test').stdout.strip() == 'second'
            print('custom-image-sessions passed: cached builds preserve sessions; changed images replace the container')
        finally:
            # Discover resources even if a launch fails before the first inspection.
            ids = docker('ps', '-aq', '--filter', 'label=ai-sandbox.workspace=' + str(workspace), check=False).stdout.split()
            if ids:
                for info in json.loads(docker('inspect', *ids).stdout):
                    tags.add(info['Config']['Image'])
                    volumes.update(mount['Name'] for mount in info['Mounts'] if mount['Type'] == 'volume')
                containers.update(ids)
            if containers:
                docker('rm', '-f', *containers, check=False)
            for volume in volumes:
                docker('volume', 'rm', volume, check=False)
            for tag in tags:
                docker('image', 'rm', tag, check=False)
            for image in images:
                docker('image', 'rm', image, check=False)


if __name__ == '__main__':
    main()
