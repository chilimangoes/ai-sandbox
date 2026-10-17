#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$repo_root/bin/ai-sandbox"
task_dir="$(mktemp -d)"
trap 'rm -rf -- "$task_dir"' EXIT
for helper in has_subordinate_range assert_rootless_podman_prerequisites supplemental_mount_args container_port_mappings ensure_container; do
  eval "$(sed -n "/^${helper}() {$/,/^}$/p" "$launcher")"
done

for record in 'fixture:100000:65536' '1000:100000:65536' $'fixture:100000:32768\nfixture:200000:32768'; do
  printf '%s\n' "$record" > "$task_dir/ranges"
  has_subordinate_range "$task_dir/ranges" fixture 1000
done
for record in '' 'other:100000:65536' 'fixture:100000:0' 'fixture:0:65536' 'fixture:bad:65536' 'fixture:100000:bad' 'fixture:100000:1000'; do
  printf '%s\n' "$record" > "$task_dir/ranges"
  if has_subordinate_range "$task_dir/ranges" fixture 1000; then echo "Accepted malformed range: $record" >&2; exit 1; fi
done
if has_subordinate_range "$task_dir/absent" fixture 1000; then exit 1; fi

has_subordinate_range() { [[ "$1" != "${missing_range:-}" ]]; }
uname() { printf 'Linux\n'; }
engine() {
  [[ "${info_failure:-false}" != true ]] || return 23
  [[ "${selinux_info_failure:-false}" != true || "$3" != '{{.Host.Security.SELinuxEnabled}}' ]] || return 24
  case "$3" in
    '{{.Host.Security.Rootless}}') printf '%s\n' "$test_rootless" ;;
    '{{.Host.Security.SELinuxEnabled}}') printf '%s\n' "$test_selinux" ;;
    *) return 99 ;;
  esac
}
ENGINE_COMMAND=podman; test_rootless=true; test_selinux=false
assert_rootless_podman_prerequisites
[[ "$PODMAN_SELINUX_ENABLED" == false ]]
test_selinux=true
assert_rootless_podman_prerequisites
[[ "$PODMAN_SELINUX_ENABLED" == true ]]
for test_rootless in false malformed ''; do
  if assert_rootless_podman_prerequisites > "$task_dir/error" 2>&1; then exit 1; fi
  grep -q 'rootless=true' "$task_dir/error"
done
test_rootless=true
for missing_range in /etc/subuid /etc/subgid; do
  if assert_rootless_podman_prerequisites > "$task_dir/error" 2>&1; then exit 1; fi
  grep -q "$missing_range" "$task_dir/error"
done
missing_range=''; test_selinux=malformed
if assert_rootless_podman_prerequisites > "$task_dir/error" 2>&1; then exit 1; fi
grep -q 'unknown SELinux state' "$task_dir/error"
test_selinux=false; selinux_info_failure=true
if assert_rootless_podman_prerequisites > "$task_dir/error" 2>&1; then exit 1; fi
grep -q 'Could not detect SELinux support' "$task_dir/error"
selinux_info_failure=false
info_failure=true
if assert_rootless_podman_prerequisites > "$task_dir/error" 2>&1; then exit 1; fi
grep -q 'podman info' "$task_dir/error"
ENGINE_COMMAND=docker
assert_rootless_podman_prerequisites
info_failure=false

read_supplemental_folder_config() {
  local -n hosts="$3" names="$4" modes="$5"
  if [[ "$2" == local ]]; then
    hosts=("$task_dir/read only" "$task_dir/read write")
    names=('read only' 'read write'); modes=(ro rw)
  fi
}
WORKSPACE_PATH="$task_dir/workspace with spaces"
for ENGINE_COMMAND in docker podman; do
  for PODMAN_SELINUX_ENABLED in false true; do
    supplemental_mount_args
    suffix=''
    [[ "$PODMAN_SELINUX_ENABLED" != true ]] || suffix=,z
    [[ "${SUPPLEMENTAL_MOUNT_ARGS[1]}" == "$task_dir/read only:/supplemental/read only:ro$suffix" ]]
    [[ "${SUPPLEMENTAL_MOUNT_ARGS[3]}" == "$task_dir/read write:/supplemental/read write:rw$suffix" ]]
  done
done
ENGINE_COMMAND=docker; PODMAN_SELINUX_ENABLED=false
supplemental_mount_args; docker_signature="$SUPPLEMENTAL_SIGNATURE"
ENGINE_COMMAND=podman
supplemental_mount_args; rootless_signature="$SUPPLEMENTAL_SIGNATURE"
[[ "$rootless_signature" != "$docker_signature" ]]
PODMAN_SELINUX_ENABLED=true
supplemental_mount_args
[[ "$SUPPLEMENTAL_SIGNATURE" != "$rootless_signature" ]]

