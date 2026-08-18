# Architecture

## High-level behavior decisions

- `ai-sandbox` opens an interactive shell by default.
- Shell mode prints a short banner listing `codex`, `claude`, `agy`, `copilot`, `opencode`, `cursor` (`cursor-agent`), `t3`, `codenomad`, and `paseo`, plus the selected host T3, CodeNomad, and Paseo addresses to use after their service commands start.
- `ai-sandbox t3` runs T3 in the foreground for the current session. Closing the terminal stops it.
- `ai-sandbox codenomad` runs CodeNomad in the foreground for the current session. Closing the terminal stops it.
- `ai-sandbox paseo` runs the Paseo daemon in the foreground for the current session. Closing the terminal stops the daemon.
- Tool auth is created and stored only inside Docker volumes.
- Image refreshes only happen when the image is missing or the user passes `--update` or `--rebuild`.
- Docker is the only supported runtime. Podman is intentionally out of scope.

## Host model

The host launcher is workspace-centric:

1. Resolve the current working directory as the sandbox workspace.
2. Derive a stable workspace slug, short hash, and workspace-specific loopback address from the absolute path.
3. Build or refresh the shared image when required.
4. Start one detached workspace-scoped container.
5. Execute either `shell`, `codex`, `claude`, `agy`, `copilot`, `opencode`, `cursor`, `cursor-agent`, `t3`, `codenomad`, or `paseo` inside that container.

Each workspace gets:

- one container
- one config volume
- one auth volume
- one data volume
- one cache volume

## Container model

The image contains all tool binaries and the repo-managed default presets. The container itself stays lightweight and detached with a long-running idle process so later invocations can use `docker exec`.

Runtime filesystem layout:

- `/workspace`: trusted parent directory inside the container
- `/workspace/<project-folder-slug>`: bind mount of the host workspace
- `/state/config`: persisted user-editable config files
- `/state/auth`: persisted auth material
- `/state/data`: persisted tool state and session data
- `/state/data/agents`: persisted shared agent metadata exposed as `~/.agents`
- `/state/cache`: persisted caches
- `/opt/ai-sandbox/defaults/configs`: image-baked default presets copied from this repo

CodeNomad runs inside the same container as `opencode`, so the browser only crosses the Docker boundary to reach the UI. All OpenCode execution, file access, and auth stay inside the sandbox.

Paseo also runs inside the same container, but it exposes a daemon endpoint rather than a standalone local UI. Clients connect to the daemon while all agent execution, file access, and credentials remain inside the sandbox.

Paseo relay connectivity is disabled by default. The launcher reads `/state/config/shared/sandbox.config`; only `paseo_relay=1` opts into running the daemon without `--no-relay`.

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
- `ai-sandbox claude`
- `ai-sandbox agy`
- `ai-sandbox copilot`
- `ai-sandbox opencode`
- `ai-sandbox cursor`
- `ai-sandbox cursor-agent`
- `ai-sandbox t3`
- `ai-sandbox codenomad`
- `ai-sandbox paseo`

Maintenance commands:

- `ai-sandbox doctor`
- `ai-sandbox stop`
- `ai-sandbox rm`
- `ai-sandbox reset-config`
- `ai-sandbox reset-state`
- `ai-sandbox --update`
- `ai-sandbox --rebuild`

## Service exposure model

- Each workspace gets one deterministic `127.x.y.z` host loopback address derived from the workspace hash.
- Published services use matching host and container ports on that address.
- Existing workspace containers are recreated when their published service ports do not match the fixed-port model.

## T3 exposure

- Container port: `3773`
- Host port: `3773`
- Host address: the workspace-specific loopback address.
- The chosen URL is surfaced in shell startup output and when T3 launches.
- Users should open the exact printed URL. Rewriting it to `localhost` or `127.0.0.1` defeats the browser cookie isolation used for multiple simultaneous T3 sandboxes.
- Shell mode reserves and prints the URL, but only `ai-sandbox t3` starts the T3 server.
- T3 is configured for Codex-backed usage in v1. Future provider support can add new preset files without changing the launcher contract.

## CodeNomad exposure

- Container port: `9899`
- Host port: `9899`
- Host address: the workspace-specific loopback address.
- The chosen URL is surfaced in shell startup output and when CodeNomad launches.
- Shell mode reserves and prints the URL, but only `ai-sandbox codenomad` starts the CodeNomad server.
- The workspace container publishes service ports at creation time because Docker port mappings cannot be added later without recreating the container.

## Paseo exposure

- Container port: `6767`
- Host port: `6767`
- Host address: the workspace-specific loopback address.
- The chosen address is surfaced in shell startup output and when Paseo launches.
- Shell mode reserves and prints the address, but only `ai-sandbox paseo` starts the Paseo daemon.
- The workspace container publishes service ports at creation time because Docker port mappings cannot be added later without recreating the container.
- `ai-sandbox paseo` passes `--no-relay` by default. To enable the relay, set `paseo_relay=1` in `/state/config/shared/sandbox.config` inside the container's persistent config state.

## Image design

- Base image: Debian Bookworm slim
- Runtime: Node.js 22
- Common packages: `bash`, `curl`, `git`, `jq`, `less`, `procps`, `ripgrep`, `sudo`, `unzip`, `ca-certificates`
- Runtime user: root for shell and tool commands, with `HOME=/home/sandbox` so persisted auth/config paths remain stable
- Command shims: the installed tool commands in the shell route back through `/opt/ai-sandbox/entrypoint.sh`, while the entrypoint calls the real binaries from `/opt/ai-sandbox/bin`

The image installs:

- `@openai/codex`
- `@anthropic-ai/claude-code`
- Antigravity CLI, installed with `curl -fsSL https://antigravity.google/cli/install.sh | bash` and exposed as `agy`
- `@github/copilot`
- `opencode-ai`
- Cursor CLI, installed with `curl https://cursor.com/install -fsS | bash` and exposed as `cursor` and `cursor-agent`
- `@neuralnomads/codenomad`
- `@getpaseo/cli`
- `t3`

Claude Code uses the standard command shim plus `/opt/ai-sandbox/claude-wrapper.sh`. The wrapper synchronizes `~/.claude.json` with `/state/data/claude/claude.json` around each invocation because Claude may replace that file atomically; `~/.claude/` is linked directly to `/state/data/claude/home`.

## Compatibility notes

Windows-first design points:

- PowerShell is the primary Windows launcher.
- The launcher resolves the workspace via PowerShell path APIs before handing it to Docker.
- Spaces and OneDrive-backed paths are preserved as normal bind mounts.

Linux notes:

- The shell launcher follows the same naming and lifecycle rules.
- The launcher still passes the host UID/GID for compatibility with the persisted `sandbox` home layout, but shell and tool commands run as root inside the sandbox.
