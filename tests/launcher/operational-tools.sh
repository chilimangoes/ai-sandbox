#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
export TOOL_LOG="$task_dir/calls" TOOL_DOCKER_READY=true TOOL_PODMAN_READY=true TOOL_EXIT=0 TOOL_PODMAN_LOCAL=false TOOL_INFO_READY=true
cat > "$task_dir/engine-stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0")"
printf '%s' "$name" >> "$TOOL_LOG"
printf ' <%s>' "$@" >> "$TOOL_LOG"
printf '\n' >> "$TOOL_LOG"
case "$1" in
  --version) echo "$name version client-test" ;;
  info)
    [[ "$TOOL_INFO_READY" == true ]] || exit 17
    if [[ "$*" == *SELinuxEnabled* ]]; then echo false
    elif [[ "$*" == *Rootless* ]]; then echo true
    elif [[ "$TOOL_PODMAN_LOCAL" == true ]]; then echo false; else echo true; fi
    ;;
  version)
    ready="$TOOL_DOCKER_READY"
    [[ "$name" != podman ]] || ready="$TOOL_PODMAN_READY"
    [[ "$ready" == true ]] || exit 17
    if [[ "$*" == *Client* ]]; then echo client-test; else echo server-test; fi
    ;;
  ps) ;;
  *) exit "$TOOL_EXIT" ;;
esac
SH
chmod +x "$task_dir/engine-stub"
ln -s engine-stub "$task_dir/docker"
ln -s engine-stub "$task_dir/podman"
export PATH="$task_dir:$PATH"
source "$repo_root/scripts/lib/engine.sh"
# Compare the launcher and helper policy without a running engine.
helper_resolve="$(declare -f resolve_engine)"
eval "$(sed -n '/^engine_healthy() {$/,/^}$/p' "$repo_root/bin/ai-sandbox")"
eval "$(sed -n '/^resolve_engine() {$/,/^}$/p' "$repo_root/bin/ai-sandbox")"
[[ "$(resolve_engine auto)" == docker ]]
export TOOL_DOCKER_READY=false
[[ "$(resolve_engine auto)" == podman ]]
if resolve_engine docker 2>"$task_dir/error"; then exit 1; fi
export TOOL_DOCKER_READY=true
eval "$helper_resolve"
[[ "$(resolve_engine auto)" == docker ]]
export TOOL_DOCKER_READY=false
[[ "$(resolve_engine auto)" == podman ]]
if resolve_engine docker 2>"$task_dir/error"; then exit 1; fi
grep -q 'server is unreachable' "$task_dir/error"
engine_status ai_sandbox_no_such_engine
[[ "$ENGINE_CLIENT" == missing && "$ENGINE_READY" == false ]]
for invalid in INVALID Docker ''; do
  if resolve_engine "$invalid" 2>"$task_dir/error"; then exit 1; fi
  grep -q 'Invalid engine' "$task_dir/error"
done
export TOOL_DOCKER_READY=true
export TOOL_PODMAN_LOCAL=true
engine_status podman
[[ "$ENGINE_READY" == true && "$ENGINE_SERVER" == 'not applicable (local Podman engine client-test)' ]]
export TOOL_INFO_READY=false
engine_status podman
[[ "$ENGINE_READY" == false ]]
export TOOL_INFO_READY=true TOOL_PODMAN_LOCAL=false
for selected in docker podman; do
  export AI_SANDBOX_ENGINE="$selected"
  : > "$TOOL_LOG"
  bash "$repo_root/scripts/build-image.sh"
  pull=--pull
  [[ "$selected" != podman ]] || pull=--pull=always
  grep -Fq "$selected <build> <$pull> <-t> <ai-sandbox:latest> <$repo_root>" "$TOOL_LOG"
  other=docker
  [[ "$selected" != docker ]] || other=podman
  : > "$TOOL_LOG"
  bash "$repo_root/scripts/build-image.sh" --engine "$other" --no-cache
  grep -q "^$other <build>.*<--no-cache>" "$TOOL_LOG"
  : > "$TOOL_LOG"
  bash "$repo_root/tests/smoke/smoke.sh" --engine "$selected" --skip-build
  bash "$repo_root/tests/smoke/smoke.sh" --engine "$selected" --skip-build
  [[ "$(grep -c "^$selected <run>.*</opt/ai-sandbox/image-smoke-check.sh>" "$TOOL_LOG")" == 2 ]]
  [[ "$(grep '<run>' "$TOOL_LOG" | sort -u | wc -l)" == 2 ]]
  bash "$repo_root/scripts/doctor.sh" --engine "$selected" > "$task_dir/status"
  grep -qx "engine: $selected" "$task_dir/status"
  grep -qx 'client: client-test' "$task_dir/status"
  grep -qx 'server: server-test' "$task_dir/status"
  grep -qx 'ready: true' "$task_dir/status"
  : > "$TOOL_LOG"
  bash "$repo_root/tests/launcher/image-runtime.sh" --engine "$selected" > "$task_dir/runtime"
  [[ "$(grep -c "^$selected <run>" "$TOOL_LOG")" == 4 ]]
  grep -q '<-v>.*:/repo:ro>' "$TOOL_LOG"
  if [[ "$selected" == podman ]]; then grep -q '<--userns=keep-id> <--user> <0>' "$TOOL_LOG"; fi
done
export TOOL_EXIT=23
if bash "$repo_root/scripts/build-image.sh" --engine podman; then exit 1; fi
if bash "$repo_root/tests/smoke/smoke.sh" --engine podman --skip-build; then exit 1; fi
export TOOL_PODMAN_READY=false
if bash "$repo_root/scripts/doctor.sh" --engine podman > "$task_dir/status" 2> "$task_dir/error"; then exit 1; fi
grep -q 'ready=false' "$task_dir/status"
grep -q 'podman machine start' "$task_dir/error"
if bash "$repo_root/scripts/build-image.sh" --engine 2> "$task_dir/error"; then exit 1; fi
grep -q 'Missing engine' "$task_dir/error"
if bash "$repo_root/scripts/doctor.sh" --skip-build 2> "$task_dir/error"; then exit 1; fi
grep -q 'only accepts' "$task_dir/error"
mkdir "$task_dir/missing-bin"
ln -s "$(command -v dirname)" "$task_dir/missing-bin/dirname"
if PATH="$task_dir/missing-bin" /bin/bash "$repo_root/scripts/doctor.sh" --engine docker > "$task_dir/status" 2> "$task_dir/error"; then exit 1; fi
grep -q 'client=missing' "$task_dir/status"
grep -q 'client is missing' "$task_dir/error"
echo 'operational-tools.sh passed'
