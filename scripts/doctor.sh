#!/usr/bin/env bash
set -euo pipefail

echo "docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo daemon-unavailable)"
echo "bash: ${BASH_VERSION:-unavailable}"
