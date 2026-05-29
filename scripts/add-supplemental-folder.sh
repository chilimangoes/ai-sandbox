#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

usage() {
  echo "Usage: ai-sandbox --add-folder <path> [--as <name>] [--global|--local] [--read-only|--read-write] [--yes]"
}

container_folder_name_valid() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  [[ "$name" == "${name#"${name%%[![:space:]]*}"}" ]] || return 1
  [[ "$name" == "${name%"${name##*[![:space:]]}"}" ]] || return 1
  [[ "$name" != *"/"* && "$name" != *"\\"* && "$name" != *":"* && "$name" != *"*"* &&
    "$name" != *"?"* && "$name" != *"\""* && "$name" != *"<"* && "$name" != *">"* &&
    "$name" != *"|"* ]]
}

split_supplemental_folder_line() {
  local line="$1"
  [[ -n "${line//[[:space:]]/}" ]] || return 1
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ "$trimmed" != \#* ]] || return 1

  local mode="ro"
  local without_mode="$line"
  if [[ "$line" == *"|"* ]]; then
    local candidate_mode="${line##*|}"
    if [[ "$candidate_mode" == "ro" || "$candidate_mode" == "rw" ]]; then
      mode="$candidate_mode"
      without_mode="${line%|*}"
    fi
  fi

  if [[ "$without_mode" != *"|"* ]]; then
    echo "Invalid supplemental folder line: $line" >&2
    return 2
  fi

  SPLIT_HOST_PATH="${without_mode%|*}"
  SPLIT_CONTAINER_NAME="${without_mode##*|}"
  SPLIT_MODE="$mode"
}

read_choice() {
  local prompt="$1"
  local default="$2"
  local suffix="[y/N]"
  [[ "$default" == "y" ]] && suffix="[Y/n]"
  local answer
  read -r -p "${prompt} ${suffix} " answer
  if [[ -z "${answer//[[:space:]]/}" ]]; then
    echo "$default"
  else
    echo "${answer:0:1}" | tr '[:upper:]' '[:lower:]'
  fi
}

folder_path=""
container_name=""
scope=""
mode=""
yes="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --path)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --path." >&2; exit 1; }
      folder_path="$1"
      shift
      ;;
    --as)
      shift
      [[ $# -gt 0 ]] || { echo "Missing value for --as." >&2; exit 1; }
      container_name="$1"
      shift
      ;;
    --global)
      scope="global"
      shift
      ;;
    --local)
      scope="local"
      shift
      ;;
    --read-only)
      mode="ro"
      shift
      ;;
    --read-write)
      mode="rw"
      shift
      ;;
    --yes)
      yes="true"
      shift
      ;;
    --*)
      echo "Unknown option for --add-folder: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$folder_path" ]]; then
        echo "Unexpected argument for --add-folder: $1" >&2
        exit 1
      fi
      folder_path="$1"
      shift
      ;;
  esac
done

[[ -n "$folder_path" ]] || { echo "Missing folder path for --add-folder." >&2; exit 1; }
[[ -d "$folder_path" ]] || { echo "Supplemental folder does not exist or is not a directory: $folder_path" >&2; exit 1; }
resolved_folder_path="$(cd "$folder_path" && pwd)"

if [[ -z "$container_name" ]]; then
  default_name="$(basename "$resolved_folder_path")"
  read -r -p "Container folder name under /supplemental [${default_name}] " container_name
  [[ -n "${container_name//[[:space:]]/}" ]] || container_name="$default_name"
fi

if ! container_folder_name_valid "$container_name"; then
  echo "Invalid container folder name '$container_name'. It must be one path segment and cannot contain / \\ : * ? \" < > |." >&2
  exit 1
fi

if [[ -z "$scope" ]]; then
  read -r -p "Scope: local or global [local] " scope
  [[ -n "${scope//[[:space:]]/}" ]] || scope="local"
  scope="$(printf '%s' "$scope" | tr '[:upper:]' '[:lower:]')"
fi
[[ "$scope" == "local" || "$scope" == "global" ]] || { echo "Scope must be local or global." >&2; exit 1; }

if [[ -z "$mode" ]]; then
  read_only="$(read_choice "Mount read-only?" "y")"
  if [[ "$read_only" == "n" ]]; then
    mode="rw"
  else
    mode="ro"
  fi
fi

if [[ "$scope" == "global" ]]; then
  config_path="${HOME}/.ai-sandbox/supplemental-folders.config"
else
  config_path="${PWD}/.ai-sandbox/supplemental-folders.config"
fi

mkdir -p "$(dirname "$config_path")"
new_line="${resolved_folder_path}|${container_name}|${mode}"
tmp_path="${config_path}.tmp.$$"
replaced="false"

if [[ -f "$config_path" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    if split_supplemental_folder_line "$line"; then
      if [[ "$SPLIT_CONTAINER_NAME" == "$container_name" ]]; then
        if [[ "$replaced" == "false" ]]; then
          if [[ "$yes" != "true" ]]; then
            echo "/supplemental/${container_name} is already configured in ${scope} config:"
            echo
            echo "  ${SPLIT_HOST_PATH} -> /supplemental/${SPLIT_CONTAINER_NAME}"
            echo
            echo "Replace it with this mapping?"
            echo
            echo "  ${resolved_folder_path} -> /supplemental/${container_name}"
            echo
            replace="$(read_choice "Replace existing entry?" "y")"
            if [[ "$replace" == "n" ]]; then
              rm -f "$tmp_path"
              echo "No changes made."
              exit 0
            fi
          fi
          echo "$new_line" >>"$tmp_path"
          replaced="true"
        fi
      else
        echo "$line" >>"$tmp_path"
      fi
    else
      echo "$line" >>"$tmp_path"
    fi
  done <"$config_path"
fi

if [[ "$replaced" == "false" ]]; then
  echo "$new_line" >>"$tmp_path"
fi

mv "$tmp_path" "$config_path"
echo "Added supplemental folder mapping:"
echo "  ${resolved_folder_path} -> /supplemental/${container_name} (${mode}, ${scope})"
echo "Config: ${config_path}"

if [[ "$yes" != "true" ]]; then
  rebuild="$(read_choice "Newly added folders require rebuilding the sandbox container. Do you want to rebuild the container for the current workspace now?" "y")"
  if [[ "$rebuild" == "n" ]]; then
    echo "Run ai-sandbox --rebuild from this workspace when you want the new mapping mounted."
    exit 0
  fi
fi

"${repo_root}/bin/ai-sandbox" --rebuild
