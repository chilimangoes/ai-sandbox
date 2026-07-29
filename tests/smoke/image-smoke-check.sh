#!/usr/bin/env bash
set -euo pipefail

/opt/ai-sandbox/bin/codex --version
/opt/ai-sandbox/bin/claude --version
/opt/ai-sandbox/bin/agy --version
/opt/ai-sandbox/bin/copilot --version
/opt/ai-sandbox/bin/opencode --version
/opt/ai-sandbox/bin/cursor-agent --version
/opt/ai-sandbox/bin/cursor --version
/opt/ai-sandbox/bin/codenomad --version
/opt/ai-sandbox/bin/paseo --version
command -v lbzip2
command -v sudo
sudo -n true
node --version
npm --version
/opt/ai-sandbox/bin/t3 --version >/dev/null 2>&1 || /opt/ai-sandbox/bin/t3 --help >/dev/null
