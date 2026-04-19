# Usage

## Command reference

From a workspace directory:

- `ai-sandbox`: start or attach and open the interactive shell
- `ai-sandbox shell`: same as the default command
- `ai-sandbox codex`: run Codex CLI in the sandbox
- `ai-sandbox gemini`: run Gemini CLI in the sandbox
- `ai-sandbox copilot`: run Copilot CLI in the sandbox
- `ai-sandbox opencode`: run OpenCode in the sandbox
- `ai-sandbox t3`: start T3 in the sandbox for the current terminal session
- `ai-sandbox codenomad`: start CodeNomad in the sandbox for the current terminal session
- `ai-sandbox paseo`: start the Paseo daemon in the sandbox for the current terminal session

Maintenance:

- `ai-sandbox doctor`: run the in-container diagnostics for the current workspace sandbox
- `ai-sandbox stop`: stop the current workspace container without deleting it
- `ai-sandbox rm`: remove the current workspace container but keep its persisted volumes
- `ai-sandbox reset-config`: restore persisted config files from the image defaults while preserving auth and most runtime data
- `ai-sandbox reset-state`: remove the current workspace container and all persisted state volumes for that workspace, including auth
- `ai-sandbox --update`: rebuild the shared image, then reuse the existing workspace container unless it needs to be recreated
- `ai-sandbox --rebuild`: rebuild the shared image and always remove and recreate the workspace container
- `ai-sandbox --t3-port 3774`
- `ai-sandbox --codenomad-port 9901`
- `ai-sandbox --paseo-port 6768`

## Windows

Requirements:

- Windows 11
- Docker Desktop
- PowerShell 5.1+ or PowerShell 7+

Recommended install:

1. Add the `/bin` directory to your `PATH`.
2. Open PowerShell in a project directory and run `ai-sandbox`.

Notes:

- OneDrive-backed paths are supported as normal Docker Desktop bind mounts.
- The launcher resolves the current directory before calling Docker, so spaces in paths are safe.
- If Docker Desktop has not been granted access to the drive, the mount will fail; see troubleshooting.

## Linux

Requirements:

- Docker Engine
- `bash`
- `sha256sum`
- `ss` or `netstat` for port probing

Install:

1. Add [bin/ai-sandbox](bin/ai-sandbox) to your `PATH`.
2. Run it from any workspace directory.

Notes:

- The launcher passes `LOCAL_UID` and `LOCAL_GID` into the container.
- Files created in `/workspace/<project-folder-slug>` should map back to the invoking Linux user cleanly.

## T3 access

- Default host URL: `http://127.0.0.1:3773`
- If that port is occupied, the launcher auto-selects the next free port unless `--t3-port` is supplied.
- The shell banner prints the chosen URL for the current workspace sandbox.
- The URL is not live in plain shell mode; run `ai-sandbox t3` before opening it in a browser.

## CodeNomad access

- Default host URL: `http://127.0.0.1:9899`
- If that port is occupied, the launcher auto-selects the next free port unless `--codenomad-port` is supplied.
- The shell banner prints the chosen URL for the current workspace sandbox.
- The URL is not live in plain shell mode; run `ai-sandbox codenomad` before opening it in a browser.
- CodeNomad runs inside the sandbox and uses the sandbox's `opencode` binary, config, auth, and workspace files.

## Paseo access

- Default host daemon address: `127.0.0.1:6767`
- If that port is occupied, the launcher auto-selects the next free port unless `--paseo-port` is supplied.
- The shell banner prints the chosen address for the current workspace sandbox.
- Run `ai-sandbox paseo` to start the daemon in the foreground.
- Use the Paseo CLI, app, or other clients to connect to that daemon.
- Paseo runs inside the sandbox and orchestrates the sandbox's installed coding CLIs.
- The sandbox starts Paseo with `--no-relay` by default so daemon traffic stays local to the host/container boundary.
- To opt into Paseo's public relay, edit `/state/config/shared/sandbox.config` inside the sandbox and set `paseo_relay=1`; any other value keeps `--no-relay` enabled.
