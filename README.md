# dev-containers

Podman images for running AI coding agents (Claude Code, Codex, Gemini CLI,
opencode, pi) in rootless containers, plus a few Fedora images for
[distrobox](https://distrobox.it/). Images are rebuilt nightly and published
to `ghcr.io/recmanj/dev-containers/<name>`.

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

- `base`: Debian with the general dev toolchain (Node via fnm, uv, pixi, gh,
  kubectl, helm, OpenTofu, Ansible, …). Also usable on its own.
- `base-agent`: adds Chromium with the
  [Playwright MCP server](https://github.com/microsoft/playwright-mcp) and
  [rtk](https://github.com/rtk-ai/rtk).
- One image per agent, plus `t3`, which runs the
  [t3code](https://github.com/pingdotgg/t3code) server.

## Usage

Each agent directory has a `<name>-container` wrapper. Put it on your `PATH`
and run it from a project directory:

```sh
cd ~/Code/my-project
claude-container
```

The wrapper mounts the current directory at the same path, along with the
agent's config from your home (`~/.claude`, `~/.codex`, …). It runs with
`--userns=keep-id`, `--cap-drop all` and `no-new-privileges`. `.venv` and
`node_modules` are kept in per-project podman volumes. Two files in `~/.config/dev-containers/`
must exist:

- `.env`: environment passed to the container (API keys etc.)
- `github`: an SSH key, mounted read-only

## Agent setup

Agent configs live on the host, so each step below only needs to be done once
per agent.

To give an agent a browser, register the Playwright MCP server with this
command:

```
playwright-mcp --browser chromium --headless --no-sandbox --isolated
```

For Claude Code, run
`claude mcp add playwright -- playwright-mcp --browser chromium --headless --no-sandbox --isolated`
inside the container. For the others, add it to `~/.gemini/settings.json`,
`~/.codex/config.toml` or `~/.config/opencode/opencode.json`.

To enable rtk, run `rtk init -g` inside the container, adding `--gemini`,
`--codex`, `--opencode` or `--agent pi` for the other agents. Check it with
`rtk gain` after a session; set `RTK_DISABLED=1` to skip it for one command.

Notes:

- Chromium's own sandbox can't start under rootless podman, so it runs with
  `--no-sandbox` and the container is the boundary. `--browser chromium` is
  needed because the MCP server defaults to Google Chrome, which isn't
  installed.
- The `claude` and `codex` wrappers add `--security-opt 'unmask=/proc/*'`.
  Without it, Codex's bubblewrap sandbox fails with
  `bwrap: Can't mount proc on /proc`.
- To upgrade the browser, bump `PLAYWRIGHT_MCP_VERSION` in
  `base-agent/Dockerfile`. Chromium comes from the Playwright version bundled
  with it.

## t3code server

The `t3` image runs the t3code server with Claude Code and Codex in one
long-lived container. The desktop and mobile apps connect to it as a remote
environment, so agents, terminals and git all run inside the container.

`t3/t3.container` is a Podman Quadlet that runs it as a systemd user service
on `127.0.0.1:3773`. Inside the container, `HOME` is your host home path, so
project paths match the host. Only `~/Code`, `~/.claude` and `~/.codex` are
mounted from your real home; add `Volume=` lines for other project folders.
The rest of the home, including t3's data, lives in
`~/.config/dev-containers/t3`.

```sh
mkdir -p ~/.config/dev-containers/t3 ~/.config/containers/systemd
cp t3/t3.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start t3
loginctl enable-linger "$(id -un)"   # keep it running after logout
```

To keep existing projects and threads from the desktop app, copy them in
before the first start, with the app closed:

```sh
mkdir -p ~/.config/dev-containers/t3/.t3
cp -a ~/.t3/userdata ~/.config/dev-containers/t3/.t3/
```

Connect the apps with a token from `podman exec t3 t3 pair`:

- **Desktop:** turn off *Settings → Environments → Local environment*, then
  add `http://127.0.0.1:3773`.
- **Phone over Tailscale:** run `tailscale serve --bg 3773` on the host and
  add `https://<machine>.<tailnet>.ts.net`. Ignore the pairing URL `t3 pair`
  prints; that's the container's own address.

To update, `podman pull ghcr.io/recmanj/dev-containers/t3:latest` and
`systemctl --user restart t3`.

## Distrobox images

Fedora images with all tooling baked in, so boxes don't install anything on
first enter. Use them from a `distrobox.ini`:

```ini
[eodh]
image=ghcr.io/recmanj/dev-containers/distrobox/eodh:latest
```

After an image update, recreate the boxes with
`distrobox assemble create --replace`.

## Building locally

```sh
./build.sh t3                    # base → base-agent → claude → t3
./build.sh codex gemini          # shared parents are built once
./build.sh                       # everything
./build.sh --no-cache codex
./build.sh --dry-run t3          # print the podman commands
./build.sh --tag local t3        # tag as :local instead of :latest
```

Builds target `linux/amd64` like CI and stay in local storage. By default they
overwrite your local `:latest` tags, so the wrappers and the Quadlet pick them
up the next time a container is created (`systemctl --user restart t3` for t3).

## Version updates

[Renovate](https://docs.renovatebot.com/) keeps every version pinned and
current. `FROM` images and GitHub Actions are found automatically. Tools
downloaded in a Dockerfile need a comment saying where they're released:

```dockerfile
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.103.3
```

Releases have to be 3 days old before Renovate picks them up. Minor, patch and
digest updates go into one `tooling` PR that merges once CI passes; majors get
their own PR.

PR builds push images tagged `pr-<number>`, and child images build on their
parent's PR tag, so a change to `base` is tested through the whole chain
before merge.

## Checks

The Lint workflow runs [pre-commit](https://pre-commit.com/) with hadolint,
shellcheck, actionlint and zizmor. Run `pre-commit install` to get the same
checks locally. The Scan workflow runs Grype against the published images
every night and reports findings under *Security → Code scanning*.

## License

[MIT](LICENSE)
