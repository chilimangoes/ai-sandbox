#!/usr/bin/env bash
set -euo pipefail

shared=/state/config/shared/AGENTS.md
codex=/home/sandbox/.codex/AGENTS.md
claude=/home/sandbox/.claude/CLAUDE.md
legacy_codex=/state/config/codex/AGENTS.md

assert_shared_instructions() {
  [[ "$(readlink "$codex")" == "$shared" ]]
  [[ "$(readlink "$claude")" == "$shared" ]]
  cmp "$shared" "$codex"
  cmp "$shared" "$claude"
}

/opt/ai-sandbox/bootstrap/init-state.sh

case "${1:?Expected install, verify, or verify-shared}" in
  install)
    printf 'shared instructions\n' > "$shared"
    assert_shared_instructions

    # Restore instructions installed at the original persisted Codex location.
    printf 'codex instructions\n' > "$legacy_codex"
    /opt/ai-sandbox/bootstrap/init-state.sh
    [[ "$(readlink "$codex")" == "$legacy_codex" ]]
    grep -qx 'codex instructions' "$codex"
    rm "$legacy_codex"

    # Preserve an existing Claude file when shared instructions are available.
    rm "$claude"
    printf 'claude instructions\n' > "$claude"
    /opt/ai-sandbox/bootstrap/init-state.sh
    [[ ! -L "$claude" ]]
    grep -qx 'claude instructions' "$claude"
    rm "$claude"
    /opt/ai-sandbox/bootstrap/init-state.sh
    assert_shared_instructions

    # Leave tool-specific files in the volumes to check after recreation.
    printf 'codex instructions\n' > "$legacy_codex"
    rm "$claude"
    printf 'claude instructions\n' > "$claude"
    ;;
  verify)
    [[ "$(readlink "$codex")" == "$legacy_codex" ]]
    grep -qx 'codex instructions' "$codex"
    grep -qx 'claude instructions' "$claude"
    rm "$legacy_codex" "$claude"
    /opt/ai-sandbox/bootstrap/init-state.sh
    assert_shared_instructions
    printf 'updated shared instructions\n' > "$shared"
    grep -qx 'updated shared instructions' "$codex"
    grep -qx 'updated shared instructions' "$claude"
    ;;
  verify-shared)
    assert_shared_instructions
    grep -qx 'updated shared instructions' "$codex"
    ;;
  *) exit 1 ;;
esac
