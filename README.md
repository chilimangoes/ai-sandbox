# ai-sandbox

`ai-sandbox` is a Docker-only workspace sandbox for running AI coding tools against the current project directory on Windows and Linux hosts.

## v1 behavior

- `ai-sandbox` opens an interactive shell in `/workspace/<project-folder-slug>`
- shell startup prints a short banner with `codex`, `gemini`, `copilot`, `opencode`, `t3`, `codenomad`, and `paseo`, plus the selected T3, CodeNomad, and Paseo addresses
- `ai-sandbox t3` starts T3 for the current terminal session; ending the session stops T3
- `ai-sandbox codenomad` starts CodeNomad server/web mode for the current terminal session; ending the session stops CodeNomad
- `ai-sandbox paseo` starts the Paseo daemon for the current terminal session; ending the session stops Paseo; public relay connectivity is disabled by default
- auth persists only inside Docker volumes owned by the sandbox
- updates happen only through explicit `--update` or `--rebuild`

## Included tools

- Codex CLI
- Gemini CLI
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
5. Use `codex`, `gemini`, `copilot`, `opencode`, `t3`, `codenomad`, or `paseo` from inside the sandbox shell.

Further details live in:

- [docs/architecture.md](docs/architecture.md)
- [docs/usage.md](docs/usage.md)
- [docs/auth.md](docs/auth.md)
- [docs/config-management.md](docs/config-management.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
