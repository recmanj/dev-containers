FROM ghcr.io/recmanj/dev-containers/base-browser:latest

RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version

ENTRYPOINT ["claude"]
