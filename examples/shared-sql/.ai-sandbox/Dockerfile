ARG AI_SANDBOX_BASE_IMAGE=ai-sandbox:latest
FROM ${AI_SANDBOX_BASE_IMAGE}

RUN curl -fsSL https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb \
      -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends dotnet-sdk-10.0 \
    && rm -rf /var/lib/apt/lists/*
