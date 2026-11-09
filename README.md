# dev-containers

Podman container images for AI coding agents, published to
`ghcr.io/recmanj/dev-containers/<name>`.

Image hierarchy:

```
base ── base-agent ── claude ── t3
                   ── gemini
                   ── codex
                   ── opencode
                   ── pi
```

`base` holds the common dev toolchain (Node via fnm, uv, pixi, k8s tools, …)
and is also usable standalone for non-AI dev work. `base-agent` builds on
`base` and adds Playwright Chromium, the [Playwright MCP
server](https://github.com/microsoft/playwright-mcp) (`playwright-mcp`,
pre-installed globally), and the [rtk](https://github.com/rtk-ai/rtk)
token-saving CLI proxy — all inherited by every agent image. Each agent directory
ships a `<name>-container` wrapper script that runs the image with rootless
podman (`--userns=keep-id`, `--security-opt no-new-privileges`, `--cap-drop
all`).

## Distrobox images

Separate Fedora-based images for [distrobox](https://distrobox.it/), with all
tooling baked in so boxes don't install anything on first enter. Published to
`ghcr.io/recmanj/dev-containers/distrobox/<name>`.

```
fedora-toolbox:45 ── distrobox/base ── oxidian
                                    ── ecmwf
                                    ── eodh
```

`distrobox/base` holds the tools shared by every box (git, jq, make, vim, yq).
The Fedora image is pinned by version and digest; Renovate bumps it (see
[Version updates](#version-updates)), and the nightly build picks up dnf
package updates.

Use them from a `distrobox.ini`:

```ini
[eodh]
image=ghcr.io/recmanj/dev-containers/distrobox/eodh:latest
```

The repo is private, so log in once with `podman login ghcr.io` (a token with
`read:packages`). After an image update, recreate the boxes with
`distrobox assemble create --replace`.

## Version updates

[Renovate](https://docs.renovatebot.com/) keeps every pinned version current
(`renovate.json`):

- `FROM` images and GitHub Actions are picked up automatically.
- Tools downloaded in a Dockerfile are pinned as an `ARG` with a comment that
  tells Renovate where they are released:

  ```dockerfile
  # renovate: datasource=github-releases depName=cli/cli
  ARG GH_VERSION=2.103.3
  ```

  Add the same comment when pinning a new tool.

Releases must be at least 3 days old before Renovate proposes them. Minor,
patch and digest updates are grouped into one `tooling` PR and merged once CI
passes; major updates get their own PR for review. Pending updates are listed
on the Dependency Dashboard issue.

PR builds push images as `pr-<number>`, and child images build `FROM` their
parent's `pr-<number>` tag (the `BASE_TAG` build arg), so a change to `base`
is tested through the whole image chain before merge.

## t3code server

The `t3` image runs the [t3code](https://github.com/pingdotgg/t3code) server
with Claude Code and Codex in one long-lived container. The desktop and mobile
apps connect to it as a remote environment, so agents, terminals and git all
run inside the container.

`t3/t3.container` is a Podman Quadlet that runs it as a systemd user service.
It publishes the server on `127.0.0.1:3773` only. Inside the container `HOME`
is your host home path, so `~/Code` and project paths are the same as on the
host. Only your project folders (`~/Code`, `~/Oxidian/Code`), `~/.claude` and
`~/.codex` are mounted from your real home
(add `Volume=` lines for other project folders); the rest of the container's
home, including t3's data in `.t3`, lives in `~/.config/dev-containers/t3`,
apart from the desktop app's `~/.t3`. To keep your existing projects and
threads, copy them in before the first start, with the desktop app closed:
`mkdir -p ~/.config/dev-containers/t3/.t3 && cp -a ~/.t3/userdata ~/.config/dev-containers/t3/.t3/`.

```sh
mkdir -p ~/.config/dev-containers/t3 ~/.config/containers/systemd
cp t3/t3.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start t3
loginctl enable-linger "$(id -un)"   # keep it running after logout
```

Connect the apps:

- **Desktop:** turn off **Settings → Environments → Local environment**
  so nothing runs on the host, then add `http://127.0.0.1:3773` as an
  environment with a token from `podman exec t3 t3 pair`.
- **Phone over Tailscale:** expose the port on the host with
  `tailscale serve --bg 3773`, then add `https://<machine>.<tailnet>.ts.net`
  in the app with a fresh token from `podman exec t3 t3 pair`. Ignore the
  pairing URL it prints; that is the container's own address.

Update with `podman pull ghcr.io/recmanj/dev-containers/t3:latest` and
`systemctl --user restart t3`.

## Codex sandbox

The `claude` and `codex` images ship bubblewrap so Codex can run its own
command sandbox. Their wrapper scripts add `--security-opt 'unmask=/proc/*'`:
podman normally masks paths under `/proc` (`/proc/kcore`, `/proc/sys`, ...),
which makes the kernel refuse a fresh `proc` mount in a nested PID namespace
(`bwrap: Can't mount proc on /proc: Operation not permitted`). Unmasking only
`/proc` keeps the other hardening in place.

## Browser use

Chromium runs with `--no-sandbox` inside the container: its own sandbox cannot
initialize under rootless podman, and the hardened container is the sandbox
boundary instead. `--isolated` keeps the browser profile in memory, matching
the ephemeral `--rm` containers. `--browser chromium` is required: without it
the MCP server defaults to the Google Chrome channel, which is not installed
in the image (and cannot be installed at runtime by the non-root user).

Agent configs are mounted from the host, so registering the MCP server is a
one-time action per agent:

**Claude Code** (inside the container; persists via the mounted `~/.claude.json`):

```sh
claude mcp add playwright -- playwright-mcp --browser chromium --headless --no-sandbox --isolated
```

**Gemini CLI** (`~/.gemini/settings.json`):

```json
{
  "mcpServers": {
    "playwright": {
      "command": "playwright-mcp",
      "args": ["--browser", "chromium", "--headless", "--no-sandbox", "--isolated"]
    }
  }
}
```

**Codex** (`~/.codex/config.toml`):

```toml
[mcp_servers.playwright]
command = "playwright-mcp"
args = ["--browser", "chromium", "--headless", "--no-sandbox", "--isolated"]
```

**opencode** (`~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["playwright-mcp", "--browser", "chromium", "--headless", "--no-sandbox", "--isolated"],
      "enabled": true
    }
  }
}
```

Upgrading the browser stack: bump `PLAYWRIGHT_MCP_VERSION` in
`base-agent/Dockerfile` only — Chromium is downloaded via the playwright
version bundled inside `@playwright/mcp`, so the two cannot drift.

## rtk (token-saving proxy)

The `rtk` binary is pre-installed in the `base-agent` image (pinned via
`RTK_VERSION` in `base-agent/Dockerfile`).

Agent configs are mounted from the host, so registering rtk's per-agent hook
is a one-time action per agent (writes land in the host-mounted config dir and
persist across containers):

**Claude Code** (inside the container; persists via the mounted `~/.claude`):

```sh
rtk init -g
```

**Gemini CLI** (persists via the mounted `~/.gemini`):

```sh
rtk init -g --gemini
```

**Codex** (persists via the mounted `~/.codex`):

```sh
rtk init -g --codex
```

**opencode** (persists via the mounted `~/.config/opencode`):

```sh
rtk init -g --opencode
```

**pi** (persists via the mounted `~/.pi/agent`):

```sh
rtk init -g --agent pi
```

Verify the hook is active with `rtk init --show` (where supported) or run
`rtk gain` after a session to see token savings. Disable rtk for a single
command with `RTK_DISABLED=1 <cmd>`.
