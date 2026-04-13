#!/usr/bin/env bash
set -euo pipefail

RESET_MODE="false"
if [[ "${1:-}" == "--reset" ]]; then
  RESET_MODE="true"
fi

copy_tree() {
  local src_root="$1"
  local dst_root="$2"
  mkdir -p "$dst_root"

  while IFS= read -r -d '' file; do
    rel="${file#${src_root}/}"
    target="${dst_root}/${rel}"
    mkdir -p "$(dirname "$target")"
    if [[ "$RESET_MODE" == "true" || ! -e "$target" ]]; then
      cp "$file" "$target"
    fi
  done < <(find "$src_root" -type f -print0)
}

copy_tree /opt/ai-sandbox/defaults/configs /state/config
