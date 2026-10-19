# Architecture

## Host lifecycle

PowerShell on Windows and Bash on Linux implement the same workspace lifecycle:

1. Resolve the absolute workspace path and derive its slug and hash.
2. Select one healthy engine for the invocation.
3. Build the image if absent, or refresh it for `--update` or `--rebuild`.
4. Create or reuse the workspace container and four named volumes.
5. Inspect its actual host endpoints.
6. Execute the requested shell, tool, service, or diagnostic inside the container.

Selection follows `--engine`, then `AI_SANDBOX_ENGINE`, then automatic detection. Automatic detection prefers healthy Docker over healthy Podman. An explicit unavailable engine fails. All subsequent operations use the selected native CLI.

Podman builds the existing `Dockerfile`; no Docker compatibility socket is required. The historical `docker/` source directory remains shared by both engines.

Images, containers, and named volumes belong to separate engine stores. Each workspace gets one container and four volumes for config, auth, data, and cache in each engine. Resource names can match across stores without sharing their contents. Stop, removal, and reset operations affect only the selected engine's exact workspace resources.

The workspace and supplemental folders are host bind mounts. Both engines can change the same writable host files. Host `.ai-sandbox` mapping files are shared and survive state resets.

Windows Podman supports rootless and rootful connections. Rootless mode is recommended because the engine runs as an ordinary Linux user inside the virtual machine. This adds a security boundary while retaining access to writable host mounts. The two modes have separate image, container, and volume stores. The launcher uses Podman's configured default connection; it does not change the machine's mode.

## Container and state layout

The detached container runs an idle process. Later invocations execute commands inside it through the selected engine.

| Path | Purpose |
|---|---|
| `/workspace/<project-folder-slug>` | Host workspace bind mount |
| `/supplemental/<name>` | Optional host bind mounts |
| `/state/config` | Persisted editable configuration |
| `/state/auth` | Persisted credentials |
| `/state/data` | Persisted sessions and tool data |
| `/state/data/agents` | Shared agent metadata exposed as `~/.agents` |
| `/state/cache` | Persisted caches |
| `/opt/ai-sandbox/defaults/configs` | Image defaults from the repository |

Bootstrap creates missing state directories, copies missing presets, and links tool home paths into persisted state. Normal startup preserves existing configuration and credentials. `reset-config` restores presets; `reset-state` deletes all four workspace volumes in the selected engine.

The image uses `docker.io/library/debian:bookworm-slim`, Node.js 22, the coding tools listed in the [overview](../README.md#included-tools), and shared entrypoint scripts. Shell command shims dispatch through `/opt/ai-sandbox/entrypoint.sh` to binaries under `/opt/ai-sandbox/bin`.

Shell and most tools run as container root with `HOME=/home/sandbox`. Claude Code runs as `sandbox` because its permission-skipping mode rejects root. Its wrapper synchronizes mutable `~/.claude.json` around each invocation so atomic replacement survives recreation.

## Linux namespaces and mounts

The Bash launcher requires native Linux Podman to report rootless operation and have at least 65536 subordinate UIDs and GIDs. It uses `--userns=keep-id --user 0` to retain initialization privileges while mapping `sandbox` to the host user. Container root remains within the rootless user namespace.

When Podman reports SELinux enabled, workspace mounts use private `:Z` labeling. Supplemental mounts use shared `:ro,z` or `:rw,z` labeling. With SELinux disabled, the launcher adds no relabel options.

These label arguments have automated coverage; access on an enforcing host remains unverified. Enforcing-host acceptance is required before whole-feature completion. The launcher never disables SELinux separation automatically.

## Service endpoints

The container always uses these ports, in this order:

| Service | Container port |
|---|---|
| T3 | 3773 |
| CodeNomad | 9899 |
| Paseo | 6767 |
| Alternate HTTP | 8080 |
| Application | 3000 |

Docker on Windows and Linux, and rootless Podman on native Linux, publish matching host ports on a workspace-specific `127.x.y.z` loopback address.

Windows Podman uses the verified deterministic localhost strategy:

- Address: `127.0.0.1`
- Range: `20000-49999`, divided into 6000 disjoint blocks of five consecutive ports
- Hash input: lowercase absolute Windows workspace path encoded as UTF-8, hashed with SHA-256
- Initial block index: first eight hexadecimal hash digits interpreted as an unsigned integer, modulo 6000
- Candidate `n`: block index `(initial + n) % 6000`, starting at port `20000 + 5 * index`
- Bound: 32 candidate blocks, starting with `n=0`

The launcher reserves all five candidate ports on Windows before native creation and retries collisions within that bound. Host ports follow the service order in the table. Exhaustion reports `No available Podman localhost port block after 32 attempts in 20000-49999.`

Host addresses and host ports are separate from container ports. The launcher inspects the actual mappings after creation and before later execution. It passes those endpoints into the container's environment, banner, and rewritten service output. Compatible containers retain inspected mappings when restarted. Recreation selects an available block again, so host ports can change.

Image changes, supplemental mount changes, and incompatible endpoint mappings trigger scoped container recreation. Volumes remain intact. Port mappings are established at creation time.

Open the exact printed URLs. Docker's distinct loopback hosts separate browser cookies across workspaces. Windows Podman's distinct ports share `127.0.0.1` and do not provide that cookie separation.

## Services and diagnostics

T3, CodeNomad, and Paseo run in the foreground for the current terminal session. Shell mode prints reserved endpoints without starting these services. CodeNomad uses OpenCode inside the same container; Paseo orchestrates the installed provider CLIs.

Paseo runs with `PASEO_HOME=/state/data/paseo` and `PASEO_LISTEN=0.0.0.0:6767`. The entrypoint runs `paseo daemon run --home /state/data/paseo`. It derives `PASEO_RELAY_ENABLED` from `/state/config/shared/sandbox.config`: only `paseo_relay=1` enables relay connectivity.

Host doctor helpers report engine readiness and client/server versions. Local Linux Podman has no separate server. The launcher command `ai-sandbox doctor` runs installed-tool diagnostics inside the workspace container instead.
