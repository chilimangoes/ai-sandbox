#!/usr/bin/env bash
set -euo pipefail

DEFAULT_T3_PORT="${AI_SANDBOX_DEFAULT_T3_PORT:-3773}"
CONTAINER_T3_PORT="${AI_SANDBOX_T3_PORT:-$DEFAULT_T3_PORT}"
HOST_T3_URL="${AI_SANDBOX_T3_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_T3_PORT:-$CONTAINER_T3_PORT}}"
DEFAULT_CODENOMAD_PORT="${AI_SANDBOX_DEFAULT_CODENOMAD_PORT:-9899}"
CONTAINER_CODENOMAD_PORT="${AI_SANDBOX_CODENOMAD_PORT:-$DEFAULT_CODENOMAD_PORT}"
HOST_CODENOMAD_URL="${AI_SANDBOX_CODENOMAD_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_CODENOMAD_PORT:-$CONTAINER_CODENOMAD_PORT}}"
DEFAULT_PASEO_PORT="${AI_SANDBOX_DEFAULT_PASEO_PORT:-6767}"
CONTAINER_PASEO_PORT="${AI_SANDBOX_PASEO_PORT:-$DEFAULT_PASEO_PORT}"
HOST_PASEO_ADDRESS="${AI_SANDBOX_PASEO_ADDRESS:-127.0.0.1:${AI_SANDBOX_HOST_PASEO_PORT:-$CONTAINER_PASEO_PORT}}"
WORKSPACE_PATH="${AI_SANDBOX_WORKSPACE_PATH:-/workspace}"

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

run_as_sandbox() {
  local command="$1"
  exec runuser -u sandbox -- /bin/bash -lc "export AI_SANDBOX_T3_URL='$HOST_T3_URL'; export AI_SANDBOX_T3_PORT='$CONTAINER_T3_PORT'; export AI_SANDBOX_CODENOMAD_URL='$HOST_CODENOMAD_URL'; export AI_SANDBOX_CODENOMAD_PORT='$CONTAINER_CODENOMAD_PORT'; export AI_SANDBOX_PASEO_ADDRESS='$HOST_PASEO_ADDRESS'; export AI_SANDBOX_PASEO_PORT='$CONTAINER_PASEO_PORT'; export AI_SANDBOX_WORKSPACE_PATH='$WORKSPACE_PATH'; cd '$WORKSPACE_PATH'; $command"
}

ensure_runtime_user
/opt/ai-sandbox/bootstrap/init-state.sh
chown -R sandbox:sandbox /state /home/sandbox

quote_args() {
  printf '%q ' "$@"
}

run_argv_as_sandbox() {
  local quoted
  quoted="$(quote_args "$@")"
  run_as_sandbox "exec ${quoted}"
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
      *)
        echo "$line"
        ;;
    esac
  done
}

rewrite_codenomad_output() {
  while IFS= read -r line; do
    case "$line" in
      "Local Connection URL :"*)
        echo "Local Connection URL : $AI_SANDBOX_CODENOMAD_URL"
        ;;
      "Remote Connection URL :"*)
        echo "Remote Connection URL : $AI_SANDBOX_CODENOMAD_URL"
        ;;
      *)
        echo "$line"
        ;;
    esac
  done
}

rewrite_paseo_output() {
  while IFS= read -r line; do
    if [[ "$line" == *"127.0.0.1:${CONTAINER_PASEO_PORT}"* ]]; then
      echo "${line//127.0.0.1:${CONTAINER_PASEO_PORT}/$HOST_PASEO_ADDRESS}"
    elif [[ "$line" == *"0.0.0.0:${CONTAINER_PASEO_PORT}"* ]]; then
      echo "${line//0.0.0.0:${CONTAINER_PASEO_PORT}/$HOST_PASEO_ADDRESS}"
    else
      echo "$line"
    fi
  done
}

