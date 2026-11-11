#!/bin/bash
set -euo pipefail

# Beszel hub (dashboard on port 8090) and agent (on a Unix socket) as user services.
# Run inside the VM as the development user, without sudo.
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as the development user, without sudo.' >&2
    exit 1
fi
if ! systemd-detect-virt --vm --quiet; then
    echo 'Run this inside the T3 VM, not on the host.' >&2
    exit 1
fi

# renovate: datasource=github-releases depName=henrygd/beszel extractVersion=^v(?<version>.*)$
beszel_version=0.21.1
base_url="https://github.com/henrygd/beszel/releases/download/v${beszel_version}"
install_dir="$HOME/.local/share/beszel"
unit_dir="$HOME/.config/systemd/user"
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT

cd "$download_dir"
for file in beszel_linux_amd64.tar.gz beszel-agent_linux_amd64.tar.gz "beszel_${beszel_version}_checksums.txt"; do
    curl --retry 5 --retry-delay 2 -fsSLO "$base_url/$file"
done
grep -E '  beszel(-agent)?_linux_amd64\.tar\.gz$' "beszel_${beszel_version}_checksums.txt" > checksums
if [ "$(wc -l < checksums)" -ne 2 ]; then
    echo 'Beszel checksums are missing from the release.' >&2
    exit 1
fi
sha256sum --check --strict checksums
mkdir -p "$install_dir/hub" "$install_dir/agent" "$unit_dir"
tar -xzf beszel_linux_amd64.tar.gz beszel
tar -xzf beszel-agent_linux_amd64.tar.gz beszel-agent
install -m 0755 beszel beszel-agent "$install_dir/"

cat > "$unit_dir/beszel-hub.service" <<'EOF'
[Unit]
Description=Beszel monitoring hub

[Service]
ExecStart=%h/.local/share/beszel/beszel serve --dir %h/.local/share/beszel/hub --http 0.0.0.0:8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Only the hub's key may connect.
cat > "$unit_dir/beszel-agent.service" <<'EOF'
[Unit]
Description=Beszel monitoring agent

[Service]
ExecStart=%h/.local/share/beszel/beszel-agent
Environment=LISTEN=%t/beszel/agent.sock
Environment=KEY_FILE=%h/.local/share/beszel/hub.pub
Environment=DATA_DIR=%h/.local/share/beszel/agent
Environment=DOCKER_IMAGE_CHECK=false
Environment=PACKAGE_UPDATES_INTERVAL=0
Environment=SKIP_SYSTEMD=true
RuntimeDirectory=beszel
RuntimeDirectoryMode=0700
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable beszel-hub.service beszel-agent.service
systemctl --user restart beszel-hub.service
# The hub creates its key pair on first start.
for _ in $(seq 30); do
    [ -s "$install_dir/hub/id_ed25519" ] && break
    sleep 1
done
ssh-keygen -y -f "$install_dir/hub/id_ed25519" > "$install_dir/hub.pub"
systemctl --user restart beszel-agent.service

"$install_dir/beszel" --version
"$install_dir/beszel-agent" --version
echo "Dashboard on port 8090. System host: ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/beszel/agent.sock"
