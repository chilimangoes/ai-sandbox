#!/usr/bin/env bash
set -euo pipefail

workspace="/tmp/Example Repo"
leaf="$(basename "$workspace")"
slug="$(printf '%s' "$leaf" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ "$slug" == "example-repo" ]]
container_workspace_path="/workspace/$slug"
[[ "$container_workspace_path" == "/workspace/example-repo" ]]
hash="$(printf '%s' "/tmp/example repo" | sha256sum | awk '{print $1}')"
[[ "${#hash}" -eq 64 ]]
loopback_octet_2=$((64 + (16#${hash:0:2} % 64)))
loopback_octet_3=$((16#${hash:2:2}))
loopback_octet_4=$((1 + (16#${hash:4:2} % 254)))
host_address="127.${loopback_octet_2}.${loopback_octet_3}.${loopback_octet_4}"
[[ "$host_address" =~ ^127\.([6-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.([1-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])$ ]]
echo "workspace-meta.sh passed"
