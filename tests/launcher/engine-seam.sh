#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$repo_root/bin/ai-sandbox"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT

cat >"$temp_dir/docker" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1" == version ]]; then
  if [[ "${0##*/}" == docker ]]; then
    [[ "$AI_TEST_DOCKER_HEALTH" == 1 ]]
  else
    [[ "$AI_TEST_PODMAN_HEALTH" == 1 ]]
  fi
  exit $?
fi
if [[ "$1" == "${AI_TEST_FAIL_OPERATION:-}" || "$1 ${2:-}" == "${AI_TEST_FAIL_OPERATION:-}" ]]; then
  echo 'deliberate engine failure' >&2
  exit 23
fi
if [[ "${AI_TEST_MISSING:-0}" == 1 ]]; then
  echo 'resource not found' >&2
  exit 1
fi
case "$1" in
  ps) printf '%s\n' "$AI_TEST_NAMES" ;;
  image) printf '%s\n' "$AI_TEST_IMAGE" ;;
  inspect)
    if [[ "$3" == '{{.Image}}' ]]; then
      printf '%s\n' "$AI_TEST_IMAGE"
    else
      printf '%s\n' "$AI_TEST_LABELS"
    fi
    ;;
  port) printf '%s\n' "$AI_TEST_ENDPOINT" ;;
  volume)
    [[ "$2" != ls ]] || printf '%s\n' "${AI_TEST_VOLUME_NAMES:-$AI_TEST_NAMES}"
    ;;
  exec)
    if [[ -n "${AI_TEST_EXEC_LOG:-}" ]]; then
      printf '%s\n' "${0##*/}" "$@" >>"$AI_TEST_EXEC_LOG"
    fi
    ;;
  stop|rm) ;;
  *) echo 'unexpected engine invocation' >&2; exit 99 ;;
esac
SHIM
cp "$temp_dir/docker" "$temp_dir/podman"
chmod +x "$temp_dir/docker" "$temp_dir/podman"
export PATH="$temp_dir:$PATH"
export AI_TEST_DOCKER_HEALTH=1 AI_TEST_PODMAN_HEALTH=1

# Execute the actual argument parser and resolver without the lifecycle or Linux
# prerequisites owned by later tickets.
sed '/^ENGINE_COMMAND="$(resolve_engine /q' "$launcher" >"$temp_dir/selection.sh"
printf '\nprintf "%%s\\n" "$ENGINE_COMMAND"\n' >>"$temp_dir/selection.sh"
assert_selection() {
  local expected="$1" environment="$2"
  shift 2
  local actual
  actual="$(AI_SANDBOX_ENGINE="$environment" bash "$temp_dir/selection.sh" "$@")"
  [[ "$actual" == "$expected" ]]
}
assert_failure() {
  local environment="$1"
  shift
  if AI_SANDBOX_ENGINE="$environment" bash "$temp_dir/selection.sh" "$@" >"$temp_dir/output" 2>&1; then
    echo "Selection should have failed: $*" >&2
    exit 1
  fi
}
assert_selection docker ''
assert_selection docker '   '
assert_selection podman podman
assert_selection docker invalid --engine docker
assert_selection docker podman --engine auto
for invalid in invalid Docker ''; do assert_failure '' --engine "$invalid"; done
assert_failure invalid
assert_failure '' --engine
assert_selection "$(sed -n 's/^  echo "\(Usage:.*\)"$/\1/p' "$launcher")" invalid --help
export AI_TEST_DOCKER_HEALTH=0
assert_selection podman ''
assert_failure '' --engine docker
export AI_TEST_PODMAN_HEALTH=0
assert_failure ''
export AI_TEST_DOCKER_HEALTH=1
assert_failure '' --engine podman
mv "$temp_dir/podman" "$temp_dir/podman-disabled"
# Exclude any installed Podman when checking command absence.
mkdir "$temp_dir/isolated"
ln -s "$(command -v bash)" "$temp_dir/isolated/bash"
ln -s "$(command -v dirname)" "$temp_dir/isolated/dirname"
PATH="$temp_dir/isolated" assert_failure '' --engine podman
mv "$temp_dir/podman-disabled" "$temp_dir/podman"

for helper in engine normalize_container_name container_exists container_running image_id container_image_id container_supplemental_signature existing_host_port; do
  eval "$(sed -n "/^${helper}() {$/,/^}$/p" "$launcher")"
