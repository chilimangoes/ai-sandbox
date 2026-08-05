#!/usr/bin/env bash
set -euo pipefail

mkdir -p \
  /state/config \
  /state/auth \
  /state/data \
  /state/cache \
  /state/config/codex \
  /state/config/antigravity \
  /state/config/copilot \
  /state/config/opencode \
  /state/config/cursor \
  /state/config/codenomad \
  /state/config/paseo \
  /state/config/t3 \
  /state/config/shared \
  /state/auth/codex \
  /state/auth/antigravity \
  /state/auth/copilot \
  /state/auth/opencode \
  /state/data/codex \
  /state/data/claude \
  /state/data/claude/home \
  /state/data/antigravity/home \
  /state/data/antigravity \
  /state/data/copilot \
  /state/data/opencode \
  /state/data/cursor \
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

if [[ -d /home/sandbox/.claude && ! -L /home/sandbox/.claude ]] && [[ -z "$(find /state/data/claude/home -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  cp -a /home/sandbox/.claude/. /state/data/claude/home/
fi
rm -rf /home/sandbox/.claude
ln -sfn /state/data/claude/home /home/sandbox/.claude

if [[ -f /home/sandbox/.claude.json && ! -L /home/sandbox/.claude.json ]] && [[ ! -s /state/data/claude/claude.json ]]; then
  cp /home/sandbox/.claude.json /state/data/claude/claude.json
fi
touch /state/data/claude/claude.json
rm -f /home/sandbox/.claude.json
cp /state/data/claude/claude.json /home/sandbox/.claude.json

rm -rf /home/sandbox/.antigravity
ln -sfn /state/data/antigravity/home /home/sandbox/.antigravity
ln -sfn /state/config/antigravity/settings.json /state/data/antigravity/home/settings.json
ln -sfn /state/auth/antigravity /state/data/antigravity/home/auth

ln -sfn /state/config/copilot/config.json /home/sandbox/.copilot/config.json
ln -sfn /state/auth/copilot /home/sandbox/.copilot/auth
ln -sfn /state/data/copilot /home/sandbox/.copilot/sessions

rm -rf /home/sandbox/.config/opencode /home/sandbox/.local/share/opencode /home/sandbox/.cache/opencode
ln -sfn /state/config/opencode /home/sandbox/.config/opencode
ln -sfn /state/data/opencode /home/sandbox/.local/share/opencode
ln -sfn /state/auth/opencode/auth.json /state/data/opencode/auth.json
ln -sfn /state/cache/opencode /home/sandbox/.cache/opencode

rm -rf /home/sandbox/.cursor
if [[ -f /state/data/cursor/cli-config.json && ! -L /state/data/cursor/cli-config.json ]]; then
  mv /state/data/cursor/cli-config.json /state/config/cursor/cli-config.json
fi
ln -sfn /state/config/cursor/cli-config.json /state/data/cursor/cli-config.json
ln -sfn /state/data/cursor /home/sandbox/.cursor

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
