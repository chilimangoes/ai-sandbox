# Troubleshooting

## Engine client is missing

Run the host doctor from the repository root using the [platform-specific diagnostic command](usage.md#build-diagnose-and-smoke-check). A missing client differs from an installed client whose server is unreachable.

Install the selected engine and make its native CLI available on `PATH`. Use the official [Podman installation guide](https://podman.io/docs/installation) for Podman. For Docker, retain Docker Desktop on Windows or Docker Engine on Linux.

An explicit `--engine` selection fails without fallback. Automatic mode prefers healthy Docker, then healthy Podman. Check `AI_SANDBOX_ENGINE` if the launcher selects an unexpected engine.

## Engine server is unavailable

On Windows Docker, start Docker Desktop. On Linux Docker, ask the host administrator to restore daemon access for your user.

For Windows Podman, inspect machine and connection state with these read-only commands:

```powershell
podman machine list
podman system connection list
podman version
```

Start the intended existing machine in Podman Desktop, then rerun the host doctor. If the doctor suggests a machine-start command, use the name of that machine. Complete any required Windows consent or WSL setup through the official installer. Follow the [rootful Windows setup](usage.md#windows) if no machine exists.

The launcher and host doctor never initialize, start, reset, or reconfigure machines automatically. A working client version alone does not prove server readiness.

## Workspace mount fails on Windows

For Docker Desktop with Hyper-V, check the workspace drive or folder in **Settings > Resources > File sharing**. The WSL 2 backend shares host files automatically; check host-folder permissions and local file availability instead. For OneDrive, make sure workspace files are available locally. See [Docker Desktop file sharing](https://docs.docker.com/desktop/settings-and-maintenance/settings/#file-sharing).

For Podman, confirm that the selected machine can access the host folder and that its native connection is reachable. Docker Desktop drive-sharing settings do not configure Podman mounts.

Run from PowerShell in the intended workspace. Both launchers preserve paths containing spaces. Check that supplemental source directories exist and that read-only mappings are intentional.

## Rootless Podman prerequisites are missing

Run the launcher as your regular Linux user. `podman info` must succeed and report rootless operation. The Linux launcher rejects rootful Podman.

Ask an administrator to assign at least 65536 subordinate UIDs and GIDs in `/etc/subuid` and `/etc/subgid`. Log out and back in after assignment. If namespace, storage, or networking errors remain, follow your distribution's [Podman installation instructions](https://podman.io/docs/installation).

The launcher uses `--userns=keep-id --user 0`; do not replace it with an unverified namespace policy. Initialization needs container-root privileges, and `sandbox` maps to your host UID.

## SELinux mount denials

Enforcing SELinux acceptance remains unverified and required before whole-feature completion. Validate access as a regular user with rootless Podman on an enforcing Linux host.

When Podman reports SELinux enabled, the launcher uses private `:Z` labeling for the workspace and shared `:ro,z` or `:rw,z` for supplemental mounts. Ask the administrator to inspect audit denials and confirm that the intended directories permit relabeling. Avoid mapping system directories or an entire home directory that other confined services need.

For a path that cannot be relabeled, Podman provides the explicit native option `--security-opt label=disable`. It disables SELinux separation for the container. The launcher has no passthrough option for it and never selects it automatically. Prefer a dedicated relabelable project directory; discuss any custom native invocation with the administrator. See [Podman labeling guidance](https://docs.podman.io/en/v6.1.3/markdown/podman-run.1.html#volume-v-source-volume-host-dir-container-dir-options).

## Port conflict or Windows Podman port exhaustion

Open the exact endpoint printed by the launcher. Docker and native Linux Podman use workspace-specific loopback addresses with matching ports. Windows Podman uses `127.0.0.1` and five-port blocks in `20000-49999`.

If a bind conflict occurs, identify the process or container owning that exact endpoint before stopping it. Windows Podman tries up to 32 candidate blocks. The error `No available Podman localhost port block after 32 attempts in 20000-49999.` means those candidates were unavailable.

Release an identified conflicting endpoint, then retry the launcher. Forwarding sockets can take time to close after removal. Follow newly printed URLs after recreation because the host ports can change. An unreachable Podman Machine or broken forwarding requires machine recovery, not repeated state resets.

If a printed service URL does not respond, start its service command first. Shell mode reserves ports without starting T3, CodeNomad, or Paseo.

## T3 disconnects with concurrent sandboxes

Open each exact printed URL. Docker's distinct loopback hosts keep browser cookies separate. Replacing them with `localhost` defeats that separation.

Windows Podman uses different ports on `127.0.0.1`; browser cookies share that host. If sessions interfere, try separate browser profiles.

## Configuration or authentication differs after switching engines

Docker and Podman have separate config, auth, data, and cache volumes. Select the original engine to recover its state, or authenticate separately in the other engine. There is no automatic state migration.

Normal startup preserves persisted configuration and credentials. `reset-config` restores presets; `reset-state` deletes all four workspace volumes only in the selected engine. Host workspace files and host supplemental mapping files remain shared.

## Installed tool is unavailable or outdated

Run `ai-sandbox doctor` to inspect installed tools inside the selected workspace container. Use the host doctor first if the engine itself is unavailable.

Run `ai-sandbox --update` to refresh the image. Run `ai-sandbox --rebuild` to refresh the image and force container recreation. Explicit updates bypass the build cache; releases published after a build require another update. Configuration, credentials, data, and caches survive recreation.

## Service cannot use a coding CLI

Authenticate the provider CLI inside the selected engine's sandbox. T3 uses Codex; CodeNomad uses OpenCode; Paseo uses the provider CLIs it orchestrates. For Claude Code or Cursor login failures, follow [Authentication](auth.md).

For Paseo local connectivity, check the printed daemon address and `daemon.allowedHosts` in `/state/config/paseo/config.json`. Rerun `ai-sandbox paseo` after an interrupted session to clean leftover daemon state.

Paseo relay connectivity defaults to disabled through `PASEO_RELAY_ENABLED=0`. Set `paseo_relay=1` in `/state/config/shared/sandbox.config`, then restart Paseo to enable relay pairing. `reset-config` restores the disabled default.
