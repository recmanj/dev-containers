FROM ghcr.io/recmanj/dev-containers/distrobox/base:latest

RUN dnf -y config-manager addrepo --overwrite \
      --from-repofile=https://yum.releases.teleport.dev/rhel/9/Teleport/x86_64/stable/v18/teleport.repo \
 && dnf -y install teleport \
 && dnf clean all
