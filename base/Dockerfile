FROM ghcr.io/astral-sh/uv:0.13.7 AS uv
FROM alpine/helm:4.3.1 AS helm
FROM debian:trixie

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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

RUN pip install --no-cache-dir --break-system-packages PyYAML

COPY --from=uv /uv /uvx /usr/local/bin/

ARG TARGETARCH

# Install GitHub CLI
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.103.3
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -C /usr/local -xz --strip-components=1 --wildcards '*/bin/*' '*/share/*'

# Install Kubernetes tools
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.2
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
        -o /usr/local/bin/kubectl \
    && echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  /usr/local/bin/kubectl" \
    | sha256sum -c - \
    && chmod +x /usr/local/bin/kubectl
COPY --from=helm /usr/bin/helm /usr/local/bin/helm
# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize extractVersion=^kustomize/(?<version>.+)$
ARG KUSTOMIZE_VERSION=v5.8.3
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -C /usr/local/bin -xz kustomize

# Install pixi
# renovate: datasource=github-releases depName=prefix-dev/pixi
ARG PIXI_VERSION=0.84.2
RUN case "${TARGETARCH}" in \
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

RUN groupadd --gid 1000 ${USER} \
    && useradd --uid 1000 --gid ${USER} -ms /bin/bash ${USER}
USER ${USER}

ENV PATH="/home/${USER}/.local/bin:${PATH}"

ENV UV_CACHE_DIR=/tmp/uv-cache \
    UV_TOOL_DIR=/tmp/uv-tools \
    PIXI_CACHE_DIR=/tmp/pixi-cache

# Install Ansible
RUN UV_TOOL_DIR=/home/${USER}/.local/share/uv/tools \
    UV_TOOL_BIN_DIR=/home/${USER}/.local/bin \
    uv tool install ansible-core --with ansible

# Install Node.js
ENV FNM_DIR=/home/${USER}/.fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir ${FNM_DIR} --skip-shell
ENV PATH="${FNM_DIR}:${PATH}"
RUN fnm install 26
ENV PATH="${FNM_DIR}/aliases/default/bin:${PATH}"
RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> ~/.bashrc

WORKDIR /home/${USER}/workspace
