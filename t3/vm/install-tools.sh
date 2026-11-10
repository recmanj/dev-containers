#!/bin/bash
set -euo pipefail

# Run as the development user. Versions are extracted from the repository's
# existing Dockerfiles by prepare.py and supplied as positional arguments.
t3_version=$1
claude_version=$2
codex_version=$3
export PATH="$HOME/.local/bin:$PATH"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/t3"
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT
curl --retry 5 --retry-delay 2 -fsSL "https://github.com/pingdotgg/t3code/releases/download/v${t3_version}/t3-${t3_version}-linux-x64.tar.gz" \
    -o "$download_dir/t3.tar.gz"
tar -xzf "$download_dir/t3.tar.gz" --strip-components=1 -C "$HOME/.local/share/t3"
ln -sfn "$HOME/.local/share/t3/t3" "$HOME/.local/bin/t3"

curl --retry 5 --retry-delay 2 -fsSL https://claude.ai/install.sh -o "$download_dir/claude-install.sh"
bash "$download_dir/claude-install.sh" "$claude_version"
npm install --global --prefix "$HOME/.local" "@openai/codex@$codex_version"

t3 --version
claude --version
codex --version

bash "$(dirname -- "${BASH_SOURCE[0]}")/install-dev-tools.sh"
