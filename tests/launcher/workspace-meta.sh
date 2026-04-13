#!/usr/bin/env bash
set -euo pipefail

workspace="/tmp/Example Repo"
leaf="$(basename "$workspace")"
slug="$(printf '%s' "$leaf" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ "$slug" == "example-repo" ]]
hash="$(printf '%s' "/tmp/example repo" | sha256sum | awk '{print $1}')"
[[ "${#hash}" -eq 64 ]]
echo "workspace-meta.sh passed"
