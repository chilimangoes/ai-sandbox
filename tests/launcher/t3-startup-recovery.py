"""Exercise recovery against real processes, listeners, and SQLite ownership locks."""

import importlib.util
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "t3_startup", Path(__file__).resolve().parents[2] / "docker/t3-startup.py"
)
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.state = self.base / "userdata"
        self.state.mkdir()
        self.record = self.state / "server-runtime.json"
        self.launcher = self.base / "package/bin/t3.mjs"
        self.launcher.parent.mkdir(parents=True)
        self.launcher.write_text("")
        (self.launcher.parent.parent / "package.json").write_text(
            json.dumps({"version": "0.1.1"})
        )
        self.write_record()

    def write_record(self, **overrides):
        self.record.write_text(json.dumps({
            "version": 1,
            "pid": 2147483647,
            "port": 3773,
            "origin": "http://127.0.0.1:3773",
            "startedAt": "2000-01-01T00:00:00.000Z",
            **overrides,
        }))

    def recover(self):
        startup.recover(self.base, self.launcher)

    def assert_preserved(self):
        before = self.record.read_bytes()
        with self.assertRaises(startup.RecoveryBlocked):
            self.recover()
        self.assertEqual(self.record.read_bytes(), before)

    def test_missing_pid_removes_only_runtime_record(self):
        protected = ["sessions.db", "settings.json", "server-owner.sqlite"]
        for name in protected[:2]:
            (self.state / name).write_bytes(b"preserve me")
        with sqlite3.connect(self.state / protected[2]) as db:
            db.execute("CREATE TABLE sentinel (value TEXT)")
            db.execute("INSERT INTO sentinel VALUES ('preserve me')")
        self.recover()
        self.assertFalse(self.record.exists())
        for name in protected[:2]:
            self.assertEqual((self.state / name).read_bytes(), b"preserve me")
        with sqlite3.connect(self.state / protected[2]) as db:
            self.assertEqual(db.execute("SELECT value FROM sentinel").fetchone()[0], "preserve me")

    def test_reused_pid_is_recovered_without_stopping_process(self):
        with subprocess.Popen(["sleep", "30"]) as process:
            try:
                self.write_record(pid=process.pid)
                self.recover()
                self.assertFalse(self.record.exists())
                self.assertIsNone(process.poll())
            finally:
                process.terminate()

    def test_potentially_live_pid_is_preserved(self):
        self.write_record(pid=os.getpid(), startedAt="2999-01-01T00:00:00Z")
        self.assert_preserved()

    def test_exited_process_awaiting_reaping_is_stale(self):
        with subprocess.Popen(["true"]) as process:
            os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT)
            self.write_record(pid=process.pid)
            self.recover()
            self.assertFalse(self.record.exists())

    def test_held_native_ownership_lock_preserves_stale_record(self):
        with sqlite3.connect(self.state / "server-owner.sqlite", isolation_level=None) as db:
            db.execute("BEGIN EXCLUSIVE")
            self.assert_preserved()

    def test_listener_preserves_stale_record(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            self.write_record(port=port, origin=f"http://127.0.0.1:{port}")
            self.assert_preserved()

    def test_permission_error_preserves_record(self):
        with patch.object(startup, "process_is_stale", side_effect=PermissionError):
            self.assert_preserved()

    def test_network_timeout_preserves_record(self):
        with patch.object(startup.socket, "create_connection", side_effect=TimeoutError):
            self.assert_preserved()

    def test_changed_record_is_preserved(self):
        original_probe = startup.process_is_stale

        def replace_record(pid, started_at):
            self.write_record(pid=os.getpid(), startedAt="2999-01-01T00:00:00Z")
            return original_probe(pid, started_at)

        with patch.object(startup, "process_is_stale", side_effect=replace_record):
            with self.assertRaises(startup.RecoveryBlocked):
                self.recover()
        self.assertEqual(json.loads(self.record.read_text())["pid"], os.getpid())

    def test_unsupported_protocol_preserves_record(self):
        for version in ("0.0.42", "0.2.0", "0.1.2-beta.1"):
            with self.subTest(version=version):
                (self.launcher.parent.parent / "package.json").write_text(json.dumps({"version": version}))
                self.assert_preserved()

    def test_malformed_record_is_preserved(self):
        self.record.write_text("{broken")
        self.assert_preserved()

    def test_symlink_is_preserved(self):
        target = self.state / "other.json"
        self.record.rename(target)
        self.record.symlink_to(target)
        self.assert_preserved()
        self.assertTrue(target.exists())

    def test_missing_record_requires_no_recovery(self):
        self.record.unlink()
        self.recover()
        self.assertFalse((self.state / "server-owner.sqlite").exists())


if __name__ == "__main__":
    unittest.main()
