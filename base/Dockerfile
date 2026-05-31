FROM ghcr.io/astral-sh/uv:0.11.15 AS uv
FROM bitnami/kubectl:latest AS kubectl
FROM alpine/helm:4.2.0 AS helm
FROM debian:trixie

LABEL devcontainer.metadata='[]'

ARG USER=dev

RUN apt-get update \
    && apt-get --no-install-recommends install -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    just \
    jq \
    less \
    libboost-all-dev \
    openssh-client \
    pre-commit \
    python-is-python3 \
    python3-dev \
    python3-pip \
    ripgrep \
    unzip \
    yq \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --break-system-packages PyYAML

COPY --from=uv /uv /uvx /usr/local/bin/

# Install GH CLI
ARG TARGETARCH
RUN GH_VERSION=2.92.0 \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -C /usr/local -xz --strip-components=1 --wildcards '*/bin/*' '*/share/*'

# Install Kubernetes tools
COPY --from=kubectl /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm /usr/local/bin/helm
RUN KUSTOMIZE_VERSION=v5.8.1 \
    && curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -C /usr/local/bin -xz kustomize

# Install pixi
RUN PIXI_VERSION=0.68.1 \
    && case "${TARGETARCH}" in \
        amd64) PIXI_ARCH=x86_64 ;; \
        arm64) PIXI_ARCH=aarch64 ;; \
    esac \
    && curl -fsSL "https://github.com/prefix-dev/pixi/releases/download/v${PIXI_VERSION}/pixi-${PIXI_ARCH}-unknown-linux-musl" \
        -o /usr/local/bin/pixi \
    && chmod +x /usr/local/bin/pixi

# Install OpenTofu
ADD https://get.opentofu.org/install-opentofu.sh /var/tmp/install-opentofu.sh
RUN chmod +x /var/tmp/install-opentofu.sh \
    && /var/tmp/install-opentofu.sh --install-method deb \
    && rm -f /var/tmp/install-opentofu.sh

RUN useradd -ms /bin/bash ${USER}
USER ${USER}

ENV PATH="/home/${USER}/.local/bin:${PATH}"

# Set uv cache / tool dir environment variables
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV UV_TOOL_DIR=/tmp/uv-tools

# Set pixi cache dir
ENV PIXI_CACHE_DIR=/tmp/pixi-cache

# Install Node.js
ENV FNM_DIR=/home/${USER}/.fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir ${FNM_DIR} --skip-shell
ENV PATH="${FNM_DIR}:${PATH}"
RUN fnm install 26
ENV PATH="${FNM_DIR}/aliases/default/bin:${PATH}"
RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> ~/.bashrc

WORKDIR /home/${USER}/workspace
