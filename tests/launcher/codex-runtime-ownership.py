"""Run as root in a disposable sandbox image to check Codex daemon ownership."""
from pathlib import Path
import os
import pwd
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'docker/entrypoint.sh').read_text()
function = re.search(r'(?ms)^set_runtime_ownership\(\) \{.*?^\}', source).group()
sandbox = pwd.getpwnam('sandbox')
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    home = root / 'home'
    state = root / 'state'
    session = home / '.codex/sessions'
    control = home / '.codex/app-server-control'
    daemon = home / '.codex/app-server-daemon'
    for directory in (state, session, control, daemon):
        directory.mkdir(parents=True)
    (control / 'startup.lock').touch()
    function = function.replace('/home/sandbox', str(home)).replace('/state', str(state))
    for _ in range(2):
        subprocess.run(['bash', '-euc', function + '\nset_runtime_ownership'], check=True)
        assert control.stat().st_uid == 0
        assert daemon.stat().st_uid == 0
        assert (control / 'startup.lock').stat().st_uid == 0
        assert session.stat().st_uid == sandbox.pw_uid
        assert state.stat().st_uid == sandbox.pw_uid
print('codex-runtime-ownership passed')
