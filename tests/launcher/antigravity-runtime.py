"""Check CLI access and state persistence across fresh containers."""

import json
import os
from pathlib import Path
import subprocess
import sys

runtime = Path("/home/sandbox/.gemini/antigravity-cli")
config = Path("/state/config/antigravity/settings.json")
token = Path("/state/auth/antigravity/antigravity-oauth-token")
assert runtime.is_symlink()
assert runtime.resolve() == Path("/state/data/antigravity/home")
assert (runtime / "settings.json").resolve() == config
assert (runtime / "antigravity-oauth-token").resolve() == token

environment = {**os.environ, "HOME": "/home/sandbox", "AI_SANDBOX_INITIALIZED": "1"}
version = subprocess.run(
    ["runuser", "-u", "sandbox", "--", "env", "HOME=/home/sandbox", "agy", "--version"],
    check=True, capture_output=True, text=True, env=environment,
)
assert version.stdout.strip(), "Expected CLI version output as the sandbox user"

if sys.argv[1] == "seed":
    subprocess.run(
        ["runuser", "-u", "sandbox", "--", "python3", "-c", """
from pathlib import Path
root = Path('/home/sandbox/.gemini/antigravity-cli')
(root / 'settings.json').write_text('{"trustedWorkspaces":["/workspace"]}')
(root / 'antigravity-oauth-token').write_text('test-token')
(root / 'conversations').mkdir()
(root / 'conversations' / 'test-session').write_text('test-session')
"""], check=True, env=environment,
    )
else:
    assert json.loads(config.read_text())["trustedWorkspaces"] == ["/workspace"]
    assert token.read_text() == "test-token"
    assert (runtime / "conversations/test-session").read_text() == "test-session"
    assert token.stat().st_uid == config.stat().st_uid == 1000

# Invoke the same public shim used by a shell or T3, and observe its user.
binary = Path("/opt/ai-sandbox/bin/agy")
binary.unlink()
binary.write_text('#!/bin/sh\nid -u\nprintf "%s\\n" "$HOME"\n')
binary.chmod(0o755)
result = subprocess.run(["agy"], check=True, capture_output=True, text=True, env=environment)
assert result.stdout.splitlines() == ["1000", "/home/sandbox"], result.stdout
print(f"Antigravity {sys.argv[1]} passed")
