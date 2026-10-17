#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
eval "$(sed -n '/^build_image() {$/,/^}$/p' "$repo_root/bin/ai-sandbox")"
eval "$(sed -n '/^engine() {$/,/^}$/p' "$repo_root/bin/ai-sandbox")"
IMAGE_TAG=test:latest
REPO_ROOT='/workspace with spaces'
docker() { docker_args=("$@"); }
podman() { docker_args=("$@"); }

for ENGINE_COMMAND in docker podman; do
  for mode in initial update rebuild; do
    UPDATE=false
    REBUILD=false
    [[ "$mode" != update ]] || UPDATE=true
    [[ "$mode" != rebuild ]] || REBUILD=true
    build_image
    [[ "${docker_args[0]}" == build ]]
    expected_pull=--pull
    [[ "$ENGINE_COMMAND" != podman ]] || expected_pull=--pull=always
    [[ "${docker_args[1]}" == "$expected_pull" ]]
    [[ "${docker_args[3]}" == "$IMAGE_TAG" ]]
    [[ "${docker_args[${#docker_args[@]}-1]}" == "$REPO_ROOT" ]]
    if [[ "$mode" == initial ]]; then
      [[ "${#docker_args[@]}" == 5 ]]
    else
      [[ "${#docker_args[@]}" == 6 ]]
      [[ "${docker_args[4]}" == --no-cache ]]
    fi
  done
done

docker() { return 17; }
podman() { return 17; }
for ENGINE_COMMAND in docker podman; do
  set +e
  ( set -e; build_image; exit 99 )
  status=$?
  set -e
  [[ "$status" == 17 ]]
done
echo 'build-image.sh passed'
