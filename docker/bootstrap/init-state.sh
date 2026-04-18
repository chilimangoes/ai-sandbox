#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /state/config \
  /state/auth \
  /state/data \
  /state/cache \
  /state/config/codex \
  /state/config/gemini \
  /state/config/copilot \
  /state/config/opencode \
  /state/config/codenomad \
  /state/config/paseo \
  /state/config/t3 \
  /state/config/shared \
  /state/auth/codex \
  /state/auth/gemini \
  /state/auth/copilot \
  /state/auth/opencode \
  /state/data/codex \
  /state/data/gemini/home \
  /state/data/gemini \
  /state/data/copilot \
  /state/data/opencode \
  /state/data/codenomad \
  /state/data/codenomad/instances \
  /state/data/codenomad/tls \
  /state/data/paseo \
  /state/data/t3 \
  /state/cache/npm \
  /state/cache/opencode

/opt/ai-sandbox/bootstrap/sync-configs.sh

mkdir -p /home/sandbox/.codex /home/sandbox/.copilot /home/sandbox/.config /home/sandbox/.cache /home/sandbox/.local/share

ln -sfn /state/config/codex/config.toml /home/sandbox/.codex/config.toml
ln -sfn /state/auth/codex/auth.json /home/sandbox/.codex/auth.json
ln -sfn /state/data/codex/sessions /home/sandbox/.codex/sessions

rm -rf /home/sandbox/.gemini
ln -sfn /state/data/gemini/home /home/sandbox/.gemini
ln -sfn /state/config/gemini/settings.json /state/data/gemini/home/settings.json
ln -sfn /state/auth/gemini /state/data/gemini/home/auth

ln -sfn /state/config/copilot/config.json /home/sandbox/.copilot/config.json
ln -sfn /state/auth/copilot /home/sandbox/.copilot/auth
ln -sfn /state/data/copilot /home/sandbox/.copilot/sessions

rm -rf /home/sandbox/.config/opencode /home/sandbox/.local/share/opencode /home/sandbox/.cache/opencode
ln -sfn /state/config/opencode /home/sandbox/.config/opencode
ln -sfn /state/data/opencode /home/sandbox/.local/share/opencode
ln -sfn /state/auth/opencode/auth.json /state/data/opencode/auth.json
ln -sfn /state/cache/opencode /home/sandbox/.cache/opencode

mkdir -p /home/sandbox/.config/codenomad
ln -sfn /state/config/codenomad/config.json /home/sandbox/.config/codenomad/config.json
ln -sfn /state/data/codenomad/instances /home/sandbox/.config/codenomad/instances
ln -sfn /state/data/codenomad/tls /home/sandbox/.config/codenomad/tls

rm -rf /home/sandbox/.paseo
ln -sfn /state/data/paseo /home/sandbox/.paseo
if [[ -f /state/config/paseo/config.json ]] && grep -q '"\$schema"' /state/config/paseo/config.json; then
  tmp_paseo_config="$(mktemp)"
  jq 'del(."$schema")' /state/config/paseo/config.json > "$tmp_paseo_config"
  mv "$tmp_paseo_config" /state/config/paseo/config.json
fi
ln -sfn /state/config/paseo/config.json /state/data/paseo/config.json

ln -sfn /state/config/t3/config.json /home/sandbox/.config/ai-sandbox-t3.json

ln -sfn /state/cache/npm /home/sandbox/.npm

mkdir -p /state/data/codex/sessions
