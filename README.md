# dev-containers

Rootless Podman images for running AI coding agents (Claude Code, Codex,
Gemini CLI, opencode, pi) in a sandbox, plus a few Fedora images for
[distrobox](https://distrobox.it/). The images are rebuilt nightly and
published to `ghcr.io/recmanj/dev-containers/<name>`.

## Quick start

Create the two files the wrappers mount:

```sh
mkdir -p ~/.config/dev-containers
touch ~/.config/dev-containers/.env                 # API keys etc.
ssh-keygen -t ed25519 -f ~/.config/dev-containers/github   # then add github.pub to GitHub
```

Put a wrapper on your `PATH` and run it from a project directory:

```sh
ln -s "$PWD/claude/claude-container" ~/.local/bin/
cd ~/Code/my-project
claude-container
```

The container sees the current directory at the same path and your agent
config (`~/.claude`, `~/.codex`, …), and nothing else from your home. Wrappers
exist for `claude`, `codex`, `gemini`, `opencode` and `pi`, plus
`base/dev-container` for a plain dev shell.

## Images

```
base ── base-agent ── claude ── t3
                   ├─ codex
                   ├─ gemini
                   ├─ opencode
                   └─ pi

fedora-toolbox ── distrobox/base ── oxidian
                                 ├─ ecmwf
                                 └─ eodh
```

- `base`: Debian with a general dev toolchain (Node, uv, pixi, gh, kubectl,
  helm, OpenTofu, Ansible, …).
- `base-agent`: adds Chromium with the Playwright MCP server, and rtk.
- `t3`: the [t3code](https://github.com/pingdotgg/t3code) server with Claude
  Code and Codex, run as a systemd service.

## Docs

- [Agents](docs/agents.md): what the wrappers mount, browser and rtk setup
- [t3code server](docs/t3.md): running t3 as a service and connecting the apps
- [Distrobox images](docs/distrobox.md)
- [Development](docs/development.md): building locally, version updates, CI

## License

[MIT](LICENSE)
