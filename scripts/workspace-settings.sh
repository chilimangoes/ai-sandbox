#!/usr/bin/env bash

# Workspace definitions are data. Values are passed to Docker as separate arguments.
read_workspace_settings() {
  WORKSPACE_RUN_ARGS=()
  WORKSPACE_NETWORKS=()
  WORKSPACE_SETTINGS_SIGNATURE=""
  local path="$WORKSPACE_PATH/.ai-sandbox/workspace.config"
  [[ -f "$path" ]] || return 0
  local line key value name port line_number=0
  local entries=()
  declare -A seen=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    if ((line_number == 1)); then line="${line#$'\xef\xbb\xbf'}"; fi
    [[ -n "${line//[[:space:]]/}" ]] || continue
    [[ "${line#"${line%%[![:space:]]*}"}" != \#* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if [[ "$line" != *=* ]]; then
      echo "Invalid workspace setting in $path:$line_number. Expected network=NAME, port=NUMBER, or env=NAME=VALUE." >&2
      return 1
    fi
    case "$key" in
      network)
        [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && "$value" != bridge && "$value" != host && "$value" != none ]] || {
          echo "Invalid named Docker network in $path:$line_number: $value" >&2; return 1;
        }
        name="network:$value"
        WORKSPACE_NETWORKS+=("$value")
        WORKSPACE_RUN_ARGS+=(--network "$value")
        ;;
      port)
        [[ "$value" =~ ^[0-9]{1,5}$ ]] || { echo "Invalid TCP port in $path:$line_number: $value" >&2; return 1; }
        port=$((10#$value))
        ((port >= 1 && port <= 65535)) || { echo "TCP port out of range in $path:$line_number: $value" >&2; return 1; }
        name="port:$port"
        value="$port"
        if [[ "$port" != "$DEFAULT_T3_CONTAINER_PORT" && "$port" != "$DEFAULT_ALT_HTTP_CONTAINER_PORT" && "$port" != "$DEFAULT_APP_CONTAINER_PORT" ]]; then
          WORKSPACE_RUN_ARGS+=(-p "$HOST_ADDRESS:$port:$port")
        fi
        ;;
      env)
        name="${value%%=*}"
        [[ "$value" == *=* && "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
          echo "Invalid environment setting in $path:$line_number." >&2; return 1;
        }
        case "$name" in
          AI_SANDBOX_*|LOCAL_UID|LOCAL_GID|HOME|PATH|USER|LOGNAME)
            echo "Reserved environment variable in $path:$line_number: $name" >&2; return 1 ;;
        esac
        WORKSPACE_RUN_ARGS+=(-e "$value")
        name="env:$name"
        ;;
      *) echo "Unknown workspace setting in $path:$line_number: $key" >&2; return 1 ;;
    esac
    [[ -z "${seen[$name]:-}" ]] || { echo "Duplicate workspace setting in $path:$line_number: $name" >&2; return 1; }
    seen["$name"]=true
    entries+=("$key=$value")
  done < "$path"
  if ((${#entries[@]})); then
    WORKSPACE_SETTINGS_SIGNATURE="$(printf '%s\n' "${entries[@]}" | LC_ALL=C sort | sha256sum | awk '{print $1}')"
  fi
}

container_runtime_image() {
  # Compare the runnable platform manifest, excluding the index's build attestations.
  local descriptor platform
  descriptor="$(docker inspect --format '{{if .ImageManifestDescriptor}}{{.ImageManifestDescriptor.digest}} {{.ImageManifestDescriptor.platform.os}}/{{.ImageManifestDescriptor.platform.architecture}}{{if .ImageManifestDescriptor.platform.variant}}/{{.ImageManifestDescriptor.platform.variant}}{{end}}{{end}}' "$CONTAINER_NAME")" || return 1
  if [[ -z "$descriptor" ]]; then
    RUNTIME_RUNNING_IMAGE="$1"
    RUNTIME_CURRENT_IMAGE="$(image_id "$IMAGE_TAG")"
    [[ -n "$RUNTIME_CURRENT_IMAGE" ]] || { echo 'Could not inspect the workspace image.' >&2; return 1; }
    return
  fi
  read -r RUNTIME_RUNNING_IMAGE platform <<< "$descriptor"
  RUNTIME_CURRENT_IMAGE="$(docker image inspect --platform "$platform" --format '{{.Id}}' "$IMAGE_TAG")" || {
    echo 'Could not inspect the workspace platform image. The existing container has not been replaced.' >&2
    return 1
  }
}

check_workspace_networks() {
  local network
  for network in "${WORKSPACE_NETWORKS[@]}"; do
    docker network inspect "$network" >/dev/null 2>&1 || {
      echo "Docker network '$network' is missing. Run the project's host bootstrap before ai-sandbox." >&2
      return 1
    }
  done
}

workspace_trust_path() {
  printf '%s/.ai-sandbox/trusted-workspaces/%s' "$HOME" "$WORKSPACE_HASH"
}

trust_workspace() {
  local path
  path="$(workspace_trust_path)"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$WORKSPACE_PATH" > "$path"
  echo "Trusted sandbox build and launch definitions in $WORKSPACE_PATH. Revoke with ai-sandbox untrust."
}

ensure_workspace_trust() {
  [[ -f "$WORKSPACE_PATH/.ai-sandbox/Dockerfile" || -f "$WORKSPACE_PATH/.ai-sandbox/workspace.config" ]] || return 0
  local path answer
  path="$(workspace_trust_path)"
  [[ ! -f "$path" || "$(cat "$path")" != "$WORKSPACE_PATH" ]] || return 0
  if [[ ! -t 0 ]]; then
    echo "Workspace customization requires approval. Run ai-sandbox trust in $WORKSPACE_PATH, then retry." >&2
    return 1
  fi
  printf 'Trust sandbox build and launch definitions in %s, including future edits? [y/N] ' "$WORKSPACE_PATH"
  read -r answer
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]] || { echo 'Workspace trust declined.' >&2; return 1; }
  trust_workspace
}

