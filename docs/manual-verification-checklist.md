# Manual Verification Checklist

## Host setup

- Docker is running.
- The workspace directory is shareable with Docker.

## Container basics

- `ai-sandbox` opens a shell in `/workspace`.
- The shell banner shows the available commands, including `opencode`, and the T3 URL reserved for `ai-sandbox t3`.
- Files created in `/workspace` appear on the host.

## Tool versions

- `ai-sandbox doctor` reports versions for `codex`, `gemini`, `copilot`, `opencode`, `node`, and Docker.

## Auth

- `codex` can authenticate and remain logged in across `ai-sandbox rm`.
- `gemini` can authenticate and remain logged in across `ai-sandbox rm`.
- `copilot` can authenticate and remain logged in across `ai-sandbox rm`.
- `opencode` can authenticate and remain logged in across `ai-sandbox rm`.

## T3

- `ai-sandbox t3` starts a server bound to the selected host port.
- The host browser can reach the printed T3 URL.
- T3 can create a Codex-backed session after Codex is authenticated.

## Reset semantics

- `ai-sandbox reset-config` restores preset files without deleting credentials.
- `ai-sandbox reset-config` restores the OpenCode preset without deleting OpenCode credentials.
- `ai-sandbox reset-state` wipes credentials and runtime data for only the current workspace.
