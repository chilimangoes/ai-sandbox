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

- Each workspace publishes T3, CodeNomad, Paseo, and web app ports `8080` and `3000` on one workspace-specific `127.x.y.z` address with matching host/container ports.
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

## CodeNomad does not start

- Verify the image has been rebuilt after adding CodeNomad support.
- Run `ai-sandbox doctor` and confirm `codenomad` and `opencode` both report versions inside the sandbox.
- Verify `opencode` is authenticated inside the sandbox before expecting CodeNomad to open working sessions.
- If a future CodeNomad release changes its auth bootstrap requirements, revisit the launcher flags around `--dangerously-skip-auth` for loopback-only sandbox use.

## Paseo does not start

- Verify the image has been rebuilt after adding Paseo support.
- Run `ai-sandbox doctor` and confirm `paseo` reports a version inside the sandbox.
- Verify the provider CLIs that Paseo should manage, such as `codex` and `opencode`, are installed and authenticated inside the sandbox.
- If direct local connectivity fails, verify the daemon address and the `daemon.allowedHosts` configuration under `PASEO_HOME/config.json`.
- If Paseo reports another daemon already running after an interrupted session, rerun `ai-sandbox paseo`; the launcher now stops leftover daemon state and removes stale PID files before starting.

## Paseo relay is unavailable

- This is expected by default: `ai-sandbox paseo` passes `--no-relay` unless the shared sandbox config opts in.
- To enable relay pairing, edit `/state/config/shared/sandbox.config` inside the sandbox and set `paseo_relay=1`, then restart `ai-sandbox paseo`.
- Run `ai-sandbox reset-config` to restore the default `paseo_relay=0`.

## Paseo local speech model warnings

- The initial warnings about missing local STT/TTS models are expected before the first successful model download.
