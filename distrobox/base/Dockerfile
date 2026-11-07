# Shared tooling for all boxes.
FROM registry.fedoraproject.org/fedora-toolbox:45@sha256:1df1bd9e60e286dcca793a62092cdbbcaa0cb3058b39d1faf9bca01124eb0b2f

RUN dnf -y install git jq make vim yq \
 && dnf clean all
