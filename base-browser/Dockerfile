FROM ghcr.io/recmanj/dev-containers/base:latest

ARG USER=dev
ARG PLAYWRIGHT_MCP_VERSION=0.0.76

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
