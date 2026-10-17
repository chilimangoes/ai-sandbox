#!/usr/bin/env python3
"""Run the Linux launcher matrix on an explicitly selected native engine."""
import argparse
import hashlib
import json
import os
import pty
from pathlib import Path
import re
import shutil
import select
import signal
import subprocess
import tempfile
import time
import urllib.request
import uuid


parser = argparse.ArgumentParser()
parser.add_argument("--engine", choices=("docker", "podman"), required=True)
parser.add_argument("--run-live", action="store_true", required=True)
parser.add_argument("--evidence-directory", type=Path, required=True)
parser.add_argument("--require-selinux-enforcing", action="store_true")
args = parser.parse_args()
if args.require_selinux_enforcing and args.engine != "podman":
    parser.error("SELinux acceptance requires native rootless Podman.")
repo = Path(__file__).resolve().parents[2]
launcher_path = repo / "bin/ai-sandbox"
evidence = args.evidence_directory.resolve() / (args.engine + "-" + uuid.uuid4().hex)
evidence.mkdir(parents=True)
task_root = Path(tempfile.mkdtemp(prefix="ai-sandbox-ticket04-live-"))
workspaces = [task_root / "first workspace with spaces", task_root / "second workspace with spaces"]
ro, rw = task_root / "read only", task_root / "read write"
for path in [*workspaces, ro, rw]:
    path.mkdir(mode=0o755)
(ro / "source.txt").write_text("read-only-source")
for workspace in workspaces:
    (workspace / ".ai-sandbox").mkdir()
    (workspace / ".ai-sandbox/supplemental-folders.config").write_text(f"{ro}|read only|ro\n{rw}|read write|rw\n")
ports = (3773, 9899, 6767, 8080, 3000)
names, addresses, workspace_paths, volumes = [], [], [], []
for workspace in workspaces:
    digest = hashlib.sha256(str(workspace).lower().encode()).hexdigest()
    slug = re.sub("[^a-z0-9]+", "-", workspace.name.lower()).strip("-")
    name = f"ai-sandbox-{slug}-{digest[:12]}"
    names.append(name)
    addresses.append(f"127.{64 + int(digest[:2], 16) % 64}.{int(digest[2:4], 16)}.{1 + int(digest[4:6], 16) % 254}")
    workspace_paths.append("/workspace/" + slug)
    volumes.append([name + "-" + kind for kind in ("config", "auth", "data", "cache")])
checks, children = [], []
sequence = 0
identity_tag = None
result = {"Result": "failed", "Engine": args.engine, "Checks": checks, "WorkspaceRoot": str(task_root)}


def redact_text(value):
    patterns = (
        (r'''(?i)((?:#|[?&])token=)([^\s"'<>\\]+)''', r'\1<REDACTED>'),
        (r'''(?i)((?:bootstrap[_ -]?token|pairing[_ -]?token|access[_ -]?token)\s*[:=]\s*)([^\s"'<>\\]+)''', r'\1<REDACTED>'),
        (r'''(?i)(["'](?:bootstrap[_ -]?token|pairing[_ -]?token|access[_ -]?token|token)["']\s*:\s*["'])([^"']+)(["'])''', r'\1<REDACTED>\3'),
        (r'''(?i)(\\"(?:bootstrap[_ -]?token|pairing[_ -]?token|access[_ -]?token|token)\\"\s*:\s*\\")([^"\\]+)(\\")''', r'\1<REDACTED>\3'),
    )
    for pattern, replacement in patterns:
        value = re.sub(pattern, replacement, value)
    return value


def sanitize_evidence():
    redacted = []
    for path in evidence.rglob("*"):
        if not path.is_file() or path.suffix not in (".json", ".txt", ".log", ".typescript"):
            continue
        original = path.read_text()
        sanitized = redact_text(original)
        if original != sanitized:
            path.write_text(sanitized)
            redacted.append(str(path.relative_to(evidence)))
    (evidence / "redaction-summary.json").write_text(json.dumps({"RedactedFiles": redacted, "Replacement": "<REDACTED>"}, indent=2))


def run(command, cwd=None, allow_failure=False, timeout=180):
    global sequence
    sequence += 1
    completed = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    record = {"Arguments": command, "Workspace": str(cwd) if cwd else None, "ExitCode": completed.returncode,
              "Stdout": redact_text(completed.stdout), "Stderr": redact_text(completed.stderr)}
    (evidence / f"command-{sequence:04}.json").write_text(json.dumps(record, indent=2))
    if completed.returncode and not allow_failure:
        raise RuntimeError(redact_text(f"{command} failed ({completed.returncode}): {completed.stdout}\n{completed.stderr}"))
    return completed


