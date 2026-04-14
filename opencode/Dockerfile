FROM ghcr.io/recmanj/dev-containers/base:latest

ENV PATH="/home/dev/.opencode/bin:${PATH}"

RUN curl -fsSL https://opencode.ai/install | bash \
    && opencode --version

ENTRYPOINT ["opencode"]
