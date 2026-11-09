ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base-agent:${BASE_TAG}

# Install from npm: pi.dev/install.sh can't pin a version. --ignore-scripts
# matches what the official installer does.
# renovate: datasource=npm depName=@earendil-works/pi-coding-agent
ARG PI_VERSION=1.5.0
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
    && pi --version

ENTRYPOINT ["pi"]
