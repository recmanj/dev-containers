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

RUN useradd -ms /bin/bash ${USER}
USER ${USER}

ENV PATH="/home/${USER}/.local/bin:${PATH}"

ENV FNM_DIR=/home/${USER}/.fnm
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "/home/${USER}/.fnm" --skip-shell
ENV PATH="/home/${USER}/.fnm:${PATH}"
RUN fnm install 25
ENV PATH="/home/${USER}/.fnm/aliases/default/bin:${PATH}"
RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> ~/.bashrc

WORKDIR /home/${USER}/workspace
