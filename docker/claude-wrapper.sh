#!/usr/bin/env bash
set -euo pipefail

CLAUDE_STATE_FILE="/state/data/claude/claude.json"
CLAUDE_HOME_FILE="/home/sandbox/.claude.json"
CLAUDE_REAL_BIN="/opt/ai-sandbox/bin/claude"

sync_from_state() {
  mkdir -p "$(dirname "$CLAUDE_STATE_FILE")"
  touch "$CLAUDE_STATE_FILE"
  cp -f "$CLAUDE_STATE_FILE" "$CLAUDE_HOME_FILE"
}

sync_to_state() {
  local temporary_state
  [[ -f "$CLAUDE_HOME_FILE" ]] || return 0
  temporary_state="$(mktemp /state/data/claude/claude.json.XXXXXX)"
  cp "$CLAUDE_HOME_FILE" "$temporary_state"
  mv -f "$temporary_state" "$CLAUDE_STATE_FILE"
}

forward_signal() {
  local signal="$1"
  if [[ -n "${claude_pid:-}" ]] && kill -0 "$claude_pid" 2>/dev/null; then
    kill "-$signal" "$claude_pid" 2>/dev/null || true
  fi
}

sync_from_state
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM

set +e
"$CLAUDE_REAL_BIN" "$@" &
claude_pid=$!
wait "$claude_pid"
claude_status=$?
set -e

trap - INT TERM
sync_to_state
exit "$claude_status"
