FROM ghcr.io/recmanj/dev-containers/base-agent:latest

RUN curl -fsSL https://pi.dev/install.sh | sh \
    && pi --version

ENTRYPOINT ["pi"]
