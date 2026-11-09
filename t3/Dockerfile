ARG BASE_TAG=latest
# The claude image already has Claude Code, Codex and bubblewrap.
FROM ghcr.io/recmanj/dev-containers/claude:${BASE_TAG}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# renovate: datasource=github-releases depName=pingdotgg/t3code extractVersion=^v(?<version>.+)$
ARG T3CODE_VERSION=0.1.7
RUN mkdir -p ~/.local/share/t3 \
    && curl -fsSL "https://github.com/pingdotgg/t3code/releases/download/v${T3CODE_VERSION}/t3-${T3CODE_VERSION}-linux-x64.tar.gz" \
    | tar -xz --strip-components=1 -C ~/.local/share/t3 \
    && ln -s ~/.local/share/t3/t3 ~/.local/bin/t3 \
    && t3 --version

# Listen on all interfaces inside the container; the host publishes the port
# on loopback only. Chrome's sandbox can't start under rootless podman, so the
# container is the sandbox (same as playwright-mcp).
ENV T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_SERVER_BROWSER_SANDBOX=0

ENTRYPOINT ["t3", "serve"]
