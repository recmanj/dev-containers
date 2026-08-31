# dev-containers

Podman container images for AI coding agents, published to
`ghcr.io/recmanj/dev-containers/<name>`.

Image hierarchy:

```
base ── base-agent ── claude
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
`RTK_VERSION` in `base-agent/Dockerfile`.

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
