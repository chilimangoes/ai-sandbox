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
DEFAULT_HTTP_PORT="${AI_SANDBOX_DEFAULT_HTTP_PORT:-80}"
CONTAINER_HTTP_PORT="${AI_SANDBOX_HTTP_PORT:-$DEFAULT_HTTP_PORT}"
HOST_HTTP_URL="${AI_SANDBOX_HTTP_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_HTTP_PORT:-$CONTAINER_HTTP_PORT}}"
DEFAULT_ALT_HTTP_PORT="${AI_SANDBOX_DEFAULT_ALT_HTTP_PORT:-8080}"
CONTAINER_ALT_HTTP_PORT="${AI_SANDBOX_ALT_HTTP_PORT:-$DEFAULT_ALT_HTTP_PORT}"
HOST_ALT_HTTP_URL="${AI_SANDBOX_ALT_HTTP_URL:-http://127.0.0.1:${AI_SANDBOX_HOST_ALT_HTTP_PORT:-$CONTAINER_ALT_HTTP_PORT}}"
WORKSPACE_PATH="${AI_SANDBOX_WORKSPACE_PATH:-/workspace}"
SANDBOX_CONFIG_PATH="/state/config/shared/sandbox.config"

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
  exec runuser -u sandbox -- /bin/bash -lc "export AI_SANDBOX_T3_URL='$HOST_T3_URL'; export AI_SANDBOX_T3_PORT='$CONTAINER_T3_PORT'; export AI_SANDBOX_CODENOMAD_URL='$HOST_CODENOMAD_URL'; export AI_SANDBOX_CODENOMAD_PORT='$CONTAINER_CODENOMAD_PORT'; export AI_SANDBOX_PASEO_ADDRESS='$HOST_PASEO_ADDRESS'; export AI_SANDBOX_PASEO_PORT='$CONTAINER_PASEO_PORT'; export AI_SANDBOX_HTTP_URL='$HOST_HTTP_URL'; export AI_SANDBOX_HTTP_PORT='$CONTAINER_HTTP_PORT'; export AI_SANDBOX_ALT_HTTP_URL='$HOST_ALT_HTTP_URL'; export AI_SANDBOX_ALT_HTTP_PORT='$CONTAINER_ALT_HTTP_PORT'; export AI_SANDBOX_WORKSPACE_PATH='$WORKSPACE_PATH'; cd '$WORKSPACE_PATH'; $command"
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
  printf 'Web Port 80: %s\n' "$HOST_HTTP_URL"
  printf 'Web Port 8080: %s\n' "$HOST_ALT_HTTP_URL"
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

get_paseo_relay_flag() {
  local paseo_relay=""

  if [[ -f "$SANDBOX_CONFIG_PATH" ]]; then
    paseo_relay="$(grep -E '^[[:space:]]*paseo_relay=' "$SANDBOX_CONFIG_PATH" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]')"
  fi

  if [[ "$paseo_relay" == "1" ]]; then
    printf ''
  else
    printf '%s' '--no-relay'
  fi
}

cleanup_paseo_daemon() {
  paseo daemon stop --home /state/data/paseo --force >/dev/null 2>&1 || true
  rm -f /state/data/paseo/paseo.pid
}

