FROM ghcr.io/recmanj/dev-containers/base:latest

RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version

ENTRYPOINT ["claude"]
