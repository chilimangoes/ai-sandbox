#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher="$repo_root/bin/ai-sandbox"
helper="$repo_root/scripts/add-supplemental-folder.sh"

[[ -f "$helper" ]]

grep -Fq -- "--add-folder" "$launcher"
grep -Fq "supplemental_mount_args" "$launcher"
grep -Fq "supplemental-folders.config" "$launcher"
grep -Fq "ai-sandbox.supplemental-folders" "$launcher"
grep -Fq "/supplemental/" "$launcher"
grep -Fq ':${mode_by_name[$name]}' "$launcher"
grep -Fq "local supplemental folder overrides global mapping" "$launcher"

grep -Fq "split_supplemental_folder_line" "$helper"
grep -Fq ".ai-sandbox" "$helper"
grep -Fq "supplemental-folders.config" "$helper"
grep -Fq -- "--read-write" "$helper"
grep -Fq -- "--read-only" "$helper"
grep -Fq '${line%|*}' "$helper"
grep -Fq "Replace" "$helper"

echo "supplemental-folders.sh passed"
