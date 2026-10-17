#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
selected_engine="${AI_SANDBOX_ENGINE:-docker}"
run_live=false
rebuild=false
build=false
while (($#)); do
  case "$1" in
    --engine) selected_engine="${2:?Missing engine}"; shift 2 ;;
    --run-live) run_live=true; shift ;;
    --build) build=true; shift ;;
    --rebuild) rebuild=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
[[ "$run_live" == true ]] || { echo 'Live validation requires --run-live.' >&2; exit 1; }
[[ "$selected_engine" == docker || "$selected_engine" == podman ]] || { echo 'Select docker or podman.' >&2; exit 1; }
"$selected_engine" version >/dev/null
eval "$(sed -n '/^workspace_meta() {$/,/^}$/p' "$repo_root/bin/ai-sandbox")"

task_temp_dir="$(mktemp -d /tmp/ai-sandbox-live-XXXXXXXX)"
workspace="$task_temp_dir/workspace with spaces"
mkdir "$workspace"
mapfile -t metadata < <(workspace_meta "$workspace")
container="${metadata[4]}"
volumes=("${metadata[5]}" "${metadata[6]}" "${metadata[7]}" "${metadata[8]}")
marker="$(basename "$task_temp_dir")"
service_pid=''
cleanup() {
  "$selected_engine" rm --force "$container" >/dev/null 2>&1 || true
  [[ -z "$service_pid" ]] || kill "$service_pid" 2>/dev/null || true
  "$selected_engine" volume rm "${volumes[@]}" >/dev/null 2>&1 || true
  [[ "$task_temp_dir" == /tmp/ai-sandbox-live-* ]] || return 1
  rm -rf -- "$task_temp_dir"
}
trap cleanup EXIT
launcher() { bash "$repo_root/bin/ai-sandbox" --engine "$selected_engine" "$@"; }

[[ "$build" != true ]] || "$selected_engine" build --pull -t ai-sandbox:latest "$repo_root"
cd "$workspace"
launcher reset-config >/dev/null
[[ "$("$selected_engine" inspect --format '{{.State.Running}}' "$container")" == true ]]
for port in 3773 9899 6767 8080 3000; do
  mapping="$("$selected_engine" port "$container" "$port/tcp")"
  if [[ "$selected_engine" == docker ]]; then
    [[ "$mapping" == *"${metadata[9]}:$port"* ]]
  fi
done
for volume in "${volumes[@]}"; do "$selected_engine" volume inspect "$volume" >/dev/null; done
"$selected_engine" exec "$container" sh -c "for directory in config auth data cache; do printf '%s' '$marker' > /state/\$directory/engine-lifecycle-marker; done"
launcher t3 >"$task_temp_dir/service.log" 2>&1 &
service_pid=$!
reachable=false
for attempt in {1..40}; do
  if ! kill -0 "$service_pid" 2>/dev/null; then
    cat "$task_temp_dir/service.log" >&2
    echo 'T3 exited before startup.' >&2
    exit 1
  fi
  if curl --noproxy '*' --max-time 2 -fs "http://${metadata[9]}:3773/" >/dev/null; then
    reachable=true
    break
  fi
  sleep 0.5
done
[[ "$reachable" == true ]] || { cat "$task_temp_dir/service.log" >&2; echo 'T3 was unreachable.' >&2; exit 1; }
launcher stop
wait "$service_pid" || true
service_pid=''
[[ "$("$selected_engine" inspect --format '{{.State.Running}}' "$container")" == false ]]
launcher rm
if "$selected_engine" container inspect "$container" >/dev/null 2>&1; then
  echo 'Removal left the container present.' >&2
  exit 1
fi
for volume in "${volumes[@]}"; do "$selected_engine" volume inspect "$volume" >/dev/null; done
launcher reset-config >/dev/null
for directory in config auth data cache; do
  [[ "$("$selected_engine" exec "$container" cat "/state/$directory/engine-lifecycle-marker")" == "$marker" ]]
done
if [[ "$rebuild" == true ]]; then
  launcher --rebuild reset-config >/dev/null
  for directory in config auth data cache; do
    [[ "$("$selected_engine" exec "$container" cat "/state/$directory/engine-lifecycle-marker")" == "$marker" ]]
  done
fi
launcher reset-state
for volume in "${volumes[@]}"; do
  if "$selected_engine" volume inspect "$volume" >/dev/null 2>&1; then
    echo "Reset left volume $volume present." >&2
    exit 1
  fi
done
printf 'engine-lifecycle.sh passed (%s; rebuild=%s)\n' "$selected_engine" "$rebuild"
