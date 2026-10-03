#!/usr/bin/env bash
set -euo pipefail

printf 'uid=%s\n' "$(id -u)"
printf '{"owner":%s}\n' "$(id -u)" > "$HOME/.claude.json"
