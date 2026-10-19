#!/usr/bin/env bash
# Executed ONLY by agent-vm inside a fresh Debian VM.
set -euo pipefail
[[ ${DEV_CONTAINERS_PROVISION:-} == 1 && $EUID == 0 ]] || { echo 'Run through agent-vm build, not on the host.' >&2; exit 1; }
systemd-detect-virt --vm --quiet || { echo 'A virtual machine is required.' >&2; exit 1; }
# shellcheck source=/dev/null
. /etc/os-release
[[ $ID == debian && $VERSION_ID == 13 ]] || { echo 'Debian 13 required' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
export CI=1
echo '==> Waiting for boot and DNS'
timeout 300 systemctl is-system-running --wait >/dev/null 2>&1 || true
for ((i = 1; i <= 60; i++)); do
  getent hosts deb.debian.org >/dev/null && break
  (( i < 60 )) || { echo 'DNS lookup of deb.debian.org failed for 120s' >&2; exit 1; }
  sleep 2
done
# Wait for unattended apt runs instead of failing on the dpkg lock.
printf 'DPkg::Lock::Timeout "300";\n' > /etc/apt/apt.conf.d/90dev-containers
printf 'LANG=C.UTF-8\n' > /etc/default/locale
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg git build-essential cmake \
  libboost-all-dev openssh-server netcat-openbsd sudo jq less ripgrep unzip bash-completion \
  python-is-python3 python3-dev python3-pip python3-venv python3-yaml bubblewrap pre-commit gh just yq
# Auxiliary tools used by the existing base image.
ARCH=$(dpkg --print-architecture)
case $ARCH in amd64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
TOOLS=$(mktemp -d)
KUBECTL_VERSION=$(curl -fsSL --retry 3 https://dl.k8s.io/release/stable.txt)
HELM_VERSION=4.3.0
KUSTOMIZE_VERSION=5.8.1
curl -fsSL --retry 3 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o "$TOOLS/kubectl"
install -m 0755 "$TOOLS/kubectl" /usr/local/bin/kubectl
curl -fsSL --retry 3 "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" -o "$TOOLS/helm.tar.gz"
tar -xzf "$TOOLS/helm.tar.gz" -C "$TOOLS"
install -m 0755 "$TOOLS/linux-${ARCH}/helm" /usr/local/bin/helm
curl -fsSL --retry 3 "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" -o "$TOOLS/kustomize.tar.gz"
tar -xzf "$TOOLS/kustomize.tar.gz" -C "$TOOLS" kustomize
install -m 0755 "$TOOLS/kustomize" /usr/local/bin/kustomize
curl -fsSL --retry 3 https://get.opentofu.org/install-opentofu.sh -o "$TOOLS/tofu.sh"
bash "$TOOLS/tofu.sh" --install-method deb
rm -rf "$TOOLS"
# Official Docker packages, including the Compose and Buildx plugins.
install -d -m 0755 /etc/apt/keyrings
curl -fsSL --retry 3 https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable\n' \
  "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
useradd --uid 1000 --create-home --shell /bin/bash dev
usermod -aG docker dev
# Docker access already permits guest root, so sudo adds no authority. Never provide host authority.
t=$(mktemp)
cat > "$t" <<'EOF'
# docker group already grants guest root; the VM is the boundary.
dev ALL=(ALL:ALL) NOPASSWD: ALL
EOF
visudo -cf "$t"
install -m 0440 -o root -g root "$t" /etc/sudoers.d/dev
rm -f "$t"
visudo -c
# Linger gives dev a user manager and /run/user/1000 without a login session.
install -d -m 0755 /var/lib/systemd/linger
touch /var/lib/systemd/linger/dev
# install -d only chowns the last component; create .local explicitly so dev owns it.
install -d -o dev -g dev /home/dev/.local /home/dev/.local/bin /home/dev/workspace
cat > /etc/profile.d/dev-tools.sh <<'EOF'
export FNM_DIR="$HOME/.fnm"
export PATH="$HOME/.local/bin:$HOME/.fnm:$HOME/.fnm/aliases/default/bin:$HOME/.opencode/bin:$PATH"
export PLAYWRIGHT_BROWSERS_PATH="$HOME/.cache/ms-playwright"
export LANG="${LANG:-C.UTF-8}"
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then XDG_RUNTIME_DIR="/run/user/$(id -u)"; export XDG_RUNTIME_DIR; fi
# Opt-in host env from `agent-vm seed`: literal KEY=VALUE lines like podman --env-file (no quotes/expansion).
if [ -r "$HOME/.config/dev-containers/.env" ]; then
  while IFS= read -r _dc_line || [ -n "$_dc_line" ]; do
    case $_dc_line in ''|'#'*) continue ;; *=*) ;; *) continue ;; esac
    _dc_key=${_dc_line%%=*}
    case $_dc_key in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac
    export "$_dc_line"
  done < "$HOME/.config/dev-containers/.env"
  unset _dc_line _dc_key
