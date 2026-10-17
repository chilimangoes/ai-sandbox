# Auth

Authenticate inside the sandbox. Credentials persist in the selected engine's workspace volumes; the launcher never imports host credentials.

Docker and Podman keep separate authentication, configuration, data, and cache state. Sign in separately after switching engines, or select the original engine to use its stored credentials. Container removal and rebuild preserve these volumes. Host workspace files remain shared between engines.

## Codex

- Authenticate by running `codex` inside the sandbox shell.
- Codex config defaults live in `/state/config/codex/config.toml`.
- Codex auth is stored under `/state/auth/codex`.
- T3 depends on a working Codex login because it uses `codex app-server`.

## Claude Code

- Authenticate by running `claude` or `ai-sandbox claude` and following the Claude Code login flow.
- Claude user settings live at `/state/config/claude/settings.json` and are exposed as `~/.claude/settings.json`.
- Claude's `~/.claude/` state persists under `/state/data/claude/home`.
- Claude's top-level `~/.claude.json` state persists at `/state/data/claude/claude.json`; the launcher synchronizes it around each Claude invocation so atomic updates survive container recreation.
- `ai-sandbox rm` preserves Claude authentication and sessions. `ai-sandbox reset-state` intentionally deletes them.

## Antigravity

- Authenticate inside the sandbox by following the Antigravity CLI login flow.
- Antigravity preset files live under `/state/config/antigravity`.
- Antigravity auth artifacts stay under `/state/auth/antigravity`.

## Copilot

- Authenticate inside the sandbox by running `copilot` and following its sign-in flow.
- Copilot preset files live under `/state/config/copilot`.
- Copilot auth and session state persist in the selected engine's volumes for the current workspace.

## OpenCode

- Authenticate inside the sandbox by running `opencode` and following its provider connection flow.
- OpenCode global config defaults live under `/state/config/opencode/opencode.json`.
- OpenCode auth persists at `/state/auth/opencode/auth.json`.
- The container maps OpenCode's expected XDG paths so `~/.config/opencode/opencode.json` and `~/.local/share/opencode/auth.json` survive container recreation.

## Cursor

- Authenticate inside the sandbox with `cursor login` (or the upstream `cursor-agent login` command).
- Check authentication with `cursor status`.
- Cursor CLI configuration is persisted separately at `/state/config/cursor/cli-config.json`.
- Credentials are stored using Cursor's file credential backend at `/state/auth/cursor/auth.json`, exposed at `~/.config/cursor/auth.json`.
- Session state is persisted under `/state/data/cursor` and linked to `~/.cursor`, so login and sessions survive container recreation and `--rebuild`.
- `reset-state` removes the persisted Cursor state along with the sandbox's other authentication and runtime data.

## CodeNomad

- Start CodeNomad by running `ai-sandbox codenomad`.
- CodeNomad uses the sandbox's `opencode`, so OpenCode must already be installed and authenticated inside the sandbox.
- The launcher starts CodeNomad with internal authentication disabled for its loopback endpoint.
- CodeNomad config defaults live under `/state/config/codenomad/config.json`.
- CodeNomad instance state persists under `/state/data/codenomad/instances`.
- CodeNomad TLS material, if enabled later, persists under `/state/data/codenomad/tls`.

## Paseo

- Start Paseo by running `ai-sandbox paseo`.
- Paseo orchestrates provider CLIs and uses their sandbox credentials.
- Authenticate the provider CLIs that Paseo will manage inside the sandbox first, such as `codex` or `opencode`.
- Paseo config defaults live under `/state/config/paseo/config.json`.
- Paseo runtime state persists under `/state/data/paseo`.
- The launcher sets `PASEO_HOME=/state/data/paseo` for the daemon.
- The launcher disables Paseo's public relay by default through `PASEO_RELAY_ENABLED=0`. Set `paseo_relay=1` in `/state/config/shared/sandbox.config`, then restart Paseo to enable relay connectivity.

## T3

- T3 is configured for Codex-backed usage in v1.
- If T3 cannot create sessions, verify Codex authentication first.
- T3 runtime config lives under `/state/config/t3`.

## Reset guidance

**Warning:** `ai-sandbox reset-state` deletes all persisted state, including credentials, for the current workspace in the selected engine.

Use `ai-sandbox reset-config` to restore default presets while keeping credentials. Both reset commands affect only the selected engine. Use an explicit `--engine` when maintaining workspaces in both stores.
