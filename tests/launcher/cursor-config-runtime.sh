#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG=/opt/ai-sandbox/defaults/configs/cursor/cli-config.json
PERSISTED_CONFIG=/state/config/cursor/cli-config.json
RUNTIME_CONFIG=/state/data/cursor/cli-config.json

reset_test_state() {
  rm -rf /state/config /state/auth /state/data /state/cache /home/sandbox/.cursor
  mkdir -p /home/sandbox
}

assert_same_json() {
  diff -u <(jq -S . "$1") <(jq -S . "$2")
}

reset_test_state
/opt/ai-sandbox/bootstrap/init-state.sh
assert_same_json "$DEFAULT_CONFIG" "$PERSISTED_CONFIG"
[[ -L "$RUNTIME_CONFIG" ]]
[[ "$(readlink "$RUNTIME_CONFIG")" == "$PERSISTED_CONFIG" ]]

printf '%s\n' '{"approvalMode":"custom"}' > "$PERSISTED_CONFIG"
/opt/ai-sandbox/bootstrap/init-state.sh
[[ "$(jq -r .approvalMode "$PERSISTED_CONFIG")" == "custom" ]]
[[ -L "$RUNTIME_CONFIG" ]]

reset_test_state
mkdir -p /state/data/cursor
printf '%s\n' '{"legacy":true}' > "$RUNTIME_CONFIG"
/opt/ai-sandbox/bootstrap/init-state.sh
[[ -L "$RUNTIME_CONFIG" ]]
[[ "$(jq -r .legacy "$PERSISTED_CONFIG")" == "true" ]]
/opt/ai-sandbox/bootstrap/init-state.sh
[[ "$(jq -r .legacy "$PERSISTED_CONFIG")" == "true" ]]

/opt/ai-sandbox/bootstrap/sync-configs.sh --reset
assert_same_json "$DEFAULT_CONFIG" "$PERSISTED_CONFIG"
[[ -L "$RUNTIME_CONFIG" ]]

echo "cursor-config-runtime.sh passed"
