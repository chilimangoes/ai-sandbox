# Config Management

## Source of truth

Repo-managed defaults live under `configs/` and are copied into the image at build time. They are not bind-mounted from the host.

You can change the defaults by editing them here in this repo. To change the configuration for an existing sandbox, edit the desired config file in the container's `/state/config/` folder. An easy way to edit files within sandbox container volumes (or other Docker volumes for that matter) is to connect to the container using the "Container Tools" extension in VS Code.

## State classes

Three state classes matter in v1:

- Default presets: version-controlled files in this repo and image-baked copies under `/opt/ai-sandbox/defaults/configs`
- Persisted config: mutable files under `/state/config`
- Persisted runtime state: auth, session data, and caches under `/state/auth`, `/state/data`, and `/state/cache`
- Host supplemental folder config: local or global host files that define extra bind mounts under `/supplemental`

## Initialization rules

On first launch for a workspace:

- the launcher creates the four state volumes
- bootstrap copies missing default config files into `/state/config`
- tool home paths are linked to those persisted locations
- `~/.agents` is linked to `/state/data/agents`

On normal later launches:

- existing config files stay untouched
- auth stays untouched
- caches and data stay untouched

## Reset commands

`reset-config`:

- preserves the `/workspace/<project-folder-slug>` bind mount
- preserves auth
- preserves most runtime data
- replaces persisted config files with the repo/image defaults

`reset-state`:

- removes the current workspace container
- removes config, auth, data, and cache volumes for that workspace
- reinitializes from image defaults on the next launch

`rm`:

- removes the current workspace container
- preserves config, auth, data, and cache volumes
- recreates the container from the current image on the next launch

`stop`:

- stops the current workspace container if it is running
- preserves the container and all state volumes
- allows the next launch to start the same container again

`doctor`:

- runs the sandbox's built-in diagnostics inside the current workspace container
- preserves the container and all state volumes

## Supplemental folder config

Supplemental folder mappings are host-side config because Docker bind mounts must be known when the container is created.

Local workspace config:

- `<workspace>/.ai-sandbox/supplemental-folders.config`

Global user config:

- Windows: `%USERPROFILE%\.ai-sandbox\supplemental-folders.config`
- Linux: `~/.ai-sandbox/supplemental-folders.config`

Each non-empty, non-comment line uses:

```text
host_path|container_name|mode
```

`mode` is optional and defaults to `ro`. Valid modes are `ro` and `rw`.

Example:

```text
D:\My_Project_Folder\skills|my-skills|ro
/home/me/shared-scratch|scratch|rw
```

Global mappings load first. Local mappings load second and override global mappings that target the same `/supplemental/<container_name>`.

Changing supplemental folder config recreates the workspace container on the next launch because the launcher stores a hash of the resolved supplemental mounts in the container's `ai-sandbox.supplemental-folders` label.

## Tool inventory

Shared agent metadata:

- runtime data: `/state/data/agents/`
- `~/.agents` is linked to the runtime directory so its contents survive container recreation

Codex:

- default config: `/state/config/codex/config.toml`
- auth target: `/state/auth/codex/auth.json`
- session data: `/state/data/codex/`

Claude Code:

- default and user settings: `/state/config/claude/settings.json`
- runtime home, authentication, and sessions: `/state/data/claude/home`
- top-level user state: `/state/data/claude/claude.json`
- `~/.claude/` is linked into the runtime home, with `~/.claude/settings.json` linked back to persisted config
- `~/.claude.json` is synchronized before and after each Claude invocation because it contains mutable app state rather than the normal user settings layer

Antigravity:

- default config: `/state/config/antigravity/settings.json`
- auth target: `/state/auth/antigravity/`
- runtime home: `~/.antigravity`

Copilot:

- default config: `/state/config/copilot/config.json`
- auth and session data: `~/.copilot/` mapped into `/state/auth/copilot` and `/state/data/copilot`

OpenCode:

- default config: `/state/config/opencode/opencode.json`
- auth target: `/state/auth/opencode/auth.json`
- runtime data: `/state/data/opencode/`
- cache target: `/state/cache/opencode/`
- XDG paths are wired so `~/.config/opencode/` and `~/.local/share/opencode/` persist through the `/state` volumes

Cursor:

- default config: `/state/config/cursor/cli-config.json`
- authentication: `/state/auth/cursor/auth.json` (Cursor's file credential backend)
- runtime and session data: `/state/data/cursor/`
- `~/.cursor/` is linked to the runtime directory, while `~/.cursor/cli-config.json` links back to the persisted config
- `~/.config/cursor/` is linked to the authentication directory
- the preset uses `approvalMode: unrestricted` and `autoAcceptWebSearch: true` for the sandbox's out-of-the-box YOLO behavior


CodeNomad:

- default config: `/state/config/codenomad/config.json`
- runtime data: `/state/data/codenomad/instances`
- TLS material: `/state/data/codenomad/tls`
- `~/.config/codenomad/` is wired into `/state` so CodeNomad server state survives container recreation

Shared sandbox config:

- default config: `/state/config/shared/sandbox.config`
- `paseo_relay=0` is the default and makes `ai-sandbox paseo` pass `--no-relay`; set `paseo_relay=1` to opt into Paseo's public relay; any other value keeps relay disabled

Paseo:

- default config: `/state/config/paseo/config.json`
- runtime home: `/state/data/paseo`
- `PASEO_HOME=/state/data/paseo`
- `config.json` inside `PASEO_HOME` is symlinked back to `/state/config/paseo/config.json` so `reset-config` can restore defaults without wiping runtime state

T3:

- default config: `/state/config/t3/config.json`
- runtime data: `/state/data/t3/`
- `ai-sandbox t3` sets `T3CODE_HOME=/state/data/t3` and starts T3 with `--base-dir /state/data/t3` so T3 state persists per workspace

## Update behavior

- `--update` rebuilds the shared image with refreshed base and npm packages, then keeps using the current workspace container unless it needs to be recreated
- `--rebuild` rebuilds the shared image with refreshed base and npm packages, then always removes and recreates the workspace container
- `--update`, `--rebuild`, and `rm` preserve `/state/data/agents` in the workspace data volume
- `reset-state` removes `/state/data/agents` along with the other persisted workspace state
