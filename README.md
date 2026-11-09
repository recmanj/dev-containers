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

## Extra mounts (`DEV_CONTAINER_EXTRA_VOLUMES`)

The `claude`, `codex`, `gemini` and `opencode` wrappers and `base/dev-container`
read `DEV_CONTAINER_EXTRA_VOLUMES`: one `podman -v` spec per line (blank lines
are ignored), added right after the `node_modules` mount. Unset, the wrappers
behave exactly as before. `agent-squad` uses it to expose a worktree's git
dir; `pi/pi-container` will get the same block in a follow-up.

```sh
DEV_CONTAINER_EXTRA_VOLUMES=$'/data:/data:ro\n/cache:/cache' claude-container
```

## Parallel agents (`agent-squad`)

`squad/agent-squad` runs several wrapped agents side by side, each in its own
git worktree and tmux session. It is one bash script built on `git worktree`
and tmux only, written to be audited.

| per task `NAME` | |
|---|---|
| worktree | `<repo>/.claude/worktrees/squad-NAME` |
| branch | `squad/NAME` |
| tmux session | `squad-<repo>-NAME` (your default tmux server) |
| podman volumes | the wrappers' usual `dev-container-<hash of worktree path>[-venv,-node_modules]` |

**Requirements:** Linux, git 2.36 or later (2.45+ for `GIT_NO_LAZY_FETCH` to
matter), tmux 3.3 or later (multi-argument `new-session` commands; to be
confirmed by the tier-2 tests), and wrappers that carry the
`DEV_CONTAINER_EXTRA_VOLUMES` block.

**Install:** symlink `squad/agent-squad` from your **main checkout** into
`~/.local/bin`. It resolves its own symlink and runs
`<agent>/<agent>-container` (`base/dev-container` for `-a dev`) from that same
checkout; a wrapper on `PATH` is used only if the repo copy is missing, and
`-a /path/to/wrapper` picks one explicitly. Never run `agent-squad` or a
wrapper from inside a squad worktree (its content is agent-written); both are
refused.

```sh
agent-squad new fix-login                 # worktree + branch off the current branch, starts claude
agent-squad new api -a codex -b main      # another agent, explicit base
agent-squad new docs -a dev -- -p 8080    # args after -- go to the wrapper
agent-squad ls                            # name, running/exited N/stopped, branch, commits ahead, path
agent-squad attach fix-login              # detach again with the tmux prefix + d
agent-squad status fix-login              # git status + commits since base
agent-squad diff fix-login [--stat]       # committed work only (what merge takes); warns about uncommitted files
agent-squad stop fix-login                # kill the session, wait for the container to go
agent-squad merge fix-login               # --no-ff merge into the main checkout's branch (agent must be stopped)
agent-squad start fix-login               # relaunch (also after the agent exited)
agent-squad rm fix-login [--force] [--delete-branch] [--keep-volumes]
agent-squad mounts fix-login              # the -v specs passed to the wrapper
```

- `-a AGENT` defaults to `$AGENT_SQUAD_AGENT` or `claude`. `start` does not
  remember the agent used by `new`; pass `-a` again.
- `new` from a non-squad worktree (e.g. `.claude/worktrees/feature`) is
  supported; the base defaults to that worktree's branch. On a detached HEAD
  the base is the HEAD commit, with no upstream.
- `merge` refuses while the task's session or container is running: the agent
  can move its branch at any time, so stop it first. It resolves the branch to
  one commit, checks and merges exactly that commit, and prints its ID. Review
  with `diff` after `stop` so what you review is what gets merged.
- `merge` merges into the branch checked out where you run it. From anywhere
  but the main checkout it requires `--into BRANCH`, naming the branch checked
  out there, so a task branch never lands on `main` by accident. It refuses a
  detached HEAD (jj leaves one in colocated repos) and prints the jj commands
  instead. It lists changed paths that can run code (`.claude/`, `.husky/`,
  `.envrc`, `Makefile`, `package.json`, ...) and asks before merging when
  stdin is a terminal; it warns when the target checkout has uncommitted
  changes (git refuses only if the merge touches them).
