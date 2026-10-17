# Manual verification checklist

Use disposable workspaces for reset checks. Repeat this checklist for each available host and engine pair. Keep enforcing SELinux acceptance pending until an enforcing host passes it.

Acceptance used Docker Engine 29.1.3 and Podman 6.1.4, including the Windows Podman client/server and native Linux Podman. These are tested versions, not minimum requirements.

## Host setup

- Verify Windows PowerShell with Docker Desktop and native rootful Podman Machine separately.
- Verify Linux Bash with Docker Engine and rootless Podman separately.
- Verify the host doctor reports the selected engine, client/server versions, and readiness. Local Linux Podman has no separate server.
- Confirm the workspace and supplemental folders are accessible to that engine.
- With both engines healthy, confirm automatic selection prefers Docker.
- Confirm `--engine` overrides `AI_SANDBOX_ENGINE`, and an explicit unavailable engine fails without fallback.

## Container and mounts

- Confirm `ai-sandbox` opens a shell in `/workspace/<project-folder-slug>`.
- Check the banner lists installed tools and all five reserved host endpoints.
- Confirm workspace writes appear on the host, including a workspace path with spaces.
- Confirm a read-only supplemental mount rejects writes and a read-write mount preserves host writes.
- On Windows, include drive-letter and OneDrive-backed paths when available.
- On Linux Podman, confirm rootless operation, subordinate ID ranges, and successful initialization with `--userns=keep-id --user 0`.

## Tools and services

- Confirm `ai-sandbox doctor` reports installed coding-tool versions inside the container.
- Confirm tool arguments reach their intended CLI unchanged.
- Confirm T3, CodeNomad, and Paseo start without an interactive TTY and advertise their inspected host endpoints.
- Confirm both application ports respond when applications listen on container ports 8080 and 3000.
- Start two workspaces concurrently and verify all ten published endpoints.
- Compare the banner, service output, execution environment, and engine inspection for endpoint agreement.
- On Docker and native Linux, confirm workspace-specific loopback hosts with matching ports.
- On Windows Podman, confirm `127.0.0.1` and separate five-port blocks, bounded collision handling, restart reuse, and accurate URLs after recreation.
- Check simultaneous T3 browser sessions; Windows Podman's different ports do not separate cookies by host. If sessions interfere, try separate browser profiles.
- Confirm CodeNomad uses sandbox OpenCode and Paseo uses sandbox provider CLIs.
- Confirm default Paseo relay is disabled and `paseo_relay=1` enables it after restart.

## Persistence and destructive scope

**Warning:** `reset-state` deletes credentials and runtime state for the selected workspace and engine. Use owned disposable fixtures for this check.

- Authenticate required tools, including Claude Code, separately in each engine and confirm recreation preserves that engine's credentials.
- Write distinct markers to config, auth, data, and cache in each engine for the same workspace.
- Confirm `ai-sandbox stop` preserves the container and all volumes.
- Confirm `ai-sandbox rm` preserves all four volumes, including `~/.agents` data.
- Confirm `ai-sandbox reset-config` restores defaults and preserves credentials and most runtime data.
- Confirm `ai-sandbox --update` and `ai-sandbox --rebuild` use the selected engine and preserve state.
- Confirm image, mount, and incompatible endpoint changes recreate the container.
- Run stop, removal, config reset, and state reset in each engine; confirm the other engine's resources and files remain intact.
- Confirm `ai-sandbox reset-state` removes only the selected engine's four workspace volumes and requires fresh authentication afterward.
- Confirm shared host workspace files and `.ai-sandbox` supplemental mappings survive reset and remain visible to both engines.

## Enforcing SELinux gate

- On an enforcing Linux host with rootless Podman, confirm private workspace `:Z` and shared supplemental `:ro,z` and `:rw,z` labels permit expected access.
- Confirm read-only mounts reject writes and read-write mounts persist writes without disabling SELinux separation.
- Record this gate as unverified until native enforcing-host acceptance passes. Automated argument checks and SELinux-disabled Linux runs do not satisfy it.