def engine(*command, **options):
    return run([args.engine, *command], **options)


def launch(index, *command):
    return run(["bash", str(launcher_path), "--engine", args.engine, *command], cwd=workspaces[index])


def inspect(index):
    return json.loads(engine("inspect", names[index]).stdout)[0]


def check(name, **details):
    checks.append(json.loads(redact_text(json.dumps({"Check": name, **details}))))
    print(name, flush=True)


def read_http(index, port, path="/", expected=None, service=None):
    url = f"http://{addresses[index]}:{port}{path}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    error = None
    for _ in range(90):
        if service is not None and service.poll() is not None:
            raise RuntimeError(f"Service exited before HTTP at {url}")
        try:
            with opener.open(url, timeout=2) as response:
                body = response.read().decode()
                assert response.status == 200
            if expected is not None:
                assert body == expected, (url, body, expected)
            check("http", Url=url, Body=body[:2048])
            return body
        except (OSError, urllib.error.URLError) as failure:
            error = failure
            time.sleep(0.5)
    raise RuntimeError(f"Unreachable {url}: {error}")


def background(command, filename, cwd=None):
    handle = (evidence / filename).open("w")
    child = subprocess.Popen(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT, text=True)
    children.append((child, handle))
    return child


def terminal_run(command, cwd, input_text):
    pid, descriptor = pty.fork()
    if pid == 0:
        os.chdir(cwd)
        os.execvp(command[0], command)
    output = bytearray()
    deadline = time.monotonic() + 120
    try:
        os.write(descriptor, input_text.encode())
        while time.monotonic() < deadline:
            if select.select([descriptor], [], [], 0.25)[0]:
                try:
                    chunk = os.read(descriptor, 65536)
                except OSError as failure:
                    if failure.errno != 5:
                        raise
                    break
                if not chunk:
                    break
                output.extend(chunk)
        else:
            os.killpg(pid, signal.SIGTERM)
            raise TimeoutError("Interactive launcher terminal timed out.")
        _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status), output.decode(errors="replace")
    finally:
        os.close(descriptor)