- `rm` refuses a running session (use `--force`), a dirty worktree (use
  `--force`) and containers still using the worktree. `--force` waits up to
  `$AGENT_SQUAD_STOP_TIMEOUT` (30) seconds for containers to go and aborts
  without touching anything if they don't. It removes the worktree even if the
  agent locked it, keeps the branch unless `--delete-branch`, and removes the
  three volumes unless `--keep-volumes`.
- `new` adds `/.claude/worktrees/` to `.git/info/exclude` if it is not ignored yet.

**TTY:** the wrappers need a terminal. claude, opencode and dev always pass
`-it`; codex and gemini add `-t` only when stdin and stdout are both terminals.
A tmux pane provides both. The session gets `remain-on-exit`, so an agent's
last output stays visible; `ls` shows `exited N`.

### Git inside a squad container

The worktree's `.git` file points at `<main>/.git/worktrees/squad-NAME`, which
the plain wrappers do not mount. `agent-squad` passes this allowlist (parent
before child):

| path | mode | why |
|---|---|---|
| `<main>/.git` (C) | ro | config, hooks, info, main `HEAD`/`index`, other worktrees' admin dirs |
| `C/objects`, `C/refs`, `C/logs` (+ `C/reftable`, `C/lfs` if present) | rw | commits, branches, reflogs |
| `C/worktrees/squad-NAME` (A) | rw | this worktree's `HEAD`, `index`, `FETCH_HEAD`, `MERGE_HEAD`, `ORIG_HEAD`, `COMMIT_EDITMSG`, `logs/HEAD`, rebase state |
| `A/commondir`, `A/gitdir`, `A/config.worktree`, `<worktree>/.git` | ro | the agent cannot repoint its own git dir |

Per-worktree files live in A, which is why commit, fetch, merge and rebase
work although C is read-only.

- **Works:** `status`, `add`, `commit`, `branch`/`checkout -b`, `tag`,
  `stash`, `merge`, `rebase`, `reset`, `fetch`. Hooks in `C/hooks` still run
  inside the container.
- **Noise:** with git 2.45+ (the images ship 2.47) commit, `checkout -b`,
  `reset --hard` and stash print
  `error: Unable to create '<main>/.git/packed-refs.lock': Read-only file system`.
  Deleting pseudorefs (`ORIG_HEAD`, `MERGE_HEAD`, ...) takes the packed-refs
  lock in the read-only C. The commands still succeed (exit 0); agents will
  see `error:` lines on every commit and can ignore them.
