#!/usr/bin/env bash
set -euo pipefail

init_state="${1:-/repo/docker/bootstrap/init-state.sh}"

bash "$init_state"
printf persisted > /state/data/claude/claude.json

for round in $(seq 1 50); do
  rm -f /home/sandbox/.claude.json
  pids=""

  for worker in $(seq 1 8); do
    bash "$init_state" >"/tmp/claude-bootstrap-${round}-${worker}.out" 2>&1 &
    pids="$pids $!"
  done

  for pid in $pids; do
    if ! wait "$pid"; then
      echo "FAILED_ROUND=$round"
      cat "/tmp/claude-bootstrap-${round}-"*.out
      exit 1
    fi
  done

  grep -qx persisted /home/sandbox/.claude.json
done

echo "claude-bootstrap-concurrency.sh passed"
