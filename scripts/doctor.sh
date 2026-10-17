#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/engine.sh"
parse_engine_options "$@"
[[ "$NO_CACHE" == false && "$SKIP_BUILD" == false ]] || { echo 'doctor only accepts --engine.' >&2; exit 1; }
if ! ENGINE_COMMAND="$(resolve_engine "$REQUESTED_ENGINE")"; then
  for name in docker podman; do
    [[ "$REQUESTED_ENGINE" == auto || "$REQUESTED_ENGINE" == "$name" ]] || continue
    engine_status "$name"
    echo "$name: client=$ENGINE_CLIENT; server=$ENGINE_SERVER; ready=$ENGINE_READY"
  done
  exit 1
fi
engine_status "$ENGINE_COMMAND"
printf 'engine: %s\nclient: %s\nserver: %s\nready: %s\n' "$ENGINE_COMMAND" "$ENGINE_CLIENT" "$ENGINE_SERVER" "$ENGINE_READY"
echo "bash: ${BASH_VERSION:-unavailable}"
