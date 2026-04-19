# Config Management

## Source of truth

Repo-managed defaults live under `configs/` and are copied into the image at build time. They are not bind-mounted from the host.

You can change the defaults by editing them here in this repo. To change the configuration for an existing sandbox, edit the desired config file in the container's `/state/config/` folder. An easy way to edit files within sandbox container volumes (or other Docker volumes for that matter) is to connect to the container using the "Container Tools" extension in VS Code.

## State classes

Three state classes matter in v1:

- Default presets: version-controlled files in this repo and image-baked copies under `/opt/ai-sandbox/defaults/configs`
- Persisted config: mutable files under `/state/config`
- Persisted runtime state: auth, session data, and caches under `/state/auth`, `/state/data`, and `/state/cache`

## Initialization rules

On first launch for a workspace:

- the launcher creates the four state volumes
- bootstrap copies missing default config files into `/state/config`
- tool home paths are linked to those persisted locations

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

## Tool inventory

Codex:

- default config: `/state/config/codex/config.toml`
- auth target: `/state/auth/codex/auth.json`
- session data: `/state/data/codex/`

Gemini:

- default config: `/state/config/gemini/settings.json`
- auth target: `/state/auth/gemini/`
- runtime home: `~/.gemini`

Copilot:

- default config: `/state/config/copilot/config.json`
- auth and session data: `~/.copilot/` mapped into `/state/auth/copilot` and `/state/data/copilot`

OpenCode:

- default config: `/state/config/opencode/opencode.json`
- auth target: `/state/auth/opencode/auth.json`
- runtime data: `/state/data/opencode/`
- cache target: `/state/cache/opencode/`
- XDG paths are wired so `~/.config/opencode/` and `~/.local/share/opencode/` persist through the `/state` volumes

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
- `ai-sandbox t3` sets `T3CODE_HOME=/state/data/t3` so T3 state persists per workspace

## Update behavior

- `--update` rebuilds the shared image with refreshed base and npm packages, then keeps using the current workspace container unless it needs to be recreated
- `--rebuild` rebuilds the shared image with refreshed base and npm packages, then always removes and recreates the workspace container
- both flows preserve all state volumes by default
