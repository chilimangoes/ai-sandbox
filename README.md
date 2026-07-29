# ai-sandbox

`ai-sandbox` is a Docker-only workspace sandbox for running AI coding tools against the current project directory on Windows and Linux hosts.

## Overview

- `ai-sandbox` opens an interactive shell in `/workspace/<project-folder-slug>`
- shell startup prints a short banner with `codex`, `agy`, `copilot`, `opencode`, `cursor` (`cursor-agent`), `t3`, `codenomad`, and `paseo`, plus the selected T3, CodeNomad, Paseo, and published web-port addresses
- `ai-sandbox t3` starts T3 for the current terminal session; ending the session stops T3
- `ai-sandbox codenomad` starts CodeNomad server/web mode for the current terminal session; ending the session stops CodeNomad
- `ai-sandbox paseo` starts the Paseo daemon for the current terminal session; ending the session stops Paseo; public relay connectivity is disabled by default
- each sandbox container publishes T3, CodeNomad, Paseo, and web app ports on one workspace-specific `127.x.y.z` host address with matching host/container ports
- web app ports currently exposed are 8080 and 3000
- optional supplemental host folders can be mounted read-only or read-write under `/supplemental`
- auth persists only inside Docker volumes owned by the sandbox
- updates happen only through explicit `--update` or `--rebuild`

## Included tools

- Codex CLI
- Antigravity CLI
- GitHub Copilot CLI
- OpenCode
- T3 Code
- CodeNomad
- Paseo

## Supported environments

- Windows 11 with Docker Desktop and PowerShell
- Linux with Docker Engine and a POSIX shell

Unsupported in v1:

- Podman
- macOS hosts
- host credential import
- automatic per-launch updates

## Quickstart

1. Install Docker.
2. Add the `/bin` directory your `PATH`.
3. Change into any workspace directory.
4. Run `ai-sandbox`.
5. Use `codex`, `agy` (aka Antigravity), `copilot`, `opencode`, `cursor` (or upstream `cursor-agent`), `t3`, `codenomad`, or `paseo` from inside the sandbox shell.

Further details live in:

- [docs/usage.md](docs/usage.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/auth.md](docs/auth.md)
- [docs/config-management.md](docs/config-management.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
