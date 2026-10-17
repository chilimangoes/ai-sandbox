#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
evidence_directory="${1:?Provide an evidence directory}"
if ! command -v getenforce >/dev/null || [[ "$(getenforce)" != Enforcing ]]; then
  echo 'SELinux acceptance requires a Linux host where getenforce reports Enforcing.' >&2
  exit 1
fi
if [[ "$(podman info --format '{{.Host.Security.Rootless}}')" != true || "$(podman info --format '{{.Host.Security.SELinuxEnabled}}')" != true ]]; then
  echo 'SELinux acceptance requires native rootless Podman with SELinux enabled.' >&2
  exit 1
fi
exec python3 "$repo_root/tests/launcher/podman-linux-live.py" --engine podman --run-live \
  --require-selinux-enforcing --evidence-directory "$evidence_directory"
