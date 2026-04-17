# Troubleshooting

## Docker is not available

- Verify `docker version` succeeds on the host.
- On Windows, make sure Docker Desktop is running.

## Workspace mount fails on Windows

- Confirm Docker Desktop is allowed to access the drive containing the workspace.
- Re-run from PowerShell so the launcher can resolve the canonical path cleanly.
- OneDrive-backed paths are supported, but they still depend on Docker Desktop file sharing.

## T3 port conflict

- Run `ai-sandbox --t3-port 3774`.
- Without an explicit override, the launcher will probe upward from `3773`.

## CodeNomad port conflict

- Run `ai-sandbox --codenomad-port 9901 codenomad`.
- Without an explicit override, the launcher will probe upward from `9899`.
- If the workspace container already exists with a different published CodeNomad port, the launcher recreates the container so the requested mapping can take effect.

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

## CodeNomad does not start

- Verify the image has been rebuilt after adding CodeNomad support.
- Run `ai-sandbox doctor` and confirm `codenomad` and `opencode` both report versions inside the sandbox.
- Verify `opencode` is authenticated inside the sandbox before expecting CodeNomad to open working sessions.
- If a future CodeNomad release changes its auth bootstrap requirements, revisit the launcher flags around `--dangerously-skip-auth` for loopback-only sandbox use.