print_banner() {
  printf '\n'
  cat /opt/ai-sandbox/defaults/configs/shared/banner.txt
  printf '\nT3 URL (after `ai-sandbox t3`): %s\n' "$HOST_T3_URL"
  printf 'CodeNomad URL (after `ai-sandbox codenomad`): %s\n' "$HOST_CODENOMAD_URL"
  printf 'Paseo Address (after `ai-sandbox paseo`): %s\n' "$HOST_PASEO_ADDRESS"
}

reset_config() {
  /opt/ai-sandbox/bootstrap/sync-configs.sh --reset
  echo "Config defaults restored from image presets."
}

run_doctor() {
  echo "codex: $(codex --version 2>/dev/null || echo unavailable)"
  echo "gemini: $(gemini --version 2>/dev/null || echo unavailable)"
  echo "copilot: $(copilot --version 2>/dev/null || echo unavailable)"
  echo "opencode: $(opencode --version 2>/dev/null || echo unavailable)"
  echo "codenomad: $(codenomad --version 2>/dev/null || echo unavailable)"
  echo "paseo: $(paseo --version 2>/dev/null || echo unavailable)"
  echo "node: $(node --version 2>/dev/null || echo unavailable)"
  echo "npm: $(npm --version 2>/dev/null || echo unavailable)"
  echo "t3: $(t3 --help >/dev/null 2>&1 && echo available || echo unavailable)"
}

run_t3() {
  echo "Starting T3 on $HOST_T3_URL"
  run_as_sandbox "$(declare -f rewrite_t3_output); export HOST=0.0.0.0; export PORT='$CONTAINER_T3_PORT'; export T3_CONFIG_PATH=/state/config/t3/config.json; export T3CODE_HOME=/state/data/t3; t3 start --no-browser --host 0.0.0.0 --port '$CONTAINER_T3_PORT' --auto-bootstrap-project-from-cwd 2>&1 | rewrite_t3_output"
}

run_codenomad() {
  echo "Starting CodeNomad on $HOST_CODENOMAD_URL"
  run_as_sandbox "$(declare -f rewrite_codenomad_output); export CLI_HTTP=true; export CLI_HTTPS=false; export CLI_HOST=0.0.0.0; export CLI_HTTP_PORT='$CONTAINER_CODENOMAD_PORT'; export CLI_WORKSPACE_ROOT='$WORKSPACE_PATH'; export CODENOMAD_SKIP_AUTH=true; codenomad --http=true --https=false --host 0.0.0.0 --http-port '$CONTAINER_CODENOMAD_PORT' --workspace-root '$WORKSPACE_PATH' --dangerously-skip-auth 2>&1 | rewrite_codenomad_output"
}

run_paseo() {
  echo "Starting Paseo on $HOST_PASEO_ADDRESS"
  run_as_sandbox "$(declare -f rewrite_paseo_output); export PASEO_HOME=/state/data/paseo; export PASEO_LISTEN=0.0.0.0:'$CONTAINER_PASEO_PORT'; paseo daemon start --home /state/data/paseo --listen 0.0.0.0:'$CONTAINER_PASEO_PORT' --foreground 2>&1 | rewrite_paseo_output"
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
      run_as_sandbox "exec bash -il"
      ;;
    codex)
      run_argv_as_sandbox codex "$@"
      ;;
    gemini)
      run_argv_as_sandbox gemini "$@"
      ;;
    copilot)
      run_argv_as_sandbox copilot "$@"
      ;;
    opencode)
      run_argv_as_sandbox opencode "$@"
      ;;
    codenomad)
      run_codenomad "$@"
      ;;
    paseo)
      run_paseo "$@"
      ;;
    t3)
      run_t3 "$@"
      ;;
    doctor)
      run_as_sandbox "$(declare -f run_doctor); run_doctor"
      ;;
    reset-config)
      reset_config
      ;;
    *)
      run_argv_as_sandbox "$cmd" "$@"
      ;;
  esac
}

dispatch "$@"
