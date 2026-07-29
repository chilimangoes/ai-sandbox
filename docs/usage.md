# Usage

## Command reference

From a workspace directory:

- `ai-sandbox`: start or attach and open the interactive shell
- `ai-sandbox shell`: same as the default command
- `ai-sandbox codex`: run Codex CLI in the sandbox
- `ai-sandbox claude`: run Claude Code CLI in the sandbox
- `ai-sandbox agy`: run Antigravity CLI in the sandbox
- `ai-sandbox copilot`: run Copilot CLI in the sandbox
- `ai-sandbox opencode`: run OpenCode in the sandbox
- `ai-sandbox cursor`: run Cursor CLI in the sandbox
- `ai-sandbox cursor-agent`: run Cursor CLI using its upstream command name
- `ai-sandbox t3`: start T3 in the sandbox for the current terminal session
- `ai-sandbox codenomad`: start CodeNomad in the sandbox for the current terminal session
- `ai-sandbox paseo`: start the Paseo daemon in the sandbox for the current terminal session
- `ai-sandbox --add-folder <path>`: add a supplemental host folder mapping under `/supplemental`

Maintenance:

- `ai-sandbox doctor`: run the in-container diagnostics for the current workspace sandbox
- `ai-sandbox stop`: stop the current workspace container without deleting it
- `ai-sandbox rm`: remove the current workspace container but keep its persisted volumes
- `ai-sandbox reset-config`: restore persisted config files from the image defaults while preserving auth and most runtime data
- `ai-sandbox reset-state`: remove the current workspace container and all persisted state volumes for that workspace, including auth
- `ai-sandbox --update`: rebuild the shared image, then reuse the existing workspace container unless it needs to be recreated
- `ai-sandbox --rebuild`: rebuild the shared image and always remove and recreate the workspace container

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

Install:

1. Add [bin/ai-sandbox](bin/ai-sandbox) to your `PATH`.
2. Run it from any workspace directory.

Notes:

- The launcher passes `LOCAL_UID` and `LOCAL_GID` into the container.
- Shell and tool commands run as root inside the sandbox, so files created in `/workspace/<project-folder-slug>` may be owned by root on Linux hosts.

## T3 access

- Host URL: `http://<workspace-127.x.y.z>:3773`
- The host address is a workspace-specific loopback address, such as `127.91.42.17`, derived from the workspace path.
- The shell banner prints the chosen URL for the current workspace sandbox.
- Open the exact printed URL. Do not rewrite it to `localhost` or `127.0.0.1` when running multiple T3 sandboxes at once, because T3 browser cookies are scoped by host.
- The URL is not live in plain shell mode; run `ai-sandbox t3` or `t3` inside the sandbox shell before opening it in a browser.

## CodeNomad access

- Host URL: `http://<workspace-127.x.y.z>:9899`
- The shell banner prints the chosen URL for the current workspace sandbox.
- The URL is not live in plain shell mode; run `ai-sandbox codenomad` or `codenomad` inside the sandbox shell before opening it in a browser.
- CodeNomad runs inside the sandbox and uses the sandbox's `opencode` binary, config, auth, and workspace files.

## Paseo access

- Host daemon address: `<workspace-127.x.y.z>:6767`
- The shell banner prints the chosen address for the current workspace sandbox.
- Run `ai-sandbox paseo` or `paseo` inside the sandbox shell to start the daemon in the foreground.
- Use the Paseo CLI, app, or other clients to connect to that daemon.
- Paseo runs inside the sandbox and orchestrates the sandbox's installed coding CLIs.
- The sandbox starts Paseo with `--no-relay` by default so daemon traffic stays local to the host/container boundary.
- To opt into Paseo's public relay, edit `/state/config/shared/sandbox.config` inside the sandbox and set `paseo_relay=1`; any other value keeps `--no-relay` enabled.

## Published web ports

- All published services use the same workspace-specific host address.
- Container ports `8080` and `3000` are published on matching host ports at that address.
- The shell banner prints all host-visible URLs for the current workspace sandbox.

## Supplemental folders

Supplemental folders let you bind-mount host directories into the sandbox outside the main workspace. They are mounted in the container under `/supplemental/<name>`.

Mappings can be local to the current workspace or global to the current host user. Local mappings override global mappings with the same `/supplemental/<name>` target and print a warning.

Supplemental folder definitions for the current workspace are stored in `<workspace>/.ai-sandbox/supplemental-folders.config` and globally under `~/.ai-sandbox/supplemental-folders.config`

#### Parameters
- `--as <mount-point-alias>`: Change the name of the mount point within the container. If `--as` is omitted, the container folder name defaults to the host folder name. Supplemental folders are read-only by default.
- `--global`: This flag adds the supplimental folder definition to the global config rather than the local workspace config. Entries are added to the local config by default.
- `--read-write`: Use this flag to allow the sandbox to modify the host folder. Supplemental folders are added as read-only by default.

#### Interactive example:

```powershell
ai-sandbox --add-folder "D:\My_Project_Folder\skills"
```

#### Scripted examples:

```powershell
ai-sandbox --add-folder "D:\My_Project_Folder\skills" --as my-skills --global --read-only
ai-sandbox --add-folder "D:\Shared\scratch" --as scratch --local --read-write --yes
```

**NOTE:** New or changed supplemental folders require recreating the workspace container. `--add-folder` asks whether to run `ai-sandbox --rebuild` after updating the config.
