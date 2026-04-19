#!/usr/bin/env bash
set -euo pipefail

entrypoint="${1:-/src/docker/entrypoint.sh}"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

workspace="$tmp_root/workspace"
paseo_home="$tmp_root/paseo"
mkdir -p "$workspace"

git -C "$workspace" init -q
git -C "$workspace" remote add origin https://github.com/example/demo.git

export PASEO_HOME="$paseo_home"
export AI_SANDBOX_WORKSPACE_PATH="$workspace"

# Load the entrypoint helpers without executing its final dispatcher.
source <(sed '$s/^dispatch/# dispatch/' "$entrypoint")
ensure_paseo_workspace_registry

jq -e '
  length == 1
  and .[0].projectId == "remote:github.com/example/demo"
  and .[0].rootPath == env.AI_SANDBOX_WORKSPACE_PATH
  and .[0].kind == "git"
  and .[0].archivedAt == null
' "$paseo_home/projects/projects.json" >/dev/null

jq -e '
  length == 1
  and .[0].workspaceId == env.AI_SANDBOX_WORKSPACE_PATH
  and .[0].projectId == "remote:github.com/example/demo"
  and .[0].cwd == env.AI_SANDBOX_WORKSPACE_PATH
  and .[0].kind == "local_checkout"
  and .[0].archivedAt == null
' "$paseo_home/projects/workspaces.json" >/dev/null

ensure_paseo_workspace_registry

jq -e 'length == 1' "$paseo_home/projects/projects.json" >/dev/null
jq -e 'length == 1' "$paseo_home/projects/workspaces.json" >/dev/null

echo "paseo-workspace-registry.sh passed"
