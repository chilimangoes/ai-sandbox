# Architecture

## Locked v1 decisions

- `ai-sandbox` opens an interactive shell by default.
- Shell mode prints a short banner listing `codex`, `gemini`, `copilot`, `opencode`, and `t3`, plus the selected host T3 URL to use after `ai-sandbox t3` starts the server.
- `ai-sandbox t3` runs T3 in the foreground for the current session. Closing the terminal stops it.
- Tool auth is created and stored only inside Docker volumes.
- Image refreshes only happen when the image is missing or the user passes `--update` or `--rebuild`.
- Docker is the only supported runtime. Podman is intentionally out of scope.

## Host model

The host launcher is workspace-centric:

1. Resolve the current working directory as the sandbox workspace.
2. Derive a stable workspace slug and short hash from the absolute path.
3. Build or refresh the shared image when required.
4. Start one detached workspace-scoped container.
5. Execute either `shell`, `codex`, `gemini`, `copilot`, `opencode`, or `t3` inside that container.

Each workspace gets:

- one container
- one config volume
- one auth volume
- one data volume
- one cache volume

## Container model

The image contains all tool binaries and the repo-managed default presets. The container itself stays lightweight and detached with a long-running idle process so later invocations can use `docker exec`.

Runtime filesystem layout:

- `/workspace`: bind mount of the host workspace
- `/state/config`: persisted user-editable config files
- `/state/auth`: persisted auth material
- `/state/data`: persisted tool state and session data
- `/state/cache`: persisted caches
- `/opt/ai-sandbox/defaults/configs`: image-baked default presets copied from this repo

The entrypoint performs idempotent bootstrap on every start:

1. Ensure state directories exist.
2. Initialize missing config files from image defaults.
3. Wire the expected home-directory paths to the persisted state roots.
4. Dispatch the requested command.

## Config and auth separation

The repo is the source of truth for default presets, not for mutable user state.

- Presets live under `configs/` in this repo.
- Presets are copied into the image at build time.
- Presets are copied into `/state/config` only when files are missing, or when the user runs `reset-config`.
- Auth is never copied from the host and is never overwritten by normal startup.
- `reset-state` deletes all persisted volumes for the current workspace. That is the only v1 flow that wipes auth.

## CLI surface

Primary commands:

- `ai-sandbox`
- `ai-sandbox shell`
- `ai-sandbox codex`
- `ai-sandbox gemini`
- `ai-sandbox copilot`
- `ai-sandbox opencode`
- `ai-sandbox t3`

Maintenance commands:

- `ai-sandbox doctor`
- `ai-sandbox stop`
- `ai-sandbox rm`
- `ai-sandbox reset-config`
- `ai-sandbox reset-state`
- `ai-sandbox --update`
- `ai-sandbox --rebuild`
- `ai-sandbox --t3-port <port>`

## T3 exposure

- Container port: `3773`
- Default host port: `3773`
- If `--t3-port` is omitted, the launcher probes from `3773` upward until it finds a free host port.
- The chosen URL is surfaced in shell startup output and when T3 launches.
- Shell mode reserves and prints the URL, but only `ai-sandbox t3` starts the T3 server.
- T3 is configured for Codex-backed usage in v1. Future provider support can add new preset files without changing the launcher contract.

## Image design

- Base image: Debian Bookworm slim
- Runtime: Node.js 22
- Common packages: `bash`, `curl`, `git`, `jq`, `less`, `procps`, `ripgrep`, `unzip`, `ca-certificates`
- Runtime user: non-root `sandbox`

The image installs:

- `@openai/codex`
- `@google/gemini-cli`
- `@github/copilot`
- `opencode-ai`
- a lightweight `t3` launcher path via `npx t3`

## Compatibility notes

Windows-first design points:

- PowerShell is the primary Windows launcher.
- The launcher resolves the workspace via PowerShell path APIs before handing it to Docker.
- Spaces and OneDrive-backed paths are preserved as normal bind mounts.

Linux notes:

- The shell launcher follows the same naming and lifecycle rules.
- The launcher passes the host UID/GID to the container so files written into `/workspace` map cleanly on Linux hosts.
