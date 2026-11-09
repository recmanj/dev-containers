ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base-agent:${BASE_TAG}

ARG USER=dev
ENV PATH="/home/${USER}/.opencode/bin:${PATH}"

# The opencode-ai npm package and this installer only carry OpenCode 1.
# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION=1.19.5
RUN curl -fsSL https://opencode.ai/install | bash -s -- --version "${OPENCODE_VERSION}" \
    && opencode --version

ENTRYPOINT ["opencode"]
