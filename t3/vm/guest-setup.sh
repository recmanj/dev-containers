#!/bin/bash
set -euo pipefail

# Arguments are supplied by cloud-init, without shell interpolation.
guest_user=$1
guest_uid=$2
guest_home=$3
shift 3

as_user() {
    runuser -u "$guest_user" -- env HOME="$guest_home" \
        XDG_RUNTIME_DIR="/run/user/$guest_uid" "$@"
}

# cloud-init may mount shares before useradd creates the home. Repair only
# the home itself: recursive ownership changes would touch the host shares.
chown "$guest_user:" "$guest_home"
as_user cp -rn /etc/skel/. "$guest_home/"
as_user install -d "$guest_home/.local/bin"

# Make CLI tools available in SSH login shells, including during first boot.
cat > /etc/profile.d/t3-path.sh <<'EOF'
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
chmod 0644 /etc/profile.d/t3-path.sh

# Install Engine, Buildx and Compose from Docker's signed Debian repository.
# This script runs inside the VM only.
install -m 0755 -d /etc/apt/keyrings
curl --retry 5 --retry-delay 2 -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod 0644 /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker.service

systemctl enable --now qemu-guest-agent
loginctl enable-linger "$guest_user"
systemctl start "user@${guest_uid}.service"

# Keep tools, images, credentials and T3 state on the VM disk.
as_user install -d "$guest_home/.config/systemd/user"
as_user install -m 600 \
    /opt/t3/t3.service "$guest_home/.config/systemd/user/t3.service"
if as_user systemctl --user is-active --quiet t3.service; then
    as_user systemctl --user stop t3.service
fi
as_user bash /opt/t3/install-tools.sh "$@"
# cloud-init adds the user to docker before any user service is started.
as_user docker info
as_user docker compose version
as_user docker buildx version
as_user systemctl --user daemon-reload
as_user systemctl --user enable --now t3.service