# File locks are released by the OS if the launcher exits or is interrupted.
lock_workspace() {
  command -v flock >/dev/null || { echo 'ai-sandbox requires flock (util-linux).' >&2; return 1; }
  mkdir -p "$HOME/.ai-sandbox/locks"
  exec 9>"$HOME/.ai-sandbox/locks/workspace-$WORKSPACE_HASH.lock"
  flock -w 600 9 || { echo 'Timed out waiting for another launcher in this workspace.' >&2; return 1; }
}

prepare_workspace_image() {
  local base_ref base_id
  exec 8>"$HOME/.ai-sandbox/locks/base-image.lock"
  flock -w 600 8 || { echo 'Timed out waiting for the shared image build.' >&2; return 1; }
  if [[ -z "$(image_id "$IMAGE_TAG")" || "$UPDATE" == true || "$REBUILD" == true ]]; then
    build_image
  fi
  if [[ -f "$WORKSPACE_PATH/.ai-sandbox/Dockerfile" ]]; then
    base_id="$(image_id "$IMAGE_TAG")"
    [[ -n "$base_id" ]] || { echo "Image $IMAGE_TAG not found after build." >&2; return 1; }
    base_ref="ai-sandbox-base:${base_id#sha256:}"
    docker tag "$base_id" "$base_ref"
  fi
  flock -u 8
  exec 8>&-
  [[ -f "$WORKSPACE_PATH/.ai-sandbox/Dockerfile" ]] || return 0
  local tag="ai-sandbox-workspace:$WORKSPACE_HASH"
  local build_args=(build -t "$tag" --file "$WORKSPACE_PATH/.ai-sandbox/Dockerfile" --build-arg "AI_SANDBOX_BASE_IMAGE=$base_ref")
  if [[ "$UPDATE" == true || "$REBUILD" == true ]]; then
    build_args+=(--no-cache)
  fi
  echo "Building workspace image $tag"
  docker "${build_args[@]}" "$WORKSPACE_PATH/.ai-sandbox" || {
    echo 'Workspace image build failed. The existing container has not been replaced.' >&2
    return 1
  }
  IMAGE_TAG="$tag"
}
