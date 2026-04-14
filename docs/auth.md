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

## T3

- T3 is configured for Codex-backed usage in v1.
- If T3 cannot create sessions, verify Codex authentication first.
- T3 runtime config lives under `/state/config/t3`.

## Reset guidance

- Use `ai-sandbox reset-config` to restore default presets while keeping credentials.
- Use `ai-sandbox reset-state` only when you want to wipe all sandbox state, including credentials.
