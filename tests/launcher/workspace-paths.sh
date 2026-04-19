#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$repo_root/bin/ai-sandbox"
entrypoint="$repo_root/docker/entrypoint.sh"

grep -Eq '\-v "\$\{WORKSPACE_PATH\}:\$\{CONTAINER_WORKSPACE_PATH\}"' "$launcher"
grep -Eq 'AI_SANDBOX_WORKSPACE_PATH=\$\{CONTAINER_WORKSPACE_PATH\}' "$launcher"
grep -Eq 'WORKSPACE_PATH="\$\{AI_SANDBOX_WORKSPACE_PATH:-/workspace\}"' "$entrypoint"
grep -Fq "cd '\$WORKSPACE_PATH'" "$entrypoint"

echo "workspace-paths.sh passed"
