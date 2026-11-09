ARG BASE_TAG=latest
FROM ghcr.io/recmanj/dev-containers/base-agent:${BASE_TAG}

# renovate: datasource=npm depName=@google/gemini-cli
ARG GEMINI_CLI_VERSION=0.67.0

RUN npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION}

ENTRYPOINT ["gemini"]
