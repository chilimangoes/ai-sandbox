#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "$REPO_ROOT/scripts/lib/engine.sh"
parse_engine_options "$@"
ENGINE_COMMAND="$(resolve_engine "$REQUESTED_ENGINE")"
container_name="ai-sandbox-smoke-$ENGINE_COMMAND-$(cat /proc/sys/kernel/random/uuid)"
cleanup() {
  local status=$? names
  trap - EXIT
  if ! names="$(engine ps -a --format '{{.Names}}')"; then exit 1; fi
  while IFS= read -r name; do
    if [[ "${name#/}" == "$container_name" ]]; then
      engine rm -f "$container_name" >/dev/null || exit 1
    fi
  done <<<"$names"
  exit "$status"
}
if [[ "$SKIP_BUILD" == false ]]; then
  build_options=(--engine "$ENGINE_COMMAND")
  [[ "$NO_CACHE" == false ]] || build_options+=(--no-cache)
  bash "$REPO_ROOT/scripts/build-image.sh" "${build_options[@]}"
fi
trap cleanup EXIT
engine run --rm --name "$container_name" ai-sandbox:latest /opt/ai-sandbox/image-smoke-check.sh
