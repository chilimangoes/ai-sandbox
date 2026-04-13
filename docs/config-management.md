# Config Management

## Source of truth

Repo-managed defaults live under `configs/` and are copied into the image at build time. They are not bind-mounted from the host.

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

- preserves the workspace bind mount
- preserves auth
- preserves most runtime data
- replaces persisted config files with the repo/image defaults

`reset-state`:

- removes the current workspace container
- removes config, auth, data, and cache volumes for that workspace
- reinitializes from image defaults on the next launch

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

T3:

- default config: `/state/config/t3/config.json`
- runtime data: `/state/data/t3/`

## Update behavior

- `--update` rebuilds the shared image with refreshed base and npm packages, then recreates the container only if needed
- `--rebuild` always rebuilds the image and recreates the workspace container
- both flows preserve all state volumes by default
