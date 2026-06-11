FROM ghcr.io/recmanj/dev-containers/base-browser:latest

ARG GEMINI_CLI_VERSION=latest

RUN npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION}

ENTRYPOINT ["gemini"]
