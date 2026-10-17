#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "$SCRIPT_DIR/lib/engine.sh"
parse_engine_options "$@"
[[ "$SKIP_BUILD" == false ]] || { echo '--skip-build is only valid for smoke checks.' >&2; exit 1; }
ENGINE_COMMAND="$(resolve_engine "$REQUESTED_ENGINE")"
pull=--pull
[[ "$ENGINE_COMMAND" != podman ]] || pull=--pull=always
build_args=(build "$pull" -t ai-sandbox:latest)
[[ "$NO_CACHE" == false ]] || build_args+=(--no-cache)
engine "${build_args[@]}" "$REPO_ROOT"
