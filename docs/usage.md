# Usage

## Select an engine

Both launchers accept `--engine auto|docker|podman`. Selection follows this precedence:

1. The `--engine` argument.
2. The `AI_SANDBOX_ENGINE` environment variable.
3. Automatic detection.

Automatic mode chooses healthy Docker first, then healthy Podman. An explicit unavailable engine fails without switching engines. `--engine auto` overrides an environment selection.

From a workspace directory, select Podman explicitly:

```text
ai-sandbox --engine podman shell
```

PowerShell and Bash can set the default for their current process:

```powershell
$env:AI_SANDBOX_ENGINE = 'podman'
```

```bash
export AI_SANDBOX_ENGINE=podman
```

Podman integration uses the native `podman` CLI. It requires no Docker compatibility socket, Docker CLI alias, or `DOCKER_HOST` setting.

## Windows

Windows requires the following:

- Windows 11 and PowerShell
- Docker Desktop or native Podman with a running Podman Machine
- Access to the workspace and supplemental host folders

For the verified Podman setup, use a rootful WSL machine:

1. Follow the official [Podman installation instructions](https://podman.io/docs/installation).
2. In Podman Desktop, open **Settings > Resources** and select **Create new** in the Podman tile.
3. Follow [Creating a Podman machine](https://podman-desktop.io/docs/podman/creating-a-podman-machine), with the WSL provider and **Machine with root privileges** enabled.
4. Start the machine in Podman Desktop.
5. Confirm the rootful connection using the [Podman connection guide](https://podman-desktop.io/docs/podman/setting-podman-machine-default-connection).
6. From this repository, run the host diagnostic:

   ```powershell
   powershell.exe -NoProfile -File scripts/doctor.ps1 -Engine podman
   ```

The diagnostic must report client and server versions and `ready: true`. The launcher never creates, starts, resets, or reconfigures a machine automatically.

Podman Desktop and the CLI have different machine defaults. Bare CLI machine initialization defaults to rootless; follow the rootful setup specified here. See [Podman machine initialization](https://docs.podman.io/en/stable/markdown/podman-machine-init.1.html).

Add this repository's `bin` directory to your `PATH`, then run the launcher from PowerShell in your workspace. Paths with spaces and OneDrive-backed workspaces passed Windows validation. For Docker Desktop mount access, see [Windows mount recovery](troubleshooting.md#workspace-mount-fails-on-windows).

## Linux

Linux requires the following:

- Bash and `sha256sum`
- Docker Engine accessible to your user, or working rootless Podman
- For Podman, user namespaces and at least 65536 subordinate UIDs and GIDs assigned in `/etc/subuid` and `/etc/subgid`

Follow the distribution-specific [Podman installation instructions](https://podman.io/docs/installation) for its namespace, storage, and networking dependencies. Run Podman as your regular user; `podman info` must succeed and report `rootless: true`.

Add this repository's `bin` directory to your `PATH`. Run `ai-sandbox` from your workspace.

Rootless Podman uses `--userns=keep-id --user 0`. Initialization runs as container root, while the `sandbox` user maps to your host UID. Claude Code runs as `sandbox`; shell and most other tools run as container root. These rootless container identities do not grant host root privileges. Docker shell writes can be owned by root on Linux hosts.

When Podman reports SELinux enabled, the launcher adds private `:Z` labeling to the workspace mount. Supplemental mounts use `:ro,z` or `:rw,z`. No relabel option is added when SELinux is disabled. See [Podman volume labeling](https://docs.podman.io/en/v6.1.3/markdown/podman-run.1.html#volume-v-source-volume-host-dir-container-dir-options).

Enforcing SELinux access remains unverified. Live acceptance on an enforcing host is required before whole-feature completion. See [SELinux recovery](troubleshooting.md#selinux-mount-denials).

## Commands

From a workspace directory, use these commands:

| Command | Result |
|---|---|
| `ai-sandbox` or `ai-sandbox shell` | Start or reuse the workspace container and open a shell |
| `ai-sandbox codex` | Run Codex; other tool names are `claude`, `agy`, `copilot`, `opencode`, `cursor`, and `cursor-agent` |
| `ai-sandbox t3`, `ai-sandbox codenomad`, or `ai-sandbox paseo` | Run the service in the foreground for this terminal session |
| `ai-sandbox doctor` | Run diagnostics inside the workspace container |
| `ai-sandbox stop` | Stop the workspace container, preserving it and its volumes |
| `ai-sandbox rm` | Remove the workspace container, preserving its four state volumes |
| `ai-sandbox reset-config` | Restore image defaults, preserving credentials and most runtime data |
| `ai-sandbox --update` | Refresh the engine's shared image; recreate an incompatible container when needed |
| `ai-sandbox --rebuild` | Refresh the engine's shared image and always recreate the workspace container |

**Warning:** `ai-sandbox reset-state` deletes the workspace's configuration, authentication, data, and cache volumes in the selected engine.

All stop, removal, and reset operations target only the selected engine and workspace. Use an explicit `--engine` for maintenance when both engines are installed. Engines keep separate images, containers, and four-volume state; switching engines does not migrate state. Host workspace files and supplemental mapping files are shared. See [Persistence boundaries](config-management.md#persistence-boundaries).

Cursor uses unrestricted approvals and automatic web-search acceptance. Both Cursor command names share persisted file credentials.

## Service addresses

Open the exact URLs printed by the shell banner or service startup output. Shell mode prints reserved addresses; start the corresponding service before opening its URL.

| Service | Container port |
|---|---|
| T3 | 3773 |
| CodeNomad | 9899 |
| Paseo daemon | 6767 |
| Alternate web application | 8080 |
| Application | 3000 |

Docker on both platforms and native Linux Podman publish matching host ports on a workspace-specific `127.x.y.z` address. Windows Podman publishes on `127.0.0.1` with workspace-specific blocks of five host ports in `20000-49999`. Host ports can change after recreation if a candidate block is occupied. See the [allocation contract](architecture.md#service-endpoints).

Docker's different loopback hosts separate browser cookies between workspaces. Windows Podman's different ports on `127.0.0.1` do not provide that separation. [HTTP cookies share a host across ports](https://www.rfc-editor.org/rfc/rfc6265.html#section-8.5). If browser sessions interfere, try separate browser profiles.

CodeNomad uses the sandbox's OpenCode installation, credentials, and workspace. Paseo clients connect to its printed daemon address and use the sandbox's provider CLIs.

Paseo relay connectivity is disabled by default through `PASEO_RELAY_ENABLED=0`. To enable it, set `paseo_relay=1` in `/state/config/shared/sandbox.config`, then restart Paseo. The launcher invokes `paseo daemon run --home /state/data/paseo`.

## Supplemental folders

Supplemental host folders appear under `/supplemental/<name>`. They default to read-only. Both engines read the same host mapping files:

- Workspace: `<workspace>/.ai-sandbox/supplemental-folders.config`
- User: `~/.ai-sandbox/supplemental-folders.config`

Use `--add-folder` with a host directory. The following syntax comes from launcher help; replace `HOST_FOLDER` with an existing directory:

```text
ai-sandbox --engine podman --add-folder HOST_FOLDER --as shared-files --local --read-only --yes
```

Use `--global` for user-wide mappings or `--read-write` to permit host writes. Local mappings override global mappings with the same target and print a warning. Changed mappings recreate the selected engine's container on its next launch. The interactive flow can offer an immediate rebuild.

## Build, diagnose, and smoke-check

Run helpers from the repository root. They use the same engine precedence as the launchers. PowerShell accepts `-Engine` and `--engine`; Bash accepts `--engine`.

Windows PowerShell examples:

```powershell
powershell.exe -NoProfile -File scripts/build-image.ps1 --engine podman
powershell.exe -NoProfile -File scripts/doctor.ps1 -Engine podman
powershell.exe -NoProfile -File tests/smoke/smoke.ps1 --engine podman --skip-build
```

Linux Bash examples:

```bash
bash scripts/build-image.sh --engine podman
bash scripts/doctor.sh --engine podman
bash tests/smoke/smoke.sh --engine podman --skip-build
```

Use `docker` instead of `podman` for Docker. Build helpers and smoke helpers accept `-NoCache` on PowerShell or `--no-cache` on Bash. Smoke builds first unless `-SkipBuild` or `--skip-build` selects an existing image. Its unique disposable container and cleanup stay in the selected engine.

Builds use the existing `Dockerfile` and `ai-sandbox:latest` tag in each engine's image store. Docker pulls with `--pull`; Podman uses `--pull=always`. Launcher `--update` and `--rebuild` also disable the build cache.

The host doctor reports the engine, client version, server version, and readiness. Local Linux Podman has no separate server. `ai-sandbox doctor` instead starts or reuses the workspace container and reports installed tools inside it.
