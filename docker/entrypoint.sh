#!/usr/bin/env bash
set -euo pipefail

DEFAULT_T3_PORT="${AI_SANDBOX_DEFAULT_T3_PORT:-3773}"
CONTAINER_T3_PORT="${AI_SANDBOX_T3_PORT:-$DEFAULT_T3_PORT}"
HOST_T3_URL="${AI_SANDBOX_T3_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_T3_PORT:-$CONTAINER_T3_PORT}}"
HOST_HTTP_URL="${AI_SANDBOX_HTTP_URL:-}"
DEFAULT_ALT_HTTP_PORT="${AI_SANDBOX_DEFAULT_ALT_HTTP_PORT:-8080}"
CONTAINER_ALT_HTTP_PORT="${AI_SANDBOX_ALT_HTTP_PORT:-$DEFAULT_ALT_HTTP_PORT}"
HOST_ALT_HTTP_URL="${AI_SANDBOX_ALT_HTTP_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_ALT_HTTP_PORT:-$CONTAINER_ALT_HTTP_PORT}}"
DEFAULT_APP_PORT="${AI_SANDBOX_DEFAULT_APP_PORT:-3000}"
CONTAINER_APP_PORT="${AI_SANDBOX_APP_PORT:-$DEFAULT_APP_PORT}"
HOST_APP_URL="${AI_SANDBOX_APP_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_APP_PORT:-$CONTAINER_APP_PORT}}"
WORKSPACE_PATH="${AI_SANDBOX_WORKSPACE_PATH:-/workspace}"
REAL_BIN_DIR="${AI_SANDBOX_REAL_BIN_DIR:-/opt/ai-sandbox/bin}"

ensure_runtime_user() {
  local target_uid="${LOCAL_UID:-1000}"
  local target_gid="${LOCAL_GID:-1000}"
  local current_uid current_gid target_group

  current_uid="$(id -u sandbox)"
  current_gid="$(id -g sandbox)"

  if [[ "$current_gid" != "$target_gid" ]]; then
    target_group="$(getent group "$target_gid" | cut -d: -f1 || true)"
    if [[ -n "$target_group" ]]; then
      usermod -g "$target_group" sandbox
    else
      groupmod -o -g "$target_gid" sandbox
    fi
  fi

  if [[ "$current_uid" != "$target_uid" ]]; then
    usermod -o -u "$target_uid" -g "$target_gid" sandbox
  fi

  mkdir -p /workspace "$WORKSPACE_PATH" /state/config /state/auth /state/data /state/cache /home/sandbox
  chown -R sandbox:sandbox /state /home/sandbox
}

run_as_root() {
  local command="$1"
  exec /bin/bash -lc "export HOME=/home/sandbox; export AI_SANDBOX_T3_URL='$HOST_T3_URL'; export AI_SANDBOX_T3_PORT='$CONTAINER_T3_PORT'; export AI_SANDBOX_HTTP_URL='$HOST_HTTP_URL'; export AI_SANDBOX_ALT_HTTP_URL='$HOST_ALT_HTTP_URL'; export AI_SANDBOX_ALT_HTTP_PORT='$CONTAINER_ALT_HTTP_PORT'; export AI_SANDBOX_APP_URL='$HOST_APP_URL'; export AI_SANDBOX_APP_PORT='$CONTAINER_APP_PORT'; export AI_SANDBOX_WORKSPACE_PATH='$WORKSPACE_PATH'; cd '$WORKSPACE_PATH'; $command"
}

run_as_sandbox() {
  local command="$1"
  local -a runtime_environment=(
    "HOME=/home/sandbox"
    "AI_SANDBOX_T3_URL=$HOST_T3_URL"
    "AI_SANDBOX_T3_PORT=$CONTAINER_T3_PORT"
    "AI_SANDBOX_HTTP_URL=$HOST_HTTP_URL"
    "AI_SANDBOX_ALT_HTTP_URL=$HOST_ALT_HTTP_URL"
    "AI_SANDBOX_ALT_HTTP_PORT=$CONTAINER_ALT_HTTP_PORT"
    "AI_SANDBOX_APP_URL=$HOST_APP_URL"
    "AI_SANDBOX_APP_PORT=$CONTAINER_APP_PORT"
    "AI_SANDBOX_WORKSPACE_PATH=$WORKSPACE_PATH"
  )

  if [[ "$(id -u)" == "0" ]]; then
    exec runuser -u sandbox -- env "${runtime_environment[@]}" /bin/bash -lc "cd '$WORKSPACE_PATH'; $command"
  fi

  exec env "${runtime_environment[@]}" /bin/bash -lc "cd '$WORKSPACE_PATH'; $command"
}

# Child harnesses inherit completed initialization from their server or shell.
# Reinitializing here races with live CLI state and other provider probes.
if [[ "$(id -u)" == "0" && "${AI_SANDBOX_INITIALIZED:-}" != "1" ]]; then
  ensure_runtime_user
  /opt/ai-sandbox/bootstrap/init-state.sh
  chown -R sandbox:sandbox /state /home/sandbox
  git config --system --add safe.directory '*' 2>/dev/null || true
  export AI_SANDBOX_INITIALIZED=1
fi