try:
    engine("version")
    engine_info = json.loads(engine("info", "--format", "{{json .}}").stdout)
    if args.engine == "podman":
        assert engine_info["host"]["security"]["rootless"] is True
        assert engine_info["host"]["serviceIsRemote"] is False
        check("native-linux-rootless-engine", GraphRoot=engine_info["store"]["graphRoot"])
    if args.require_selinux_enforcing:
        mode = run(["getenforce"]).stdout.strip()
        assert mode == "Enforcing", f"Required SELinux Enforcing host; received {mode!r}."
        assert engine_info["host"]["security"]["selinuxEnabled"] is True
        assert engine_info["host"]["security"]["rootless"] is True
        check("selinux-enforcing-precheck", Mode=mode)
    original_image = engine("image", "inspect", "--format", "{{.Id}}", "ai-sandbox:latest").stdout.strip()
    result["Image"] = original_image
    for index in range(2):
        launch(index, "reset-config")
        data = inspect(index)
        assert data["State"]["Running"]
        assert data["Config"]["WorkingDir"] == "/workspace"
        for port in ports:
            mapping = engine("port", names[index], f"{port}/tcp").stdout.splitlines()
            assert f"{addresses[index]}:{port}" in mapping, mapping
        for volume in volumes[index]:
            engine("volume", "inspect", volume)
        if args.require_selinux_enforcing:
            creation_command = data["Config"]["CreateCommand"]
            assert f"{workspaces[index]}:{workspace_paths[index]}:Z" in creation_command
            assert f"{ro}:/supplemental/read only:ro,z" in creation_command
            assert f"{rw}:/supplemental/read write:rw,z" in creation_command
            assert not any("label=disable" in value for value in creation_command)
            assert not any("label=disable" in value for value in data["HostConfig"].get("SecurityOpt", []) or [])
            assert data["ProcessLabel"] and data["MountLabel"]
            run(["ls", "-Zd", str(workspaces[index]), str(ro), str(rw)])
            check("selinux-private-workspace-shared-supplemental-labels", Container=names[index], ProcessLabel=data["ProcessLabel"], MountLabel=data["MountLabel"])
        creation_env = dict(value.split("=", 1) for value in data["Config"]["Env"])
        for key, port in zip(("T3", "CODENOMAD", "PASEO", "ALT_HTTP", "APP"), ports):
            assert creation_env[f"AI_SANDBOX_HOST_{key}_PORT"] == str(port)
            field = "ADDRESS" if key == "PASEO" else "URL"
            expected = f"{addresses[index]}:{port}" if key == "PASEO" else f"http://{addresses[index]}:{port}"
            assert creation_env[f"AI_SANDBOX_{key}_{field}"] == expected
        check("creation-inspection", Container=names[index], Address=addresses[index])
    marker = task_root.name
    write_script = 'for state in config auth data cache; do echo "$MARKER" > /state/$state/rootless-marker; done; echo sandbox > "$AI_SANDBOX_WORKSPACE_PATH/sandbox-write"; echo sandbox > "/supplemental/read write/sandbox-write"'
    engine("exec", "--user", "sandbox", "--env", "MARKER=" + marker, names[0], "sh", "-c", write_script)
    engine("exec", names[0], "/opt/ai-sandbox/entrypoint.sh", "bash", "-c", 'echo root > "$AI_SANDBOX_WORKSPACE_PATH/root-write"; echo root > "/supplemental/read write/root-write"')
    assert (workspaces[0] / "sandbox-write").read_text().strip() == "sandbox"
    assert (rw / "sandbox-write").read_text().strip() == "sandbox"
    assert (workspaces[0] / "root-write").read_text().strip() == "root"
    for user in ("0", "sandbox"):
        assert engine("exec", "--user", user, names[0], "sh", "-c", 'echo forbidden > "/supplemental/read only/forbidden"', allow_failure=True).returncode != 0
    check("privileged-initialization-and-mount-access", WorkspaceMode=oct(workspaces[0].stat().st_mode & 0o777))
    engine("exec", "--user", "sandbox", names[1], "sh", "-c", 'test "$(cat "/supplemental/read only/source.txt")" = read-only-source; test "$(cat "/supplemental/read write/sandbox-write")" = sandbox; echo shared > "/supplemental/read write/second-write"')
    assert engine("exec", "--user", "sandbox", names[0], "cat", "/supplemental/read write/second-write").stdout.strip() == "shared"
    check("two-containers-share-supplemental-mounts")

    server = '''import http.server, threading, time
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  body=(IDENTITY+":"+str(self.server.server_port)).encode(); self.send_response(200); self.end_headers(); self.wfile.write(body)
for port in (3773,9899,6767,8080,3000):
 threading.Thread(target=http.server.HTTPServer(("0.0.0.0",port),Handler).serve_forever,daemon=True).start()
time.sleep(900)
'''
    for index in range(2):
        engine("exec", "-d", names[index], "python3", "-c", "IDENTITY=" + repr(names[index]) + "\n" + server)
        for port in ports:
            read_http(index, port, expected=names[index] + ":" + str(port))
    before_stop = [inspect(index)["Id"] for index in range(2)]
    for index in range(2):
        launch(index, "stop")
        assert not inspect(index)["State"]["Running"]
        launch(index, "reset-config")
        assert inspect(index)["Id"] == before_stop[index]
    check("stop-start-preserves-containers-and-volumes")

    for service, port, path in (("t3", 3773, "/"), ("codenomad", 9899, "/"), ("paseo", 6767, "/api/status")):
        help_output = launch(0, service, "--help").stdout
        assert re.search(r"usage|options", help_output, re.IGNORECASE), help_output
        check("native-tool-help-argument", Service=service)
        child = background(["bash", str(launcher_path), "--engine", args.engine, service], service + ".log", workspaces[0])
        body = read_http(0, port, path, service=child)
        if service == "t3": assert re.search(r"<title>T3 Code(?: \(Alpha\))?</title>", body)
        elif service == "codenomad": assert "<title>CodeNomad</title>" in body
        else:
            identity = json.loads(body)
            assert identity["status"] == "server_info"
            assert identity["hostname"] == inspect(0)["Config"]["Hostname"]
        log = (evidence / (service + ".log")).read_text()
        expected_address = f"{addresses[0]}:{port}"
        assert expected_address in log, log
        check("actual-service-noninteractive", Service=service, Endpoint=expected_address)

    # A native PTY gives both the launcher and its engine exec actual terminal handles.
    shell_command = ["bash", str(launcher_path), "--engine", args.engine, "shell"]
    tty_commands = f'printf "SHELL_PWD=%s\\n" "$PWD"; test -t 0 && test -t 1 && echo REAL_TTY_PASS; env | grep "^AI_SANDBOX_"; exit\n'
    tty_status, tty_output = terminal_run(shell_command, workspaces[0], tty_commands)
    (evidence / "interactive.typescript").write_text(tty_output)
    assert tty_status == 0, tty_output
    assert re.search(r"[\r\n]REAL_TTY_PASS[\r\n]", tty_output) and f"SHELL_PWD={workspace_paths[0]}" in tty_output
    for port in ports: assert f"{addresses[0]}:{port}" in tty_output
    check("interactive-shell-banner-and-exec-environment")
    claude_status, claude_output = terminal_run(
        ["bash", str(launcher_path), "--engine", args.engine, "claude", "--version"], workspaces[0], "")
    (evidence / "claude-version.typescript").write_text(claude_output)
    assert claude_status == 0 and "Claude Code" in claude_output, claude_output
    check("native-claude-sandbox-dispatch")
    launch(0, "stop")
    for child, handle in children:
        child.wait(timeout=30)
        handle.close()
    children.clear()

    launch(0, "reset-config")
    engine("exec", names[0], "sh", "-c", 'echo ticket04-custom >> /state/config/codex/config.toml')
    launch(0, "reset-config")
    assert "ticket04-custom" not in engine("exec", names[0], "cat", "/state/config/codex/config.toml").stdout
    check("reset-config-restores-managed-default")

    for reason in ("remove", "mount", "endpoint", "image"):
        launch(0, "reset-config")
        old_id = inspect(0)["Id"]
        if reason == "remove": launch(0, "rm")
        elif reason == "mount":
            with (workspaces[0] / ".ai-sandbox/supplemental-folders.config").open("a") as handle:
                handle.write(f"{rw}|extra write|rw\n")
        elif reason == "endpoint":
            signature = inspect(0)["Config"]["Labels"]["ai-sandbox.supplemental-folders"]
            engine("rm", "-f", names[0])
            engine("run", "-d", "--name", names[0], "--label", "ai-sandbox.supplemental-folders=" + signature, "ai-sandbox:latest", "daemon")
            old_id = inspect(0)["Id"]
        else:
            identity_tag = "localhost/ai-sandbox-ticket04-identity:" + uuid.uuid4().hex
            engine("commit", "--change", "LABEL ticket04.identity=" + marker, names[0], identity_tag)
            engine("tag", identity_tag, "ai-sandbox:latest")
        launch(0, "reset-config")
        assert inspect(0)["Id"] != old_id
        for state in ("config", "auth", "data", "cache"):
            assert engine("exec", names[0], "cat", f"/state/{state}/rootless-marker").stdout.strip() == marker
        if reason == "image":
            engine("tag", original_image, "ai-sandbox:latest")
            launch(0, "reset-config")
        check("recreation-preserves-four-volumes", Reason=reason)
    launch(0, "reset-state")
    assert engine("inspect", names[0], allow_failure=True).returncode != 0
    for volume in volumes[0]: assert engine("volume", "inspect", volume, allow_failure=True).returncode != 0
    assert inspect(1)["State"]["Running"]
    for volume in volumes[1]: engine("volume", "inspect", volume)
    check("scoped-reset-state-preserves-second-workspace")
    result["Result"] = "passed"