image_id() { printf 'image\n'; }
container_image_id() { printf 'image\n'; }
container_supplemental_signature() { printf '%s\n' "$SUPPLEMENTAL_SIGNATURE"; }
ensure_volume() { :; }
container_exists() { [[ "$exists" == true ]]; }
container_running() { true; }
remove_container() { exists=false; removed=true; }
engine() {
  if [[ "$1" == inspect ]]; then
    [[ "$mapping_mode" != absent ]] || return 1
    if [[ "$mapping_mode" == malformed ]]; then printf 'malformed\n'; return; fi
    local address="$HOST_ADDRESS" port container_port
    [[ "$mapping_mode" != address ]] || address=127.0.0.1
    for container_port in 3773 9899 6767 8080 3000; do
      [[ "$mapping_mode" != missing_one || "$container_port" != 6767 ]] || continue
      port="$container_port"
      [[ "$mapping_mode" != port ]] || port=$((port + 1))
      printf '%s/tcp %s %s\n' "$container_port" "$address" "$port"
    done
  elif [[ "$1" == run ]]; then printf '%s\0' "$@" > "$task_dir/run-args"; exists=true
  else return 99; fi
}
CONTAINER_NAME=fixture; CONFIG_VOLUME=config; AUTH_VOLUME=auth; DATA_VOLUME=data; CACHE_VOLUME=cache
IMAGE_TAG=fixture; WORKSPACE_SLUG=fixture; WORKSPACE_HASH=abcdef; CONTAINER_WORKSPACE_PATH=/workspace/fixture
HOST_ADDRESS=127.76.1.2; DEFAULT_T3_CONTAINER_PORT=3773; DEFAULT_CODENOMAD_CONTAINER_PORT=9899
DEFAULT_PASEO_CONTAINER_PORT=6767; DEFAULT_ALT_HTTP_CONTAINER_PORT=8080; DEFAULT_APP_CONTAINER_PORT=3000
FORCE_RECREATE=false
for ENGINE_COMMAND in docker podman; do
  for PODMAN_SELINUX_ENABLED in false true; do
    supplemental_mount_args
    exists=false; mapping_mode=valid
    ensure_container
    mapfile -d '' -t args < "$task_dir/run-args"
    expected_workspace="$WORKSPACE_PATH:$CONTAINER_WORKSPACE_PATH"
    [[ "$PODMAN_SELINUX_ENABLED" != true ]] || expected_workspace+=:Z
    found_workspace=false; found_namespace=false; found_root=false
    for ((index=0; index<${#args[@]}; index++)); do
      [[ "${args[index]}" != "$expected_workspace" ]] || found_workspace=true
      [[ "${args[index]}" != --userns=keep-id ]] || found_namespace=true
      if [[ "${args[index]}" == --user && "${args[index+1]}" == 0 ]]; then found_root=true; fi
      [[ "${args[index]}" != *label=disable* ]]
    done
    [[ "$found_workspace" == true ]]
    [[ "$found_namespace" == "$([[ "$ENGINE_COMMAND" == podman ]] && echo true || echo false)" ]]
    [[ "$found_root" == "$found_namespace" ]]
    for mapping_mode in valid absent missing_one malformed address port; do
      exists=true; removed=false
      ensure_container
      [[ "$removed" == "$([[ "$mapping_mode" == valid ]] && echo false || echo true)" ]]
    done
  done
done
python3 - "$repo_root/tests/launcher/podman-linux-live.py" <<'PY'
import ast, json, pathlib, re, sys, tempfile
source = ast.parse(pathlib.Path(sys.argv[1]).read_text())
helpers = [node for node in source.body if isinstance(node, ast.FunctionDef) and node.name in ("redact_text", "sanitize_evidence")]
namespace = {"re": re, "json": json}
exec(compile(ast.Module(body=helpers, type_ignores=[]), "harness-helpers", "exec"), namespace)
samples = [
    "http://127.76.1.2:3773/#token=generated-secret",
    "Bootstrap token: generated-secret",
    json.dumps({"bootstrapToken": "generated-secret", "endpoint": "127.76.1.2:3773"}),
    json.dumps({"Body": json.dumps({"token": "generated-secret"})}),
]
for sample in samples:
    redacted = namespace["redact_text"](sample)
    assert "generated-secret" not in redacted, redacted
    assert "<REDACTED>" in redacted
    if sample.startswith("{"):
        json.loads(redacted)
with tempfile.TemporaryDirectory() as temporary:
    evidence = pathlib.Path(temporary)
    namespace["evidence"] = evidence
    for extension in ("json", "log", "txt", "typescript"):
        (evidence / ("failure." + extension)).write_text(samples[0])
    try:
        raise RuntimeError("simulated acceptance failure")
    except RuntimeError:
        pass
    finally:
        namespace["sanitize_evidence"]()
    for path in evidence.glob("failure.*"):
        assert "generated-secret" not in path.read_text()
    assert len(json.loads((evidence / "redaction-summary.json").read_text())["RedactedFiles"]) == 4
PY
echo 'podman-linux.sh passed (ranges, readiness, SELinux mounts, namespaces, endpoint recreation)'
