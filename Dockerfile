FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV AI_SANDBOX_DEFAULT_T3_PORT=3773
ENV AI_SANDBOX_REAL_BIN_DIR=/opt/ai-sandbox/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        g++ \
        git \
        jq \
        less \
        lbzip2 \
        make \
        passwd \
        procps \
        python3 \
        ripgrep \
        sudo \
        unzip \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex @anthropic-ai/claude-code @github/copilot opencode-ai t3 @neuralnomads/codenomad @getpaseo/cli \
    && curl -fsSL https://antigravity.google/cli/install.sh | bash \
    && ln -sf /root/.local/bin/agy /usr/local/bin/agy \
    && command -v agy >/dev/null \
    && curl https://cursor.com/install -fsS | bash \
    && ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor-agent \
    && ln -sf /root/.local/bin/cursor-agent /usr/local/bin/cursor \
    && command -v cursor-agent >/dev/null \
    && mkdir -p "$AI_SANDBOX_REAL_BIN_DIR" \
    && for command in codex claude agy copilot opencode cursor-agent cursor t3 codenomad paseo; do \
        shim_path="$(command -v "$command")"; \
        real_path="$(readlink -f "$shim_path")"; \
        if [ "$real_path" = "$shim_path" ]; then \
            mv "$shim_path" "$AI_SANDBOX_REAL_BIN_DIR/$command"; \
        else \
            ln -sf "$real_path" "$AI_SANDBOX_REAL_BIN_DIR/$command"; \
            rm -f "$shim_path"; \
        fi; \
        printf '%s\n' \
            '#!/usr/bin/env bash' \
            'set -euo pipefail' \
            'command="$(basename "$0")"' \
            'exec /opt/ai-sandbox/entrypoint.sh "$command" "$@"' \
            > "$shim_path"; \
        chmod +x "$shim_path"; \
    done \
    && ln -sfn "$AI_SANDBOX_REAL_BIN_DIR/cursor-agent" "$AI_SANDBOX_REAL_BIN_DIR/cursor"

RUN useradd --create-home --shell /bin/bash sandbox \
    && printf '%s\n' 'sandbox ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/sandbox \
    && chmod 0440 /etc/sudoers.d/sandbox \
    && visudo -cf /etc/sudoers.d/sandbox

RUN mkdir -p /opt/ai-sandbox/defaults/configs /opt/ai-sandbox/bootstrap /state/config /state/auth /state/data /state/cache \
    && chown -R sandbox:sandbox /opt/ai-sandbox /state /home/sandbox

COPY configs/ /opt/ai-sandbox/defaults/configs/
COPY docker/bootstrap/ /opt/ai-sandbox/bootstrap/
COPY docker/entrypoint.sh /opt/ai-sandbox/entrypoint.sh
COPY docker/claude-wrapper.sh /opt/ai-sandbox/claude-wrapper.sh
COPY tests/smoke/image-smoke-check.sh /opt/ai-sandbox/image-smoke-check.sh

RUN chmod +x /opt/ai-sandbox/entrypoint.sh /opt/ai-sandbox/claude-wrapper.sh /opt/ai-sandbox/bootstrap/*.sh /opt/ai-sandbox/image-smoke-check.sh

WORKDIR /workspace

ENTRYPOINT ["/opt/ai-sandbox/entrypoint.sh"]
CMD ["daemon"]
