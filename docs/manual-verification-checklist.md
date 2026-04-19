# Manual Verification Checklist

## Host setup

- Docker is running.
- The workspace directory is shareable with Docker.

## Container basics

- `ai-sandbox` opens a shell in `/workspace/<project-folder-slug>`.
- The shell banner shows the available commands, including `opencode`, `codenomad`, and `paseo`, and the addresses reserved for `ai-sandbox t3`, `ai-sandbox codenomad`, and `ai-sandbox paseo`.
- Files created in `/workspace/<project-folder-slug>` appear on the host.

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

## CodeNomad

- `ai-sandbox codenomad` starts a server bound to the selected host port.
- The host browser can reach the printed CodeNomad URL.
- CodeNomad can open the current workspace and use the sandbox's `opencode`.
- `ai-sandbox --codenomad-port 9901 codenomad` honors the explicit port.

## Paseo

- `ai-sandbox paseo` starts a daemon bound to the selected host port.
- Another Paseo client can connect to the printed daemon address.
- Paseo can orchestrate the current workspace and use the sandbox's installed coding CLIs.
- `ai-sandbox --paseo-port 6768 paseo` honors the explicit port.
- Default Paseo startup disables relay; setting `paseo_relay=1` in `/state/config/shared/sandbox.config` opts into relay pairing.

## Reset semantics

- `ai-sandbox reset-config` restores preset files without deleting credentials.
- `ai-sandbox reset-config` restores the OpenCode preset without deleting OpenCode credentials.
- `ai-sandbox reset-state` wipes credentials and runtime data for only the current workspace.
