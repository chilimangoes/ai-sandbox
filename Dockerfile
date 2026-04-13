FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV AI_SANDBOX_DEFAULT_T3_PORT=3773

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        g++ \
        git \
        jq \
        less \
        make \
        passwd \
        procps \
        python3 \
        ripgrep \
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex @google/gemini-cli @github/copilot t3

RUN useradd --create-home --shell /bin/bash sandbox

RUN mkdir -p /opt/ai-sandbox/defaults/configs /opt/ai-sandbox/bootstrap /state/config /state/auth /state/data /state/cache \
    && chown -R sandbox:sandbox /opt/ai-sandbox /state /home/sandbox

COPY configs/ /opt/ai-sandbox/defaults/configs/
COPY docker/bootstrap/ /opt/ai-sandbox/bootstrap/
COPY docker/entrypoint.sh /opt/ai-sandbox/entrypoint.sh
COPY tests/smoke/image-smoke-check.sh /opt/ai-sandbox/image-smoke-check.sh

RUN chmod +x /opt/ai-sandbox/entrypoint.sh /opt/ai-sandbox/bootstrap/*.sh /opt/ai-sandbox/image-smoke-check.sh

WORKDIR /workspace

ENTRYPOINT ["/opt/ai-sandbox/entrypoint.sh"]
CMD ["daemon"]
