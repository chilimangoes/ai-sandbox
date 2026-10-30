"""Recover stale T3 startup metadata while holding T3's native ownership lock."""

import argparse
from datetime import datetime
import errno
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import sqlite3
import stat
import sys
from urllib.parse import urlsplit


class RecoveryBlocked(Exception):
    """The runtime record must be preserved because ownership is uncertain."""


def read_record(path: Path) -> tuple[bytes, tuple[int, int, int, int]]:
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > 65536:
            raise RecoveryBlocked("the runtime record is not a small regular file")
        return source.read(65537), (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)


def process_is_stale(pid: int, started_at: datetime) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True

    # Linux exposes process identity independently of the command name. Allow
    # two seconds for the whole-second boot timestamp and timestamp rounding.
    process_path = Path("/proc") / str(pid)
    details = (process_path / "stat").read_text()
    fields = details.rpartition(")")[2].split()
    if fields[0] in ("Z", "X"):
        return True
    os.readlink(process_path / "exe")
    start_ticks = int(fields[19])
    boot_time = next(
        int(line.split()[1])
        for line in Path("/proc/stat").read_text().splitlines()
        if line.startswith("btime ")
    )
    process_started = boot_time + start_ticks / os.sysconf("SC_CLK_TCK")
    return process_started > started_at.timestamp() + 2


def check_listener(port: int) -> None:
    for host in ("127.0.0.1", "::1"):
        try:
            with socket.create_connection((host, port), timeout=0.5):
                raise RecoveryBlocked("the recorded port has a listener")
        except OSError as error:
            if error.errno not in (errno.ECONNREFUSED, errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL):
                raise


def recover(base_dir: Path, launcher: Path) -> None:
    state_dir = base_dir / "userdata"
    record_path = state_dir / "server-runtime.json"
    try:
        try:
            original = read_record(record_path)
        except FileNotFoundError:
            return

        package = json.loads((launcher.resolve().parent.parent / "package.json").read_text())
        # This recovery uses the ownership protocol shipped in stable T3 0.1.x.
        # Other releases need their locking protocol checked before cleanup.
        if not re.fullmatch(r"0\.1\.\d+", package["version"]):
            raise RecoveryBlocked("this T3 version has an unverified ownership protocol")

        lock_path = state_dir / "server-owner.sqlite"
        try:
            descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        except FileExistsError:
            descriptor = os.open(lock_path, os.O_RDWR | os.O_NOFOLLOW)
        else:
            # Normal launches enter as root, then run T3 as the mapped user.
            # Give a newly created lock the same owner as T3's state directory.
            if os.geteuid() == 0:
                owner = state_dir.stat()
                os.fchown(descriptor, owner.st_uid, owner.st_gid)
        with os.fdopen(descriptor, "rb") as lock_file:
            lock_info = os.fstat(lock_file.fileno())
            if not stat.S_ISREG(lock_info.st_mode):
                raise RecoveryBlocked("the ownership lock is not a regular file")
            db = sqlite3.connect(lock_path, timeout=0, isolation_level=None)
            try:
                # T3 holds this exact transaction for its server's lifetime.
                # Releasing it before launch lets T3 acquire ownership itself;
                # concurrent starts are arbitrated by the same native lock.
                db.execute("BEGIN EXCLUSIVE")
                current_lock = lock_path.stat()
                if (current_lock.st_dev, current_lock.st_ino) != (lock_info.st_dev, lock_info.st_ino):
                    raise RecoveryBlocked("the ownership lock changed during verification")
                if read_record(record_path) != original:
                    raise RecoveryBlocked("the runtime record changed during verification")

                record = json.loads(original[0])
                pid, port = record["pid"], record["port"]
                if record["version"] != 1 or type(pid) is not int or not 0 < pid <= 2147483647:
                    raise RecoveryBlocked("the runtime record has an unsupported process identity")
                if type(port) is not int or not 0 < port < 65536:
                    raise RecoveryBlocked("the runtime record has an invalid port")
                origin = urlsplit(record["origin"])
                if origin.scheme not in ("http", "https") or origin.port != port:
                    raise RecoveryBlocked("the recorded server address is unsupported")
                if origin.hostname != "localhost" and not ipaddress.ip_address(origin.hostname).is_loopback:
                    raise RecoveryBlocked("the recorded server address is not local")
                started_at = datetime.fromisoformat(record["startedAt"].replace("Z", "+00:00"))
                if started_at.tzinfo is None:
                    raise RecoveryBlocked("the recorded start time has no time zone")
                if not process_is_stale(pid, started_at):
                    raise RecoveryBlocked("the recorded process may still be the T3 server")
                check_listener(port)
                if read_record(record_path) != original or not process_is_stale(pid, started_at):
                    raise RecoveryBlocked("the runtime record or process changed during verification")
                record_path.unlink()
                print(f"Removed stale T3 runtime record (PID {pid}).", flush=True)
            finally:
                db.close()
    except (OSError, sqlite3.Error, ValueError, KeyError, TypeError, IndexError, StopIteration) as error:
        raise RecoveryBlocked(f"ownership could not be verified: {error}") from error


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-dir", type=Path, required=True)
    parser.add_argument("--launcher", type=Path, default=Path("/opt/ai-sandbox/bin/t3"))
    arguments = parser.parse_args()
    try:
        recover(arguments.base_dir.expanduser(), arguments.launcher)
    except RecoveryBlocked as error:
        print(f"T3 startup record preserved: {error}. Startup stopped.", file=sys.stderr)
        sys.exit(1)
