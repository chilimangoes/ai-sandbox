#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

docker build -t ai-sandbox:latest "$REPO_ROOT"
docker run --rm ai-sandbox:latest /opt/ai-sandbox/image-smoke-check.sh