warn_missing_git_identity() {
  local git_user_name git_user_email

  if [[ "$(git -C "$WORKSPACE_PATH" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    return
  fi

  git_user_name="$(git -C "$WORKSPACE_PATH" config --get user.name 2>/dev/null || true)"
  git_user_email="$(git -C "$WORKSPACE_PATH" config --get user.email 2>/dev/null || true)"

  if [[ -n "$git_user_name" && -n "$git_user_email" ]]; then
    return
  fi

  printf '\033[33m%s\033[0m\n' 'The current git config has no user.name and user.email values. You can run the following commands to configure these values in the workspace folder (this will apply the config at the folder level and be visible outside the sandbox):'
  printf '\033[33m%s\033[0m\n' '> git config user.name "Your Name"'
  printf '\033[33m%s\033[0m\n' '> git config user.email "your.email@example.com"'
  printf ''
  printf '\033[33m%s\033[0m\n' 'To configure them only inside this sandbox, use the following:'
  printf '\033[33m%s\033[0m\n' '> git config --global user.name "Your Name"'
  printf '\033[33m%s\033[0m\n' '> git config --global user.email "your.email@example.com"'
}

quote_args() {
  printf '%q ' "$@"
}

run_argv_as_root() {
  local quoted
  quoted="$(quote_args "$@")"
  run_as_root "exec ${quoted}"
}

run_argv_as_sandbox() {
  local quoted
  quoted="$(quote_args "$@")"
  run_as_sandbox "exec ${quoted}"
}

run_cursor_as_root() {
  local quoted
  quoted="$(quote_args /opt/ai-sandbox/bin/cursor-agent "$@")"
  run_as_root "export AGENT_CLI_CREDENTIAL_STORE=file; exec ${quoted}"
}

rewrite_t3_output() {
  while IFS= read -r line; do
    case "$line" in
      "Connection string: "*)
        echo "Connection string: $AI_SANDBOX_T3_URL"
        ;;
      "Pairing URL: "*"#token="*)
        token="${line##*#token=}"
        echo "Pairing URL: $AI_SANDBOX_T3_URL/pair#token=$token"
        ;;
      *"pairingUrl: "*"#token="*)
        token="${line##*#token=}"
        prefix="${line%%pairingUrl: *}"
        echo "${prefix}pairingUrl: $AI_SANDBOX_T3_URL/pair#token=$token"
        ;;
      *)
        echo "$line"
        ;;
    esac
  done
}

print_banner() {
  printf '\n'
  cat /opt/ai-sandbox/defaults/configs/shared/banner.txt
  printf '\nT3 URL (after `ai-sandbox t3`): %s\n' "$HOST_T3_URL"
  printf 'Web Port 8080: %s\n' "$HOST_ALT_HTTP_URL"
  printf 'Web Port 3000: %s\n' "$HOST_APP_URL"
}

reset_config() {
  /opt/ai-sandbox/bootstrap/sync-configs.sh --reset
  echo "Config defaults restored from image presets."
}

run_doctor() {
  echo "codex: $(codex --version 2>/dev/null || echo unavailable)"
  echo "claude: $(claude --version 2>/dev/null || echo unavailable)"
  echo "agy: $(agy --version 2>/dev/null || echo unavailable)"
  echo "copilot: $(copilot --version 2>/dev/null || echo unavailable)"
  echo "opencode: $(opencode --version 2>/dev/null || echo unavailable)"
  echo "cursor: $(cursor --version 2>/dev/null || echo unavailable)"
  echo "node: $(node --version 2>/dev/null || echo unavailable)"
  echo "npm: $(npm --version 2>/dev/null || echo unavailable)"
  echo "t3: $(t3 --help >/dev/null 2>&1 && echo available || echo unavailable)"
}

run_t3() {
  echo "Starting T3 on $HOST_T3_URL"
  python3 /opt/ai-sandbox/t3-startup.py --base-dir /state/data/t3
  run_as_sandbox "$(declare -f rewrite_t3_output); export HOST=0.0.0.0; export PORT='$CONTAINER_T3_PORT'; export T3_CONFIG_PATH=/state/config/t3/config.json; export T3CODE_HOME=/state/data/t3; /opt/ai-sandbox/bin/t3 start --no-browser --host 0.0.0.0 --port '$CONTAINER_T3_PORT' --base-dir /state/data/t3 --auto-bootstrap-project-from-cwd 2>&1 | rewrite_t3_output"
}

dispatch() {
  local cmd="${1:-shell}"
  shift || true

  case "$cmd" in
    daemon)
      exec sleep infinity
      ;;
    shell)
      print_banner
      warn_missing_git_identity
      run_as_root "exec bash -il"
      ;;
    codex)
      run_argv_as_root /opt/ai-sandbox/bin/codex "$@"
      ;;
    claude)
      run_argv_as_sandbox /opt/ai-sandbox/claude-wrapper.sh "$@"
      ;;
    agy)
      run_argv_as_root /opt/ai-sandbox/bin/agy "$@"
      ;;
    copilot)
      run_argv_as_root /opt/ai-sandbox/bin/copilot "$@"
      ;;
    opencode)
      run_argv_as_root /opt/ai-sandbox/bin/opencode "$@"
      ;;
    cursor-agent)
      run_cursor_as_root "$@"
      ;;
    cursor)
      run_cursor_as_root "$@"
      ;;
    t3)
      run_t3 "$@"
      ;;
    doctor)
      run_as_root "$(declare -f run_doctor); run_doctor"
      ;;
    reset-config)
      reset_config
      ;;
    *)
      run_argv_as_root "$cmd" "$@"
      ;;
  esac
}

dispatch "$@"
