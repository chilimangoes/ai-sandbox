#!/usr/bin/env bash
set -euo pipefail

chrome="$1"
[[ "$(id -u)" != "0" ]]
[[ -n "$(fc-match --format='%{file}' sans-serif)" ]]
unshare --user --map-root-user true

profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT
output="$(timeout -k 2 20 "$chrome" \
  --user-data-dir="$profile" \
  --disable-gpu --disable-dev-shm-usage --no-first-run \
  --dump-dom 'data:text/html,<title>T3 browser test</title><p>sandbox-browser-ok</p>')"
[[ "$output" == *'<p>sandbox-browser-ok</p>'* ]]
echo 'PASS: non-root Chrome renders a page with its sandbox and system fonts available'
