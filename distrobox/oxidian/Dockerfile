FROM ghcr.io/recmanj/dev-containers/distrobox/base:latest

RUN dnf -y install age ansible opentofu uv \
 && dnf clean all

ARG SOPS_VERSION=3.13.3
RUN curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
      -o /usr/local/bin/sops \
 && chmod +x /usr/local/bin/sops
