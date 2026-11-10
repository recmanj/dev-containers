#!/bin/bash
set -euo pipefail

# Run inside the VM as the development user, without sudo.
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as the development user, without sudo.' >&2
    exit 1
fi
cd "$HOME"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
mkdir -p "$HOME/.local/bin"
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT

curl --retry 5 --retry-delay 2 -fsSL https://astral.sh/uv/install.sh -o "$download_dir/uv.sh"
UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh "$download_dir/uv.sh"
curl --retry 5 --retry-delay 2 -fsSL https://mise.run -o "$download_dir/mise.sh"
MISE_VERSION=v2026.10.4 MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$download_dir/mise.sh"
mise use --global node@24
mise reshim

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

uv --version
mise --version
node --version
npm --version
echo 'Tools installed. Reconnect SSH; reload and restart t3.service when ready.'