- **Fails:** deleting branches or tags and `fetch --prune` (need
  `packed-refs.lock`); `gc`/auto-maintenance (harmless); any config write
  (`push -u`, `branch --set-upstream-to`, `remote add`, `git config --local`);
  `git worktree *` (Claude Code's own worktree feature included);
  `sparse-checkout` with `extensions.worktreeConfig`; deepening a shallow
  clone; LFS when `.git/lfs` does not exist yet; Claude Code appending to
  `.git/info/exclude`.
- **Shared:** `refs/stash` is a common ref, so all squad agents and the main
  checkout share one stash stack; one agent's `stash pop` can pop another's
  entry.
- **Fresh per worktree:** volume names hash the worktree path, so each task
  gets new, empty `.venv` and `node_modules` volumes (run `uv sync` / `npm ci`
  per task) and its own `~/.claude/projects/<path>` history. With `-a dev`,
  `base/dev-container` mounts the volume as the whole container home, so each
  task also gets a fresh home (shell history, caches, tool logins). `rm`
  removes these volumes unless `--keep-volumes`. `dev -p` ports clash between
  tasks.
- **Empty dirs:** the first run creates empty `.venv/` and `node_modules/`
  mount points in the worktree; they don't show in `git status` and `rm`
  deletes them. A *non-empty* host-side `.venv` in a worktree was written
  outside the container.

### Security model and remaining risks

- **A squad container cannot touch** `C/config`, `C/hooks`, `C/info`,
  `C/config.worktree`, the main checkout's `index`, `HEAD`, `rebase-merge` and
  `sequencer`, other worktrees' admin dirs, its own `commondir`, `gitdir` and
  `.git` pointer, or other tasks' checkouts, and cannot create `C/commondir`.
  Mount points cannot be renamed over or unlinked (EBUSY) and, with
  `--cap-drop all`, not unmounted; hardlinking `C/config` into `C/objects` or
  `A/commondir` into A fails (EXDEV, separate bind mounts).
- **Still writable (by design):** all refs, so an agent can move `main`,
  other tasks' branches and `refs/remotes`, or turn `refs/heads/main` into a
  symref (host `git status` then reports another branch); and the whole object
  store, so it can delete objects, add a pack that shadows objects, or write
  `objects/info/alternates` so host git reads objects from a path it chose.
  `git fsck --full` detects tampering; keep a remote and push often.
- **jj (colocated repos):** jj's automatic import abandons commits no longer
  reachable from a git ref, so an agent that moves `main` can make your next
  `jj` command drop commits (`jj op log` / `jj op restore` recovers them). jj
  runs no git hooks and ignores `core.fsmonitor`.
- **Host-side git:** every git call in `agent-squad` goes through `g()`:
  `-c` overrides that disable hooks, fsmonitor, pagers, editors, signing and
  signature verification (every `gpg.*program` points at `/bin/false`, since a
  repo-config `gpg.program` with `merge.verifySignatures` would otherwise run
  on merge), transports, submodule recursion and auto-gc;
  `GIT_NO_REPLACE_OBJECTS`, `GIT_OPTIONAL_LOCKS=0` (host `status` never
  rewrites the agent's index) and `--no-ext-diff --no-textconv` on diffs.
  Repo-config keys that no flag can disable (`filter.*.clean/smudge/process`,
  `merge.*.driver`, `include.path`, `includeIf.*.path`) make `new`, `status`,
  `diff`, `merge` and `rm` refuse unless `AGENT_SQUAD_TRUST_CONFIG=1`; a
  non-empty `refs/replace/` is reported. `alias.*` is not checked: git ignores
  aliases that shadow builtins. Global and system config are trusted (no
  wrapper mounts them), so filters from your global config (git-lfs) still run
  on attributes an agent writes.
- **Non-squad sessions are unchanged:** a wrapper run in the main checkout can
  write `.git/config` and hooks, which run the next time you use git there
  (agents have been seen writing files into `.git/`). The hardening above only
  covers `agent-squad`'s own git calls, not your shell prompt or IDE.
- **Agent config dirs are unchanged:** e.g. the claude wrapper mounts
  `~/.claude` read-write in every session; an agent can edit
  `~/.claude/settings.json` hooks, which is host code.
- **Merged code is code:** review `.claude/settings.json`, `.husky`, `.envrc`,
  `package.json` scripts and Makefiles before `merge`.
- **tmux** uses a user-only unix socket; any process running as you can attach.

### Tests

```sh
bash squad/tests/run.sh
```

Tier 1 needs bash and git (bwrap, when it works, simulates the container's
mounts); tier 2 needs tmux. The tests put a fake `podman` first on `PATH` and
abort if the real one would be reached. Once on the host, also run the manual
smoke test: `agent-squad new smoke`, then inside check that `git commit`
works, `touch <main>/.git/config` fails and `.git/objects` is writable; check
that `stop` returns without a warning and `podman ps -a --filter
volume=dev-container-<hash>-venv` is empty; `rm smoke`; then
`agent-squad new smoke2 -a dev`.
