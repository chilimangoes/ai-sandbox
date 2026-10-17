#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
export ARGS_FILE="$task_dir/arguments"
export ENV_FILE="$task_dir/environment"
cat > "$task_dir/tool" <<'SH'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$ARGS_FILE"
printf '%s' "${PASEO_RELAY_ENABLED:-}" > "$ENV_FILE"
exit "${FAKE_EXIT:-0}"
SH
chmod +x "$task_dir/tool"
cleanup_definition="$(sed -n '/^cleanup_paseo_daemon() {/,/^}/p' "$repo_root/docker/entrypoint.sh")"
cleanup_definition="${cleanup_definition//\/opt\/ai-sandbox\/bin\/paseo/$task_dir\/tool}"
eval "$cleanup_definition"
paseo() { echo 'Cleanup reentered the Paseo wrapper' >&2; exit 99; }
cleanup_paseo_daemon
python3 - "$ARGS_FILE" <<'PY'
import pathlib, sys
actual = pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert actual == [b'daemon', b'stop', b'--home', b'/state/data/paseo', b'--force'], actual
PY
run_as_root() { bash -c "$1"; }
rewrite_t3_output() { cat; }
rewrite_codenomad_output() { cat; }
rewrite_paseo_output() { cat; }
cleanup_paseo_daemon() { :; }
ensure_paseo_workspace_registry() { :; }
eval "$(sed -n '/^get_paseo_relay_enabled() {/,/^}/p' "$repo_root/docker/entrypoint.sh")"
SANDBOX_CONFIG_PATH="$task_dir/sandbox.config"
[[ "$(get_paseo_relay_enabled)" == false ]]
printf 'paseo_relay=1\n' > "$SANDBOX_CONFIG_PATH"
[[ "$(get_paseo_relay_enabled)" == true ]]
printf 'paseo_relay=0\n' > "$SANDBOX_CONFIG_PATH"
[[ "$(get_paseo_relay_enabled)" == false ]]
HOST_T3_URL=http://127.0.0.1:20100
HOST_CODENOMAD_URL=http://127.0.0.1:20101
HOST_PASEO_ADDRESS=127.0.0.1:20102
CONTAINER_T3_PORT=3773
CONTAINER_CODENOMAD_PORT=9899
CONTAINER_PASEO_PORT=6767
WORKSPACE_PATH='/workspace/with spaces'
for service in t3 codenomad paseo; do
  definition="$(sed -n "/^run_${service}() {/,/^}/p" "$repo_root/docker/entrypoint.sh")"
  definition="${definition//\/opt\/ai-sandbox\/bin\/$service/$task_dir\/tool}"
  eval "$definition"
done
arguments=('value with spaces' "apostrophe's" '$(touch /tmp/ai-sandbox-should-not-exist)' 'D:\OneDrive\with spaces' '--engine' 'podman')
for service in t3 codenomad paseo; do
  "run_$service" "${arguments[@]}"
  python3 - "$ARGS_FILE" <<'PY'
import pathlib, sys
actual = pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
expected = [b'value with spaces', b"apostrophe's", b'$(touch /tmp/ai-sandbox-should-not-exist)', b'D:\\OneDrive\\with spaces', b'--engine', b'podman']
assert actual[-len(expected):] == expected, actual
PY
  "run_$service"
  if [[ "$service" == paseo ]]; then [[ "$(cat "$ENV_FILE")" == false ]]; fi
  python3 - "$ARGS_FILE" <<'PY'
import pathlib, sys
actual = pathlib.Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert actual and b'' not in actual, actual
PY
done
export FAKE_EXIT=17
for service in t3 codenomad paseo; do
  if "run_$service" --example; then
    echo "$service lost its tool exit code" >&2
    exit 1
  else
    status=$?
    [[ "$status" == 17 ]] || exit 1
  fi
done
echo 'service-arguments.sh passed'
