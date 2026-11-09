# Agents

Each agent directory has a `<name>-container` wrapper that runs the image with
rootless Podman:

- `--userns=keep-id`, so files the agent creates belong to you
- `--cap-drop all` and `no-new-privileges`
- the current directory mounted at the same path
- the agent's own config from your home (`~/.claude`, `~/.codex`, …)
- `.venv` and `node_modules` kept in per-project Podman volumes
- `~/.config/dev-containers/.env` passed in as environment
- `~/.config/dev-containers/github` mounted read-only as an SSH key

Containers are removed when the agent exits (`--rm`).

`base/dev-container` starts a plain shell in the `base` image instead. It also
mounts `~/.config/dev-containers/kubeconfig`, keeps the home in a
per-project volume, and takes `-p` to publish ports
(`dev-container -p 8000:8000`).

## Browser

`base-agent` ships Chromium and the
[Playwright MCP server](https://github.com/microsoft/playwright-mcp). Agent
configs live on the host, so registering it is a one-time step per agent. The
server command is:

```
playwright-mcp --browser chromium --headless --no-sandbox --isolated
```

For Claude Code, run this inside the container:

```sh
claude mcp add playwright -- playwright-mcp --browser chromium --headless --no-sandbox --isolated
```

For the others, add the same command to `~/.gemini/settings.json`,
`~/.codex/config.toml` or `~/.config/opencode/opencode.json`.

- `--no-sandbox`: Chromium's own sandbox can't start under rootless Podman, so
  the container is the boundary.
- `--browser chromium`: the MCP server defaults to Google Chrome, which isn't
  installed.
- `--isolated`: keeps the browser profile in memory.

To upgrade the browser, bump `PLAYWRIGHT_MCP_VERSION` in
`base-agent/Dockerfile`. Chromium comes from the Playwright version bundled
with it, so the two can't drift.

## rtk

[rtk](https://github.com/rtk-ai/rtk) is a CLI proxy that trims command output
to save tokens. To enable it, run this once inside the container:

| Agent | Command |
|---|---|
| Claude Code | `rtk init -g` |
| Gemini CLI | `rtk init -g --gemini` |
| Codex | `rtk init -g --codex` |
| opencode | `rtk init -g --opencode` |
| pi | `rtk init -g --agent pi` |

Run `rtk gain` after a session to see what it saved. Set `RTK_DISABLED=1` to
skip it for one command.

## Codex sandbox

The `claude` and `codex` images ship bubblewrap so Codex can sandbox the
commands it runs. Their wrappers add `--security-opt 'unmask=/proc/*'`:
Podman masks paths under `/proc` by default, which makes the kernel refuse
the fresh `proc` mount bubblewrap needs (`bwrap: Can't mount proc on /proc`).
The rest of the hardening stays in place.
