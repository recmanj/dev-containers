FROM ghcr.io/recmanj/dev-containers/base-browser:latest

ARG USER=dev
ARG CODEX_CLI_VERSION=latest

USER root
RUN apt-get update \
    && apt-get --no-install-recommends install -y \
    bubblewrap \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER dev

RUN npm i -g @openai/codex@${CODEX_CLI_VERSION} \
    && mkdir -p ~/.local/bin \
    && ln -s "$(which node)" ~/.local/bin/node \
    && ln -s "$(which codex)" ~/.local/bin/codex

ENTRYPOINT ["codex"]
