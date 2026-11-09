ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base-agent:${BASE_TAG}

ARG USER=dev

# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.319
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}" \
    && claude --version

# Codex is included for t3, which runs both agents from this image.
# renovate: datasource=npm depName=@openai/codex
ARG CODEX_CLI_VERSION=0.167.0

USER root
RUN apt-get update \
    && apt-get --no-install-recommends install -y \
    bubblewrap \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER ${USER}

RUN npm i -g @openai/codex@${CODEX_CLI_VERSION} \
    && mkdir -p ~/.local/bin \
    && ln -s "$(which node)" ~/.local/bin/node \
    && ln -s "$(which codex)" ~/.local/bin/codex

ENTRYPOINT ["claude"]