except BaseException as error:
    result["Error"] = redact_text(repr(error))
    error.args = tuple(redact_text(str(value)) for value in error.args)
    raise
finally:
    try:
        cleanup = []
        for name in names:
            cleanup.append({"Container": name, "ExitCode": engine("rm", "-f", name, allow_failure=True).returncode})
        for child, handle in children:
            try: child.wait(timeout=20)
            except subprocess.TimeoutExpired:
                child.terminate()
                child.wait(timeout=10)
            handle.close()
        if "original_image" in globals(): engine("tag", original_image, "ai-sandbox:latest", allow_failure=True)
        if identity_tag: engine("image", "rm", identity_tag, allow_failure=True)
        for volume_set in volumes:
            for volume in volume_set:
                cleanup.append({"Volume": volume, "ExitCode": engine("volume", "rm", volume, allow_failure=True).returncode})
        result["Cleanup"] = cleanup
        try:
            shutil.rmtree(task_root)
            result["HostFixtureCleanup"] = "passed"
        except OSError as failure:
            result["HostFixtureCleanup"] = repr(failure)
            result["Result"] = "failed"
        (evidence / "result.json").write_text(redact_text(json.dumps(result, indent=2)))
        print("Evidence:", evidence, flush=True)
    finally:
        sanitize_evidence()
