"""Exercise entrypoint dispatch in Bash with the CLI and recovery replaced by recorders."""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
BASH = os.environ.get("BASH") or (
    "C:/Program Files/Git/bin/bash.exe" if os.name == "nt" else shutil.which("bash")
)


def shell_path(path):
    value = Path(path).resolve().as_posix()
    return f"/{value[0].lower()}{value[2:]}" if os.name == "nt" else value


class DispatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="t3-dispatch-")
        cls.root = Path(cls.temporary.name)
        source = (REPO / "docker/entrypoint.sh").read_text(encoding="utf-8")
        functions = "\n".join(re.findall(r"^\w+\(\) \{\n.*?^\}", source, re.M | re.S))
        cls.recorder = cls.root / "record.py"
        cls.recorder.write_text(
            "import json, os, sys\n"
            "print(json.dumps({'args': sys.argv[1:], 'stdin': sys.stdin.read(), "
            "'env': {k: v for k, v in os.environ.items() if k.startswith('T3')}, "
            "'user': os.environ.get('TEST_USER')}))\n"
            "sys.exit(int(os.environ.get('TEST_EXIT', '0')))\n",
            encoding="utf-8",
        )
        cli = cls.root / "t3"
        cli.write_text(
            "#!/usr/bin/env bash\nexec "
            + shlex.join([Path(sys.executable).as_posix(), cls.recorder.as_posix()])
            + ' "$@"\n', encoding="utf-8", newline="\n",
        )
        cli.chmod(0o755)
        cls.harness = cls.root / "dispatch.sh"
        cls.harness.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n" + functions + "\n"
            + "REAL_BIN_DIR=" + shlex.quote(shell_path(cls.root)) + "\n"
            + "CONTAINER_T3_PORT=3773\nHOST_T3_URL=http://127.91.42.17:3773\n"
            "AI_SANDBOX_T3_URL=$HOST_T3_URL\n"
            "run_as_sandbox() { export TEST_USER=sandbox; eval \"$1\"; }\n"
            "run_as_root() { export TEST_USER=root; eval \"$1\"; }\n"
            "python3() {\n"
            "  case \"$1\" in\n"
            "    */t3-startup.py) shift; printf 'RECOVERY:%s\\n' \"$*\" >&2; return \"${TEST_RECOVERY_EXIT:-0}\" ;;\n"
            "    */t3-output.py) cat ;;\n"
            "    *) return 99 ;;\n"
            "  esac\n"
            "}\n"
            'dispatch "$@"\n', encoding="utf-8", newline="\n",
        )

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def invoke(self, *args, stdin="", **environment):
        command = shlex.join(["bash", shell_path(self.harness), "t3", *args])
        env = {key: value for key, value in os.environ.items() if not key.startswith("T3")}
        return subprocess.run(
            [BASH, "-c", command], input=stdin, text=True, capture_output=True,
            env={**env, "MSYS_NO_PATHCONV": "1", "MSYS2_ENV_CONV_EXCL": "T3CODE_HOME;T3_CONFIG_PATH", **environment}, timeout=10,
        )

    def record(self, *args, **options):
        result = self.invoke(*args, **options)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.splitlines()[-1]), result

    def test_subcommands_preserve_arguments_and_skip_recovery(self):
        for args in [("connect",), ("pair",), ("pair", "--tailscale"), ("auth", "session", "list"),
                     ("thread", "send", "thread-id", "space and 'quote'", "--json"),
                     ("future-command", "$(echo injected)", "")]:
            with self.subTest(args=args):
                record, result = self.record(*args)
                expected = [*args, "--headless"] if args == ("connect",) else list(args)
                self.assertEqual(record["args"], expected)
                self.assertNotIn("RECOVERY:", result.stderr)
                self.assertEqual(record["user"], "sandbox")
                self.assertEqual(record["env"]["T3CODE_HOME"], "/state/data/t3")

    def test_stdin_and_exit_status(self):
        result = self.invoke("thread", "send", "thread-id", "-", stdin="my message\n", TEST_EXIT="17")
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(json.loads(result.stdout)["stdin"], "my message\n")

    def test_help_bypasses_startup_and_policy(self):
        for args in [("--help",), ("--version",), ("start", "--help"),
                     ("serve", "--help"), ("update", "--help"), ("help",)]:
            with self.subTest(args=args):
                record, result = self.record(*args)
                self.assertEqual(record["args"], list(args))
                self.assertNotIn("RECOVERY:", result.stderr)

    def test_server_defaults_and_explicit_flags(self):
        for args in [(), ("start",), ("serve",),
                     ("start", "--port", "4999", "--base-dir", "state with spaces"),
                     ("./project",), ("--port=4999",)]:
            with self.subTest(args=args):
                record, result = self.record(*args)
                self.assertEqual(record["args"], list(args) if args else ["start"])
                self.assertIn("RECOVERY:", result.stderr)
                self.assertEqual(record["env"]["T3CODE_HOST"], "0.0.0.0")
                self.assertEqual(record["env"]["T3CODE_PORT"], "3773")
                self.assertEqual(record["env"]["T3CODE_NO_BROWSER"], "true")
                if args and "--base-dir" in args:
                    self.assertIn("--base-dir state with spaces", result.stderr)
                if args != ("serve",):
                    self.assertEqual(record["env"]["T3CODE_AUTO_BOOTSTRAP_PROJECT_FROM_CWD"], "true")
                else:
                    self.assertNotIn("T3CODE_AUTO_BOOTSTRAP_PROJECT_FROM_CWD", record["env"])

    def test_server_exit_status(self):
        self.assertEqual(self.invoke("start", TEST_EXIT="23").returncode, 23)

    def test_pair_exit_status(self):
        self.assertEqual(self.invoke("pair", TEST_EXIT="24").returncode, 24)

    def test_explicit_state_and_pairing_url(self):
        for args in [("auth", "session", "list", "--base-dir", "help"),
                     ("--base-dir", "other state", "auth", "session", "list"),
                     ("auth", "pairing", "create", "--base-url", "https://example.com"),
                     ("pair", "--base-dir=other-state")]:
            with self.subTest(args=args):
                record, result = self.record(*args)
                self.assertEqual(record["args"], list(args))
                self.assertNotIn("RECOVERY:", result.stderr)
        record, _ = self.record("auth", "pairing", "create")
        self.assertEqual(record["args"], ["auth", "pairing", "create", "--base-url", "http://127.91.42.17:3773"])

    def test_inherited_state(self):
        record, result = self.record("start", T3CODE_HOME="custom-state")
        self.assertEqual(record["env"]["T3CODE_HOME"], "custom-state")
        self.assertIn("RECOVERY:--base-dir custom-state", result.stderr)

    def test_recovery_refusal_stops_startup(self):
        result = self.invoke("start", TEST_RECOVERY_EXIT="29")
        self.assertEqual(result.returncode, 29, result.stderr)
        self.assertNotIn('"args"', result.stdout)

    def test_connect_login_defaults(self):
        for args in [("connect", "login"), ("connect", "link"), ("connect", "status")]:
            record, _ = self.record(*args)
            expected = [*args, "--headless"] if args[-1] != "status" else list(args)
            self.assertEqual(record["args"], expected)

    def test_image_lifecycle_commands_explain_host_action(self):
        for args in [("update",), ("uninstall",), ("service", "install"),
                     ("service", "restart"), ("service", "update"), ("service", "uninstall")]:
            with self.subTest(args=args):
                result = self.invoke(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("RECOVERY:", result.stderr)
                self.assertIn("ai-sandbox", result.stderr)


if __name__ == "__main__":
    unittest.main()
