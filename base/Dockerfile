FROM ghcr.io/astral-sh/uv:0.11.3 AS uv
FROM debian:trixie

ARG USER=dev

RUN apt-get update \
    && apt-get --no-install-recommends install -y \
    build-essential \
    curl \
    ca-certificates \
    git \
    less \
    python3-dev \
    unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

# Install GH CLI
ARG TARGETARCH
RUN GH_VERSION=2.89.0 \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -C /usr/local -xz --strip-components=1 --wildcards '*/bin/*' '*/share/*'

RUN useradd -ms /bin/bash ${USER}
USER ${USER}

ENV PATH="/home/${USER}/.local/bin:${PATH}"

# Set uv cache / tool dir environment variables
ENV UV_CACHE_DIR=/tmp/uv-cache
ENV UV_TOOL_DIR=/tmp/uv-tools

# Install Node.js
ENV FNM_DIR=/home/${USER}/.fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir ${FNM_DIR} --skip-shell
ENV PATH="${FNM_DIR}:${PATH}"
RUN fnm install 25
ENV PATH="${FNM_DIR}/aliases/default/bin:${PATH}"
RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> ~/.bashrc

WORKDIR /home/${USER}/workspace
