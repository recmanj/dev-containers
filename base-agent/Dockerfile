FROM ghcr.io/recmanj/dev-containers/base:latest

ARG USER=dev
ARG PLAYWRIGHT_MCP_VERSION=0.0.81
ARG RTK_VERSION=v0.49.0

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

# Install rtk (Rust Token Killer) — token-saving CLI proxy shared by all agent
# images that inherit base-agent. Pinned via RTK_VERSION; the upstream
# install.sh fetches the matching pre-built musl/gnu binary into ~/.local/bin
# (already on PATH via base). Kept out of the generic base image, which is also
# used standalone for non-AI dev work.
RUN RTK_VERSION=${RTK_VERSION} \
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh \
    && rtk --version
