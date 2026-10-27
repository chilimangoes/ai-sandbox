# Manual Verification Checklist

## Host setup

- Docker is running.
- The workspace directory is shareable with Docker.

## Container basics

- `ai-sandbox` opens a shell in `/workspace/<project-folder-slug>`.
- The shell banner lists the available commands and prints the T3 URL and published web app URLs for ports `8080` and `3000`.
- Files created in `/workspace/<project-folder-slug>` appear on the host.

## Tool versions

- `ai-sandbox doctor` reports versions for `codex`, `claude`, `agy`, `copilot`, `opencode`, `node`, and Docker.

## Auth

- `codex` can authenticate and remain logged in across `ai-sandbox rm`.
- `claude` can authenticate and remain logged in across `ai-sandbox rm`.
- `agy` can authenticate and remain logged in across `ai-sandbox rm`.
- `copilot` can authenticate and remain logged in across `ai-sandbox rm`.
- `opencode` can authenticate and remain logged in across `ai-sandbox rm`.

## T3

- `ai-sandbox t3` starts a server reachable at the printed workspace-specific `127.x.y.z:3773` URL.
- The host browser can reach the printed T3 URL.
- Running two T3 sandboxes from different workspaces prints different loopback hosts; opening the exact printed URLs keeps both browser sessions connected.
- T3 can create a Codex-backed session after Codex is authenticated.

## Cursor

- `cursor --version` and `cursor-agent --version` report the same Cursor CLI release.
- `ai-sandbox cursor` starts Cursor CLI, and Cursor authentication survives container recreation.

## Published web ports

- `docker port <container-name>` shows bindings for `8080/tcp` and `3000/tcp` on matching ports at the workspace-specific host address.
- The shell banner prints all host-visible URLs.

## Reset semantics

- A marker written under `~/.agents` remains after `ai-sandbox --rebuild` and `ai-sandbox rm`.
- `ai-sandbox reset-config` restores preset files without deleting credentials.
- `ai-sandbox reset-config` restores the OpenCode preset without deleting OpenCode credentials.
- `ai-sandbox reset-state` wipes credentials and runtime data, including `~/.agents`, for only the current workspace.
- After `ai-sandbox reset-state`, Claude Code requires authentication again because its persisted state was intentionally removed.
