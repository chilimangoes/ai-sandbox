# ai-sandbox

`ai-sandbox` runs AI coding tools against your project directory in a Docker or native Podman container on Windows and Linux.

## Overview

- Run `ai-sandbox` to open a shell in `/workspace/<project-folder-slug>`.
- Run coding CLIs with configuration, authentication, data, and caches persisted in four named volumes per workspace and engine.
- Run `ai-sandbox t3`, `ai-sandbox codenomad`, or `ai-sandbox paseo` to start a service for the current terminal session.
- Open the exact service URLs printed by the launcher. Windows Podman uses localhost ports; Docker and native Linux use workspace-specific loopback addresses.
- Mount optional supplemental host folders read-only or read-write under `/supplemental`.
- Refresh installed tools explicitly with `--update` or `--rebuild`.

Docker and Podman keep separate images, containers, and persisted state. Switching engines requires separate tool sign-in. Workspace files remain shared host files.

## Included tools

The image includes these tools:

- Codex CLI
- Claude Code CLI
- Antigravity CLI
- GitHub Copilot CLI
- OpenCode
- Cursor CLI, exposed as `cursor` and `cursor-agent`
- T3 Code
- CodeNomad
- Paseo, with public relay connectivity disabled by default

## Supported environments

The verified environments are:

- Windows 11 with PowerShell and Docker Desktop
- Windows 11 with PowerShell and native Podman Machine using a rootful WSL connection
- Linux with Bash and Docker Engine
- Linux with Bash and rootless Podman, with SELinux disabled in live validation

Enforcing SELinux acceptance remains unverified and required before the Podman feature is complete. See [Linux prerequisites](docs/usage.md#linux).

## Quickstart

1. Set up an engine using the [Windows or Linux instructions](docs/usage.md#windows).
2. Add this repository's `bin` directory to your `PATH`.
3. Open a terminal in your workspace directory.
4. Run `ai-sandbox`.

Automatic selection prefers healthy Docker, then healthy Podman. Use `ai-sandbox --engine podman` to select Podman explicitly.

For more information, see these guides:

- [Usage and operational commands](docs/usage.md)
- [Architecture](docs/architecture.md)
- [Authentication](docs/auth.md)
- [Configuration management](docs/config-management.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Manual verification checklist](docs/manual-verification-checklist.md)
