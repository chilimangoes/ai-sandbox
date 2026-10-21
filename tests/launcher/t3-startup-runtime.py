"""Run the real T3 CLI in a disposable container, without inference requests."""

import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time


base = Path("/state/data/t3")
record_path = base / "userdata/server-runtime.json"
record_path.parent.mkdir(parents=True, exist_ok=True)
cli = "/opt/ai-sandbox/bin/t3"
environment = {**os.environ, "T3CODE_HOME": str(base), "HOME": "/home/sandbox"}
subprocess.run([cli, "--version"], env=environment, check=True)
subprocess.run(["chown", "-R", "sandbox:sandbox", str(base)], check=True)


def stop(process, sig=signal.SIGTERM):
    if process.poll() is None:
        os.killpg(process.pid, sig)
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)


def start(log):
    previous = record_path.read_bytes() if record_path.exists() else None
    log.seek(0, os.SEEK_END)
    log_start = log.tell()
    process = subprocess.Popen(
        ["/opt/ai-sandbox/entrypoint.sh", "t3"], env=environment,
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
    )
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        if process.poll() is not None:
            log.seek(log_start)
            reasons = [
                line for line in log.read().decode(errors="replace").splitlines()
                if line.startswith("T3 startup record preserved:")
            ]
            raise AssertionError(f"T3 exited during startup: {process.returncode}; {reasons}")
        try:
            raw = record_path.read_bytes()
            record = json.loads(raw)
            if raw != previous and "ownerId" in record and Path(f'/proc/{record["pid"]}').stat().st_uid == 12345:
                return process, record
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    stop(process)
    raise AssertionError("T3 did not publish a runtime record within 25 seconds")


protected = [base / "recovery-sentinel", Path("/state/auth/recovery-sentinel")]
for path in protected:
    path.write_bytes(b"preserve me")

with subprocess.Popen(["sleep", "120"]) as unrelated, tempfile.TemporaryFile() as log:
    server = None
    try:
        record_path.write_text(json.dumps({
            "version": 1, "pid": unrelated.pid, "port": 3773,
            "origin": "http://127.0.0.1:3773", "startedAt": "2000-01-01T00:00:00Z",
        }))
        server, record = start(log)
        assert unrelated.poll() is None
        print("PASS: real T3 starts as UID 12345 after recovery from a reused PID", flush=True)

        before = record_path.read_bytes()
        result = subprocess.run(
            ["/opt/ai-sandbox/entrypoint.sh", "t3"], env=environment,
            capture_output=True, text=True, timeout=8,
        )
        assert result.returncode != 0 and "preserved" in result.stdout + result.stderr
        assert record_path.read_bytes() == before and server.poll() is None
        print("PASS: a second launcher preserves the running server and its record", flush=True)

        with sqlite3.connect(record_path.parent / "server-owner.sqlite", timeout=0) as db:
            try:
                db.execute("BEGIN EXCLUSIVE")
            except sqlite3.OperationalError as error:
                assert "locked" in str(error)
            else:
                raise AssertionError("The real T3 server does not hold the expected ownership lock")

        # A direct CLI start can race after recovery releases the lock. Hide
        # discovery metadata to exercise its ownership check past the PID guard.
        hidden = record_path.with_suffix(".test-backup")
        record_path.rename(hidden)
        try:
            result = subprocess.run(
                ["runuser", "-u", "sandbox", "--", "env", "HOME=/home/sandbox",
                 f"T3CODE_HOME={base}", cli, "start", "--no-browser", "--host", "0.0.0.0",
                 "--port", "3773", "--base-dir", str(base)],
                capture_output=True, text=True, timeout=12,
            )
            assert result.returncode != 0 and "already owns" in result.stdout + result.stderr
        finally:
            hidden.rename(record_path)
        assert record_path.read_bytes() == before and server.poll() is None
        print("PASS: native ownership blocks a direct CLI start beyond the PID guard", flush=True)

        # runuser can place children in another session. Kill the recorded
        # server itself to model the server death caused by container removal.
        os.kill(record["pid"], signal.SIGKILL)
        stop(server, signal.SIGKILL)
        server = None
        server, _ = start(log)
        for path in protected:
            assert path.read_bytes() == b"preserve me"
        print("PASS: real T3 restarts after SIGKILL and preserves persistent data", flush=True)
    finally:
        if server is not None:
            stop(server)
        unrelated.terminate()
