FROM ghcr.io/recmanj/dev-containers/distrobox/base:latest

# HashiCorp has no Fedora 45 repo yet; pin it to 44 (terraform is a static binary).
RUN dnf -y install awscli2 helm k9s kubectl kustomize \
 && dnf -y config-manager addrepo --overwrite \
      --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
 && sed -i 's/\$releasever/44/g' /etc/yum.repos.d/hashicorp.repo \
 && dnf -y install terraform \
 && dnf clean all
