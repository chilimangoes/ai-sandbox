# Auth

All auth for v1 happens inside the sandbox and persists only in Docker volumes. The launcher never imports host credentials.

## Codex

- Authenticate by running `codex` inside the sandbox shell.
- Codex config defaults live in `/state/config/codex/config.toml`.
- Codex auth is stored under `/state/auth/codex`.
- T3 depends on a working Codex login because it uses `codex app-server`.

## Gemini

- Authenticate inside the sandbox by following the Gemini CLI login flow.
- Gemini preset files live under `/state/config/gemini`.
- Gemini auth artifacts stay under `/state/auth/gemini`.

## Copilot

- Authenticate inside the sandbox by running `copilot` and following `/login`.
- Copilot preset files live under `/state/config/copilot`.
- Copilot auth and session state persist in Docker volumes for the current workspace.

## OpenCode

- Authenticate inside the sandbox by running `opencode` and following the OpenCode `/connect` flow.
- OpenCode global config defaults live under `/state/config/opencode/opencode.json`.
- OpenCode auth persists at `/state/auth/opencode/auth.json`.
- The container maps OpenCode's expected XDG paths so `~/.config/opencode/opencode.json` and `~/.local/share/opencode/auth.json` survive container recreation.

## CodeNomad

- Start CodeNomad by running `ai-sandbox codenomad`.
- CodeNomad uses the sandbox's `opencode`, so OpenCode must already be installed and authenticated inside the sandbox.
- The sandbox launcher currently starts CodeNomad with its internal auth disabled because it is exposed only on loopback by default and current CodeNomad server builds require an explicit password bootstrap otherwise.
- CodeNomad config defaults live under `/state/config/codenomad/config.json`.
- CodeNomad instance state persists under `/state/data/codenomad/instances`.
- CodeNomad TLS material, if enabled later, persists under `/state/data/codenomad/tls`.

## Paseo

- Start Paseo by running `ai-sandbox paseo`.
- Paseo is a daemon/orchestrator, not the underlying credential source for agent providers.
- Authenticate the provider CLIs that Paseo will manage inside the sandbox first, such as `codex` or `opencode`.
- Paseo config defaults live under `/state/config/paseo/config.json`.
- Paseo runtime state persists under `/state/data/paseo`.
- The launcher sets `PASEO_HOME=/state/data/paseo` for the daemon.
- The launcher disables Paseo's public relay by default with `--no-relay`; set `paseo_relay=1` in `/state/config/shared/sandbox.config` only if you explicitly want relay-backed clients.

## T3

- T3 is configured for Codex-backed usage in v1.
- If T3 cannot create sessions, verify Codex authentication first.
- T3 runtime config lives under `/state/config/t3`.

## Reset guidance

- Use `ai-sandbox reset-config` to restore default presets while keeping credentials.
- Use `ai-sandbox reset-state` only when you want to wipe all sandbox state, including credentials.