fi
EOF
cat > /tmp/provision-dev.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export CI=1
source /etc/profile.d/dev-tools.sh
# Keep these versions aligned with base/ and base-agent/ Dockerfiles.
UV_VERSION=0.12.15
NODE_VERSION=26
PIXI_VERSION=0.81.0
PLAYWRIGHT_MCP_VERSION=0.0.81
RTK_VERSION=v0.49.0
curl -fsSL --retry 3 "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
curl -fsSL --retry 3 https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell
fnm install "$NODE_VERSION"
fnm default "$NODE_VERSION"
uv tool install ansible-core --with ansible
PIXI_ARCHIVE=$(mktemp)
curl -fsSL --retry 3 "https://github.com/prefix-dev/pixi/releases/download/v${PIXI_VERSION}/pixi-$(uname -m)-unknown-linux-musl.tar.gz" -o "$PIXI_ARCHIVE"
tar -xzf "$PIXI_ARCHIVE" -C "$HOME/.local/bin" pixi
rm -f "$PIXI_ARCHIVE"
npm install -g @playwright/mcp@"$PLAYWRIGHT_MCP_VERSION" @openai/codex@latest @google/gemini-cli@latest
(cd "$(npm root -g)/@playwright/mcp" && npx playwright install chromium)
curl -fsSL --retry 3 https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | env RTK_VERSION="$RTK_VERSION" sh
curl -fsSL --retry 3 https://claude.ai/install.sh | bash
curl -fsSL --retry 3 https://opencode.ai/install | bash
curl -fsSL --retry 3 https://pi.dev/install.sh | sh
for cli in uv node pixi claude codex gemini opencode pi rtk playwright-mcp; do
  command -v "$cli"
done
cat >> "$HOME/.bashrc" <<'RC'
source /etc/profile.d/dev-tools.sh
eval "$(fnm env --use-on-cd --shell bash)"
RC
EOF
chmod 0755 /tmp/provision-dev.sh
su --login dev -c 'bash /tmp/provision-dev.sh'
# Install browser OS libraries as root, using the exact bundled Playwright.
export PATH="/home/dev/.fnm/aliases/default/bin:$PATH"
(cd /home/dev/.fnm/aliases/default/lib/node_modules/@playwright/mcp && npx playwright install-deps chromium)
# SSH is key-only. Host keys are generated separately for each instantiated VM.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-dev-containers.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers dev
EOF
cat > /etc/systemd/system/dev-ssh-host-keys.service <<'EOF'
[Unit]
Description=Generate unique SSH host keys on first boot
Before=ssh.service
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
# GitHub key from `agent-vm seed` is used only if present; host keys are pinned.
mkdir -p /etc/ssh/ssh_config.d
cat > /etc/ssh/ssh_config.d/50-dev-containers-github.conf <<'EOF'
# Active only after `agent-vm seed` installs ~/.ssh/github.
Match host github.com exec "test -r %d/.ssh/github"
    IdentityFile %d/.ssh/github
    IdentitiesOnly yes
EOF
curl -fsSL --retry 3 https://api.github.com/meta | jq -r '.ssh_keys[] | "github.com " + .' > /etc/ssh/ssh_known_hosts
[[ -s /etc/ssh/ssh_known_hosts ]]
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/host-keys.conf <<'EOF'
[Unit]
Requires=dev-ssh-host-keys.service
After=dev-ssh-host-keys.service
EOF
systemctl daemon-reload
systemctl enable docker ssh dev-ssh-host-keys.service
printf 'Debian 13 agent VM; provisioned %s\n' "$(date -u +%FT%TZ)" > /etc/dev-containers-image
# Record resolved packages for debugging: latest installers are not reproducible.
dpkg-query -W > /etc/dev-containers-packages.txt
su --login dev -c 'npm list -g --depth=0' > /etc/dev-containers-npm.txt
# Fresh builder only: never run this sanitization against a project VM.
rm -f /tmp/provision-dev.sh /root/provision.sh /root/.bash_history /home/dev/.bash_history
# Drop download caches (keep ms-playwright: it holds the installed browser).
rm -rf /home/dev/.npm/_cacache /home/dev/.npm/_npx /home/dev/.cache/uv /home/dev/.cache/pip /root/.cache /root/.npm
journalctl --rotate || true
journalctl --vacuum-time=1s || true
rm -f /etc/ssh/ssh_host_* /var/lib/systemd/random-seed
rm -f /var/lib/dbus/machine-id
truncate -s 0 /etc/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id
# /etc/hostname is left alone: Incus templates rewrite it per instance.
apt-get clean
rm -rf /var/lib/apt/lists/*
# No credentials, host directories or SSH public keys have been supplied to this builder.
