FROM ghcr.io/recmanj/dev-containers/distrobox/base:latest

RUN dnf -y install awscli2 helm k9s kubectl kustomize \
 && dnf -y config-manager addrepo --overwrite \
      --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
 && dnf -y install terraform \
 && dnf clean all
