#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG="/opt/ai-sandbox/defaults/configs/claude/settings.json"
PERSISTED_CONFIG="/state/config/claude/settings.json"
RUNTIME_CONFIG="/home/sandbox/.claude/settings.json"

reset_test_state() {
  rm -rf /state/config/* /state/data/* /home/sandbox/.claude /home/sandbox/.claude.json
  mkdir -p /state/config /state/data /home/sandbox
}

assert_same_json() {
  diff -u <(jq -S . "$1") <(jq -S . "$2")
}

reset_test_state
/opt/ai-sandbox/bootstrap/init-state.sh
assert_same_json "$DEFAULT_CONFIG" "$PERSISTED_CONFIG"
[[ -L "$RUNTIME_CONFIG" ]]
[[ "$(readlink "$RUNTIME_CONFIG")" == "$PERSISTED_CONFIG" ]]

printf '%s\n' '{"theme":"dark"}' > "$PERSISTED_CONFIG"
/opt/ai-sandbox/bootstrap/init-state.sh
[[ "$(jq -r .theme "$PERSISTED_CONFIG")" == "dark" ]]
[[ -L "$RUNTIME_CONFIG" ]]

/opt/ai-sandbox/bootstrap/sync-configs.sh --reset
assert_same_json "$DEFAULT_CONFIG" "$PERSISTED_CONFIG"

reset_test_state
mkdir -p /home/sandbox/.claude
printf '%s\n' '{"theme":"legacy"}' > "$RUNTIME_CONFIG"
/opt/ai-sandbox/bootstrap/init-state.sh
[[ "$(jq -r .theme "$PERSISTED_CONFIG")" == "legacy" ]]
[[ -L "$RUNTIME_CONFIG" ]]
[[ "$(readlink "$RUNTIME_CONFIG")" == "$PERSISTED_CONFIG" ]]

echo "claude-config-runtime.sh passed"
