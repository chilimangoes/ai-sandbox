#!/usr/bin/env bash
set -euo pipefail

codex --version
gemini --version
copilot --version
opencode --version
codenomad --version
paseo --version
command -v lbzip2
command -v sudo
sudo -n true
node --version
npm --version
t3 --version >/dev/null 2>&1 || t3 --help >/dev/null
