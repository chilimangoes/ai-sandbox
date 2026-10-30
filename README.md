# ai-sandbox

`ai-sandbox` is a Docker-only workspace sandbox for running AI coding tools against the current project directory on Windows and Linux hosts.

## Overview

- `ai-sandbox` opens an interactive shell in `/workspace/<project-folder-slug>`
- shell startup lists the available tools and prints the T3 and published web app URLs
- `ai-sandbox t3` starts T3 for the current terminal session; ending the session stops T3
- each sandbox container publishes T3 and web app ports on one workspace-specific `127.x.y.z` host address with matching host/container ports
- default web app ports are 8080 and 3000
- optional supplemental host folders can be mounted read-only or read-write under `/supplemental`
- auth persists only inside Docker volumes owned by the sandbox
- shared base image updates happen through explicit `--update` or `--rebuild`

## Included tools

- Codex CLI
- Claude Code CLI
- Antigravity CLI
- GitHub Copilot CLI
- OpenCode
- T3 Code

## Supported environments

- Windows 11 with Docker Desktop and PowerShell
- Linux with Docker Engine and a POSIX shell

## Quickstart

1. Install Docker.
2. Add the `/bin` directory your `PATH`.
3. Change into any workspace directory.
4. Run `ai-sandbox`.
5. Use `codex`, `claude`, `agy` (aka Antigravity), `copilot`, `opencode`, `cursor` (or upstream `cursor-agent`), or `t3` from inside the sandbox shell.

Further details live in:

- [docs/usage.md](docs/usage.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/auth.md](docs/auth.md)
- [docs/config-management.md](docs/config-management.md)
- [Custom workspace images](docs/custom-images.md)
- [Workspaces with shared services](docs/workspace-services.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