done
export AI_TEST_MISSING=0
for ENGINE_COMMAND in docker podman; do
  export AI_TEST_NAMES=workspace
  [[ "$ENGINE_COMMAND" != docker ]] || AI_TEST_NAMES=/workspace
  container_exists workspace
  container_running workspace
  for other in work Workspace workspace-other; do
    if container_exists "$other"; then echo "Matched a different container: $other" >&2; exit 1; fi
  done
  for AI_TEST_IMAGE in abcdef sha256:abcdef; do
    export AI_TEST_IMAGE
    [[ "$(image_id test)" == abcdef && "$(container_image_id workspace)" == abcdef ]]
  done
  export AI_TEST_NAMES=workspace-prefix-decoy
  if container_exists workspace || container_running workspace; then
    echo 'A prefix-only match selected a container.' >&2
    exit 1
  fi
  export AI_TEST_NAMES=workspace
  export AI_TEST_LABELS='{"unrelated":"value", "ai-sandbox.supplemental-folders": "abcdef"}'
  [[ "$(container_supplemental_signature workspace)" == abcdef ]]
  for AI_TEST_LABELS in null '{}' not-json '{"ai-sandbox.supplemental-folders":null}'; do
    [[ -z "$(container_supplemental_signature workspace)" ]]
  done
  for AI_TEST_ENDPOINT in 127.64.1.2:3773 0.0.0.0:3773 '[::]:3773' '[::1]:3773'; do
    export AI_TEST_ENDPOINT
    [[ "$(existing_host_port workspace 3773)" == 3773 ]]
  done
  export AI_TEST_ENDPOINT=$'0.0.0.0:3773\n[::]:3773'
  [[ "$(existing_host_port workspace 3773)" == 3773 ]]
  export AI_TEST_ENDPOINT=unpublished
  [[ -z "$(existing_host_port workspace 3773)" ]]
  export AI_TEST_MISSING=1
  if container_exists workspace; then echo 'Missing container should not exist' >&2; exit 1; fi
  [[ -z "$(image_id missing)" && -z "$(container_image_id missing)" ]]
  [[ -z "$(container_supplemental_signature missing)" && -z "$(existing_host_port missing 3773)" ]]
  export AI_TEST_MISSING=0
done

sed '/^ENGINE_COMMAND="$(resolve_engine /q' "$launcher" >"$temp_dir/dispatch.sh"
cat >>"$temp_dir/dispatch.sh" <<'FIXTURES'
assert_rootless_podman_prerequisites() { :; }
workspace_meta() {
  printf '%s\n' fixture workspace abcdef /workspace workspace state state state state 127.0.0.1
}
supplemental_mount_args() { SUPPLEMENTAL_WARNINGS=(); }
ensure_container() { :; }
FIXTURES
sed -n '/^PODMAN_SELINUX_ENABLED="false"/,$p' "$launcher" >>"$temp_dir/dispatch.sh"
export AI_TEST_DOCKER_HEALTH=1 AI_TEST_PODMAN_HEALTH=1 AI_TEST_MISSING=0 AI_TEST_NAMES=workspace AI_TEST_VOLUME_NAMES=state AI_TEST_IMAGE=abcdef
for engine_name in docker podman; do
  for command in reset-config doctor t3 shell; do
    export AI_TEST_FAIL_OPERATION=exec
    status=0
    bash "$temp_dir/dispatch.sh" --engine "$engine_name" "$command" >"$temp_dir/output" 2>&1 || status=$?
    [[ "$status" == 23 ]] || { echo "Exec exit code was lost for $engine_name $command" >&2; exit 1; }
  done
  for case in 'stop|stop' 'rm|rm' 'reset-state|rm' 'reset-state|volume rm' 'rm|ps' 'reset-state|volume ls'; do
    export AI_TEST_FAIL_OPERATION="${case#*|}"
    if bash "$temp_dir/dispatch.sh" --engine "$engine_name" "${case%%|*}" >"$temp_dir/output" 2>&1; then
      echo "Mutation failure was hidden for $engine_name $case" >&2
      exit 1
    fi
  done
  export AI_TEST_FAIL_OPERATION='' AI_TEST_NAMES=another-workspace AI_TEST_VOLUME_NAMES=another-state
  bash "$temp_dir/dispatch.sh" --engine "$engine_name" reset-state
  export AI_TEST_NAMES=workspace AI_TEST_VOLUME_NAMES=state
done
export AI_TEST_EXEC_LOG="$temp_dir/exec.log"
for engine_name in docker podman; do
  : >"$AI_TEST_EXEC_LOG"
  environment_engine=docker
  [[ "$engine_name" != docker ]] || environment_engine=podman
  AI_SANDBOX_ENGINE="$environment_engine" bash "$temp_dir/dispatch.sh" --engine "$engine_name" t3 --help --engine other-engine --unknown --update --rebuild 'value with spaces'
  mapfile -t invocation <"$AI_TEST_EXEC_LOG"
  [[ "${invocation[0]}" == "$engine_name" ]]
  expected_arguments=(t3 --help --engine other-engine --unknown --update --rebuild 'value with spaces')
  for index in "${!expected_arguments[@]}"; do
    [[ "${invocation[${#invocation[@]}-${#expected_arguments[@]}+index]}" == "${expected_arguments[$index]}" ]]
  done
done
echo 'engine-seam.sh passed'
