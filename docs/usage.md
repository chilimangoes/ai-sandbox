# Usage

## Command reference

From a workspace directory:

- `ai-sandbox`: start or attach and open the interactive shell
- `ai-sandbox shell`: same as the default command
- `ai-sandbox codex`: run Codex CLI in the sandbox
- `ai-sandbox gemini`: run Gemini CLI in the sandbox
- `ai-sandbox copilot`: run Copilot CLI in the sandbox
- `ai-sandbox t3`: start T3 in the sandbox for the current terminal session

Maintenance:

- `ai-sandbox doctor`
- `ai-sandbox stop`
- `ai-sandbox rm`
- `ai-sandbox reset-config`
- `ai-sandbox reset-state`
- `ai-sandbox --update`
- `ai-sandbox --rebuild`
- `ai-sandbox --t3-port 3774`

## Windows

Requirements:

- Windows 11
- Docker Desktop
- PowerShell 5.1+ or PowerShell 7+

Recommended install:

1. Add [bin/ai-sandbox.ps1](bin/ai-sandbox.ps1) to your `PATH`.
2. Optionally add [bin/ai-sandbox.cmd](bin/ai-sandbox.cmd) for `cmd.exe`.
3. Open PowerShell in a project directory and run `ai-sandbox`.

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
- Files created in `/workspace` should map back to the invoking Linux user cleanly.

## T3 access

- Default host URL: `http://127.0.0.1:3773`
- If that port is occupied, the launcher auto-selects the next free port unless `--t3-port` is supplied.
- The shell banner prints the chosen URL for the current workspace sandbox.
- The URL is not live in plain shell mode; run `ai-sandbox t3` before opening it in a browser.
