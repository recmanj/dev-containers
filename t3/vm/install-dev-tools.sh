#!/bin/bash
set -euo pipefail

# Run inside the VM as the development user, without sudo.
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as the development user, without sudo.' >&2
    exit 1
fi
if ! systemd-detect-virt --vm --quiet; then
    echo 'Run this inside the T3 VM, not on the host.' >&2
    exit 1
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HOME"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
mkdir -p "$HOME/.local/bin"
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT

curl --retry 5 --retry-delay 2 -fsSL https://astral.sh/uv/install.sh -o "$download_dir/uv.sh"
UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$download_dir/uv.sh"
curl --retry 5 --retry-delay 2 -fsSL https://mise.run -o "$download_dir/mise.sh"
# renovate: datasource=github-releases depName=jdx/mise
mise_version=v2026.11.4
MISE_VERSION=$mise_version MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$download_dir/mise.sh"
mise use --global node@24

# Other tools are pinned in mise.toml, next to this script. Mise downloads the
# vendors' release files and checks their checksums and, where published,
# signatures. These tools need no cloud credentials: they render, lint and
# validate, and kind runs local clusters on the VM's Docker.
mkdir -p "$HOME/.config/mise/conf.d"
cp "$script_dir/mise.toml" "$HOME/.config/mise/conf.d/t3-vm.toml"
mise install
mise reshim

# Python CLIs, each in its own environment.
uv tool install --upgrade ansible-core --with ansible
uv tool install --upgrade ansible-lint
uv tool install --upgrade pre-commit

# Shims select project versions even without interactive shell activation.
# shellcheck disable=SC2016 # Expand HOME and PATH when the shell reads the profile.
path_line='export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"'
for profile in "$HOME/.profile" "$HOME/.bashrc"; do
    if ! grep -Fqx "$path_line" "$profile" 2>/dev/null; then
        printf '\n%s\n' "$path_line" >> "$profile"
    fi
done
mkdir -p "$HOME/.config/systemd/user/t3.service.d"
cat > "$HOME/.config/systemd/user/t3.service.d/dev-tools.conf" <<'EOF'
[Service]
Environment=PATH=%h/.local/bin:%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin
EOF

bash "$script_dir/install-monitoring.sh"

uv --version
mise --version
node --version
npm --version
mise ls --global --current
ansible --version | sed -n 1p
ansible-lint --version | sed -n 1p
pre-commit --version
echo 'Tools installed. Reconnect SSH; reload and restart t3.service when ready.'
