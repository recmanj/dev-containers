ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base-agent:${BASE_TAG}

# Install from npm rather than pi.dev/install.sh, which always installs the
# latest release. The global npm prefix lives under fnm (already on PATH),
# away from ~/.pi/agent, which the wrapper bind-mounts from the host.
# --ignore-scripts matches what the official installer does.
# renovate: datasource=npm depName=@earendil-works/pi-coding-agent
ARG PI_VERSION=1.5.0
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
    && pi --version \
    && ls -l "$(command -v pi)"

ENTRYPOINT ["pi"]