ensure_paseo_workspace_registry() {
  node <<'NODE'
const { randomUUID } = require("node:crypto");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const paseoHome = process.env.PASEO_HOME || "/state/data/paseo";
const workspacePath = path.resolve(process.env.AI_SANDBOX_WORKSPACE_PATH || process.cwd());
const projectsDir = path.join(paseoHome, "projects");
const projectsPath = path.join(projectsDir, "projects.json");
const workspacesPath = path.join(projectsDir, "workspaces.json");

function runGit(args) {
  try {
    return execFileSync("git", ["-C", workspacePath, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return null;
  }
}

function deriveRemoteProjectKey(remoteUrl) {
  if (!remoteUrl || !remoteUrl.trim()) {
    return null;
  }

  const trimmed = remoteUrl.trim();
  let host = null;
  let remotePath = null;
  const scpLike = trimmed.match(/^[^@]+@([^:]+):(.+)$/);

  if (scpLike) {
    host = scpLike[1] || null;
    remotePath = scpLike[2] || null;
  } else if (trimmed.includes("://")) {
    try {
      const parsed = new URL(trimmed);
      host = parsed.hostname || null;
      remotePath = parsed.pathname ? parsed.pathname.replace(/^\/+/, "") : null;
    } catch {
      return null;
    }
  }

  if (!host || !remotePath) {
    return null;
  }

  let cleanedPath = remotePath.trim().replace(/^\/+/, "").replace(/\/+$/, "");
  if (cleanedPath.endsWith(".git")) {
    cleanedPath = cleanedPath.slice(0, -4);
  }
  if (!cleanedPath.includes("/")) {
    return null;
  }

  const cleanedHost = host.toLowerCase();
  if (cleanedHost === "github.com") {
    return `remote:github.com/${cleanedPath}`;
  }
  return `remote:${cleanedHost}/${cleanedPath}`;
}

function displayNameForProject(projectId) {
  const githubPrefix = "remote:github.com/";
  if (projectId.startsWith(githubPrefix)) {
    return projectId.slice(githubPrefix.length) || projectId;
  }
  return path.basename(projectId) || projectId;
}

function readRecords(filePath) {
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function upsertRecord(records, idKey, record) {
  const index = records.findIndex((entry) => entry && entry[idKey] === record[idKey]);
  if (index === -1) {
    records.push(record);
    return;
  }
  records[index] = {
    ...records[index],
    ...record,
    createdAt: records[index].createdAt || record.createdAt,
    archivedAt: null,
  };
}

function writeRecords(filePath, records) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const tempPath = `${filePath}.${process.pid}.${Date.now()}.${randomUUID()}.tmp`;
  fs.writeFileSync(tempPath, `${JSON.stringify(records, null, 2)}\n`, "utf8");
  fs.renameSync(tempPath, filePath);
}

const isGit = runGit(["rev-parse", "--is-inside-work-tree"]) === "true";
const gitRoot = isGit ? runGit(["rev-parse", "--show-toplevel"]) : null;
const workspaceId = path.resolve(gitRoot || workspacePath);
const currentBranch = isGit ? runGit(["branch", "--show-current"]) : null;
const remoteUrl = isGit ? runGit(["config", "--get", "remote.origin.url"]) : null;
const projectId = deriveRemoteProjectKey(remoteUrl) || workspaceId;
const now = new Date().toISOString();
const workspaceDisplayName =
  currentBranch && currentBranch.toUpperCase() !== "HEAD"
    ? currentBranch
    : path.basename(workspaceId) || workspaceId;

const projectRecord = {
  projectId,
  rootPath: workspaceId,
  kind: isGit ? "git" : "non_git",
  displayName: displayNameForProject(projectId),
  createdAt: now,
  updatedAt: now,
  archivedAt: null,
};

const workspaceRecord = {
  workspaceId,
  projectId,
  cwd: workspaceId,
  kind: isGit ? "local_checkout" : "directory",
  displayName: workspaceDisplayName,
  createdAt: now,
  updatedAt: now,
  archivedAt: null,
};

const projects = readRecords(projectsPath);
const workspaces = readRecords(workspacesPath);
upsertRecord(projects, "projectId", projectRecord);
upsertRecord(workspaces, "workspaceId", workspaceRecord);
writeRecords(projectsPath, projects);
writeRecords(workspacesPath, workspaces);
NODE
}

run_paseo() {
  local PASEO_RELAY_FLAG
  PASEO_RELAY_FLAG="$(get_paseo_relay_flag)"

  echo "Starting Paseo on $HOST_PASEO_ADDRESS"
  run_as_sandbox "$(declare -f rewrite_paseo_output cleanup_paseo_daemon ensure_paseo_workspace_registry); trap cleanup_paseo_daemon INT TERM EXIT; cleanup_paseo_daemon; export PASEO_HOME=/state/data/paseo; ensure_paseo_workspace_registry; export PASEO_LISTEN=0.0.0.0:'$CONTAINER_PASEO_PORT'; paseo daemon start --home /state/data/paseo --listen 0.0.0.0:'$CONTAINER_PASEO_PORT' --foreground $PASEO_RELAY_FLAG > >(rewrite_paseo_output) 2>&1 & paseo_pid=\$!; wait \"\$paseo_pid\""
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
