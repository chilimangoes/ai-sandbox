#!/usr/bin/env bash
set -euo pipefail
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
unset AI_SANDBOX_INITIALIZED
cat > "$task_dir/probe.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${AI_SANDBOX_INITIALIZED:-}" == 1 ]]
[[ ! -e /proc/self/fd/8 ]]
[[ -L /home/sandbox/.config/cursor ]]
printf 'initialized\n'
SH
chmod +x "$task_dir/probe.sh"
pids=()
for index in {1..12}; do
  /opt/ai-sandbox/entrypoint.sh "$task_dir/probe.sh" > "$task_dir/$index.stdout" 2> "$task_dir/$index.stderr" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then cat "$task_dir/"*.stderr >&2; exit 1; fi
done
[[ "$(cat "$task_dir/"*.stdout | grep -c '^initialized$')" == 12 ]]
[[ -z "$(cat "$task_dir/"*.stderr)" ]]
echo 'entrypoint-bootstrap-concurrency.sh passed (12 initializers; lock FD closed)'
