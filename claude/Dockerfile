FROM ghcr.io/recmanj/dev-containers/base:latest

ARG USER=dev
ARG CLAUDE_CODE_VERSION=latest

RUN npm i -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && mkdir -p ~/.local/bin \
    && ln -s "$(which node)" ~/.local/bin/node \
    && ln -s "$(which claude)" ~/.local/bin/claude

ENTRYPOINT ["claude"]
