# Troubleshooting

## T3 stays on an older version after rebuilding

Older launchers used `docker build --pull`, which can reuse the cached npm install layer even when newer releases exist. Use the updated launcher and run `ai-sandbox --rebuild t3` from the affected workspace. Explicit updates now bypass the build cache and install `t3@latest` (stable, not nightly).

To verify the installed version, run `/opt/ai-sandbox/bin/t3 --version` inside the sandbox and compare it with `npm view t3@latest version`. Releases published after the build require another explicit update. Rebuilding preserves workspace config, auth, data, and cache volumes; resetting state is unnecessary.

## Docker is not available

- Verify `docker version` succeeds on the host.
- On Windows, make sure Docker Desktop is running.

## Workspace mount fails on Windows

- Confirm Docker Desktop is allowed to access the drive containing the workspace.
- Re-run from PowerShell so the launcher can resolve the canonical path cleanly.
- OneDrive-backed paths are supported, but they still depend on Docker Desktop file sharing.

## T3 disconnects when multiple sandboxes are open

- Open the exact T3 URL printed by `ai-sandbox`; it may use a workspace-specific address such as `127.91.42.17`.
- Do not rewrite the printed T3 URL to `localhost` or `127.0.0.1`, because browser cookies are scoped by host and can collide across T3 instances.

## Published service address is unavailable

- Each workspace publishes T3 and web app ports `8080` and `3000` on one workspace-specific `127.x.y.z` address with matching host/container ports.
- If Docker reports a bind conflict, stop or remove the process/container already using that exact workspace address and port.
- `ai-sandbox --rebuild` recreates the current workspace container with the current fixed service mappings.

## Config changes were overwritten

- Normal startup does not overwrite persisted config.
- If config changed unexpectedly, check whether `reset-config` was used for that workspace.

## Auth disappeared

- Auth should survive container recreation because it lives in named volumes.
- `reset-state` removes auth volumes by design.

## T3 cannot reach Codex

- Verify `codex` is authenticated inside the sandbox.
- Run `codex app-server --help` inside the sandbox to confirm the CLI supports the app-server mode.
- Rebuild with `ai-sandbox --update` if the image was built against an older CLI release.

## T3 startup records after a container restart

Before starting T3, the sandbox checks `/state/data/t3/userdata/server-runtime.json`. A stale record can refer to a missing process, an exited process awaiting cleanup, or a PID reused by a process that started after the recorded server.

Automatic recovery supports the ownership protocol in stable T3 `0.1.x`. Recovery requires a free T3 ownership lock, an unused local server port, and an unchanged runtime record. It removes only `server-runtime.json`. T3 recreates that file on startup. Sessions, authentication, settings, databases, and the ownership lock are preserved.

If a server owns the state or verification is uncertain, startup stops with `T3 startup record preserved` and the reason. Examples include unreadable process details, a busy port, a changed record, and an unsupported T3 version. Check the reported process or listener before retrying. Rebuilding preserves the data volume, including the runtime record.

## T3 browser reports missing libraries or a blocked sandbox

The image includes Chrome's shared libraries and system fonts. The launchers apply a seccomp profile that permits Chrome's sandbox namespaces. Run `ai-sandbox --rebuild t3` from the affected workspace to install the image and recreate the container with that profile.

T3 runs as `sandbox`. The `t3 browser setup` command checks the account running setup. Invoking setup from a root shell can print a root warning even when the T3 server runs as `sandbox`.

## Claude Code is unavailable or logged out

- Run `claude --version` or `ai-sandbox doctor` to verify the CLI is installed.
- Run `ai-sandbox claude` and complete the login flow if authentication is required.
- Rebuild with `ai-sandbox --update` to install the latest package release.
- Claude state survives `ai-sandbox rm`, but `ai-sandbox reset-state` intentionally removes it.

## Cursor CLI is unavailable or logged out

- Run `cursor --version` inside the sandbox to verify the alias and installed CLI.
- Run `cursor status`, then `cursor login` if authentication is required.
- Rebuild with `ai-sandbox --update` to install the latest Cursor CLI release.
- If state was intentionally cleared with `reset-state`, authenticate again.
