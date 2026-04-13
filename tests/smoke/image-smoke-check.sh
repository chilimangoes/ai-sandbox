#!/usr/bin/env bash
set -euo pipefail

codex --version
gemini --version
copilot --version
node --version
npm --version
npx --yes t3 --version >/dev/null 2>&1 || npx --yes t3 --help >/dev/null
