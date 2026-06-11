# dev-containers

Podman container images for AI coding agents, published to
`ghcr.io/recmanj/dev-containers/<name>`.

Image hierarchy:

```
base ── base-browser ── claude
                     ── gemini
                     ── codex
                     ── opencode
                     ── pi
```

`base` holds the common dev toolchain (Node via fnm, uv, pixi, k8s tools, …).
`base-browser` adds Playwright Chromium and the [Playwright MCP
server](https://github.com/microsoft/playwright-mcp) (`playwright-mcp`,
pre-installed globally), which all agent images inherit. Each agent directory
ships a `<name>-container` wrapper script that runs the image with rootless
podman (`--userns=keep-id`, `--security-opt no-new-privileges`, `--cap-drop
all`).

## Browser use

Chromium runs with `--no-sandbox` inside the container: its own sandbox cannot
initialize under rootless podman, and the hardened container is the sandbox
boundary instead. `--isolated` keeps the browser profile in memory, matching
the ephemeral `--rm` containers.

Agent configs are mounted from the host, so registering the MCP server is a
one-time action per agent:

**Claude Code** (inside the container; persists via the mounted `~/.claude.json`):

```sh
claude mcp add playwright -- playwright-mcp --headless --no-sandbox --isolated
```

**Gemini CLI** (`~/.gemini/settings.json`):

```json
{
  "mcpServers": {
    "playwright": {
      "command": "playwright-mcp",
      "args": ["--headless", "--no-sandbox", "--isolated"]
    }
  }
}
```

**Codex** (`~/.codex/config.toml`):

```toml
[mcp_servers.playwright]
command = "playwright-mcp"
args = ["--headless", "--no-sandbox", "--isolated"]
```

**opencode** (`~/.config/opencode/opencode.json`):

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["playwright-mcp", "--headless", "--no-sandbox", "--isolated"],
      "enabled": true
    }
  }
}
```

Upgrading the browser stack: bump `PLAYWRIGHT_MCP_VERSION` in
`base-browser/Dockerfile` only — Chromium is downloaded via the playwright
version bundled inside `@playwright/mcp`, so the two cannot drift. Dependabot
does not track this ARG.
