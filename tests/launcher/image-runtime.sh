#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$repo_root/scripts/lib/engine.sh"
parse_engine_options "$@"
[[ "$NO_CACHE" == false && "$SKIP_BUILD" == false ]] || { echo 'image-runtime only accepts --engine.' >&2; exit 1; }
ENGINE_COMMAND="$(resolve_engine "$REQUESTED_ENGINE")"
prefix="ai-sandbox-image-runtime-$ENGINE_COMMAND-$(cat /proc/sys/kernel/random/uuid)"
container_name=''
cleanup() {
  local status=$? names name
  trap - EXIT
  if [[ -n "$container_name" ]]; then
    names="$(engine ps -a --format '{{.Names}}')" || exit 1
    while IFS= read -r name; do
      if [[ "${name#/}" == "$container_name" ]]; then engine rm -f "$container_name" >/dev/null || exit 1; fi
    done <<<"$names"
  fi
  exit "$status"
}
trap cleanup EXIT
mount_mode=ro
namespace_args=()
if [[ "$ENGINE_COMMAND" == podman ]]; then
  if [[ "$(engine info --format '{{.Host.Security.SELinuxEnabled}}')" == true ]]; then mount_mode=ro,z; fi
  if [[ "$(engine info --format '{{.Host.Security.Rootless}}')" == true ]]; then namespace_args=(--userns=keep-id --user 0); fi
fi
for test in claude-config-runtime cursor-config-runtime entrypoint-bootstrap-concurrency paseo-workspace-registry; do
  container_name="$prefix-$test"
  test_args=()
  [[ "$test" != paseo-workspace-registry ]] || test_args=(/repo/docker/entrypoint.sh)
  engine run --rm --name "$container_name" "${namespace_args[@]}" -v "$repo_root:/repo:$mount_mode" \
    ai-sandbox:latest bash "/repo/tests/launcher/$test.sh" "${test_args[@]}"
  printf '%s passed (%s)\n' "$test" "$ENGINE_COMMAND"
done
