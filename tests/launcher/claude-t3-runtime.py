"""Exercise T3's version and stream-JSON probes through the installed shim."""

import concurrent.futures
import json
from pathlib import Path
import subprocess


failures = []

# The parent entrypoint already initialized this disposable container. Make
# repeated initialization fail deterministically instead of relying on a race.
chown = Path("/usr/local/bin/chown")
chown.write_text("#!/bin/sh\necho 'Unexpected nested initialization' >&2\nexit 91\n")
chown.chmod(0o755)


def version_probe(_):
    return subprocess.run(
        ["claude", "--version"], capture_output=True, text=True, timeout=8
    )


try:
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(version_probe, range(24)))
    rejected = [r for r in results if r.returncode or "Claude Code" not in r.stdout]
    if rejected:
        failures.append(f"Version probe: {len(rejected)}/24 failed: {rejected[0].stderr.strip()}")
    else:
        print("PASS: 24 concurrent nested version probes")
finally:
    chown.unlink()

# No user message is sent, so this checks the same IPC connection as T3's
# capabilities probe without making an inference request.
request_id = "sandbox-t3-regression"
request = json.dumps({
    "type": "control_request",
    "request_id": request_id,
    "request": {"subtype": "initialize"},
}) + "\n"
result = subprocess.run(
    ["runuser", "-u", "sandbox", "--", "env", "HOME=/home/sandbox",
     "claude", "--input-format", "stream-json", "--output-format",
     "stream-json", "--verbose", "--print"],
    input=request, capture_output=True, text=True, timeout=15,
)
messages = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
if result.returncode or not any(
    m.get("type") == "control_response"
    and m.get("response", {}).get("request_id") == request_id
    for m in messages
):
    failures.append("Stream-JSON probe: Claude did not acknowledge initialization on stdin")
else:
    print("PASS: stream-JSON initialization through the Claude wrapper")

if failures:
    raise SystemExit("\n".join(failures))
