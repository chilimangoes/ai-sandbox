#!/usr/bin/env bash
set -euo pipefail

codex --version
gemini --version
copilot --version
opencode --version
codenomad --version
node --version
npm --version
t3 --version >/dev/null 2>&1 || t3 --help >/dev/null
