ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base:${BASE_TAG}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG USER=dev
# renovate: datasource=npm depName=@playwright/mcp
ARG PLAYWRIGHT_MCP_VERSION=0.0.84
# renovate: datasource=github-releases depName=rtk-ai/rtk
ARG RTK_VERSION=v1.1.0

ENV PLAYWRIGHT_BROWSERS_PATH=/home/${USER}/.cache/ms-playwright

# Install Chromium via the playwright version bundled inside @playwright/mcp
# so the browser revision always matches the MCP server.
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} \
    && cd "$(npm root -g)/@playwright/mcp" \
    && npx playwright install chromium

USER root
RUN cd "$(npm root -g)/@playwright/mcp" \
    && apt-get update \
    && npx playwright install-deps chromium \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER ${USER}

RUN playwright-mcp --version

# Install rtk into ~/.local/bin. It lives here rather than in base, which is
# also used for non-agent work.
RUN RTK_VERSION=${RTK_VERSION} \
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh \
    && rtk --version
