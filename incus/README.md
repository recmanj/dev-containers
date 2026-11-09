# Incus project VMs

Run agents **directly in a Debian 13 VM**, with Docker Engine and Compose for
project services. Existing Podman images and wrappers are unaffected.

This is an initial implementation: CLI contracts are tested with a mocked Incus
client. Image provisioning and VM boot still require the workstation smoke test
below before relying on this workflow.

## Host prerequisites

- Linux with working KVM (`/dev/kvm`), virtualization enabled in firmware.
- Incus 6.0 LTS or newer (`incus snapshot create/list/restore`, `exec --mode`).
- Incus initialized with a **default profile containing a root disk and NIC**,
  an image remote named `images`, and internet access for guest provisioning.
- Bash, GNU `timeout`, OpenSSH client (`ssh`, `ssh-keygen`), and standard GNU tools.
- Your host user must be authorized to manage Incus. Incus management access is
  powerful host authority: never expose its socket or credentials to guests.

Install Incus using the [official instructions](https://linuxcontainers.org/incus/docs/main/installing/),
then run `incus admin init` interactively if this is a new installation. Select
storage and a managed bridge appropriate for your workstation. These scripts do
not reconfigure an existing Incus installation or the host firewall.

Commands operate on your **current Incus remote/project**. Check `incus remote list`
and `incus project list` first; use a local daemon and a trusted default profile.
Remove inherited host disk mounts or other privileged devices from that profile.

## Build the golden image

From the repository root:

```sh
./incus/agent-vm build agent-image-builder
```

The build launches a fresh `images:debian/13` VM, provisions it, stops it, and
publishes the local image alias `agent-dev`. It never imports host configuration,
keys, environment files, or checkouts. Expect substantial downloads; provisioning
typically takes 15-40 minutes and its output streams to your terminal.

The builder disk (`AGENT_VM_BUILD_DISK`, default 20 GiB) becomes the image's
virtual size, so project disks (`AGENT_VM_DISK`) must be at least that large.
The root partition grows to the project disk size on boot via the image's
`incus-growpart` unit, which runs on every boot; do not remove it.

The builder is retained, stopped, for inspection:

```sh
incus info agent-image-builder
incus delete agent-image-builder  # once satisfied; explicit manual cleanup
```

On failure, inspect the builder with `incus console NAME --show-log` or
`incus exec NAME -- bash`. A retry needs a new builder name. Existing instance
names and image aliases are never deliberately replaced. Do not provision a
builder with credentials or project data and then republish it.

Installed tooling:

- Docker Engine, Compose and Buildx plugins; Docker starts at boot.
- Git, C/C++ build tools, Python development tools, pre-commit, bubblewrap.
- Node 26 through fnm, uv, pixi, Ansible.
- GitHub CLI, just, yq, kubectl, Helm, Kustomize, OpenTofu.
- Claude, Codex, Gemini, opencode, pi, rtk.
- Playwright MCP and its matching Chromium browser plus OS dependencies.
- Passwordless `sudo` for dev (Docker access already implies guest root).
- systemd linger for dev, so `systemctl --user` works and `XDG_RUNTIME_DIR` is set.
- `C.UTF-8` locale; GitHub SSH host keys pinned in `/etc/ssh/ssh_known_hosts`.

Versions live in `provision.sh`; GitHub CLI/just/yq use Debian packages rather
than necessarily matching container versions. Several upstream installers use latest,
so builds are not bit-for-bit reproducible. Resolved Debian/npm packages are
recorded under `/etc/dev-containers-{packages,npm}.txt`.

## Create and use a project

```sh
# Public key optional: omit it if you only need `enter`.
./incus/agent-vm create project-foo ~/.ssh/id_ed25519.pub
./incus/agent-vm enter project-foo

# Inside the VM, as dev (enter starts in ~/workspace):
git clone https://github.com/your-org/your-project.git
cd your-project
docker compose up -d
claude  # or codex, gemini, opencode, pi
```

`enter` opens a login shell as dev in `~/workspace` with a real terminal, so job
control (Ctrl-Z, `fg`) works. The VM must be running (`agent-vm start` first).
Login/interactive shells set up the toolchain PATH. For automated commands use
`incus exec project-foo -- su --login dev -c 'your command'`.

No credentials are copied automatically. Either authenticate agents **inside the
guest** (preferably with narrowly scoped credentials), or opt in to copying
your host logins with `agent-vm seed` (below). For private repositories, prefer
a project-specific deploy key/token over your broad host SSH identity. Don't
forward your host SSH agent into an agent-controlled guest.

## Credentials and config (opt-in)

```sh
./incus/agent-vm seed project-foo   # VM must be running; re-run to refresh
```

`seed` copies only this allowlist from your host home into `/home/dev`, owned by
dev with mode 0600. Missing files are skipped (and reported); symlinks are
resolved; re-running overwrites the guest copies. Nothing else is copied, e.g.
not `~/.claude/projects`, history, skills, commands, plugins, or `~/.ssh`.

| Host (`~/`)                         | Guest (`/home/dev/`)    | Purpose |
| ----------------------------------- | ----------------------- | ------- |
| `.claude/.credentials.json`         | same                    | Claude login |
| `.claude/settings.json`             | same                    | Claude settings and hooks |
| `.claude/*.md` (top level only)     | same                    | Global instructions (CLAUDE.md etc.) |
| `.claude.json`                      | same                    | Claude state; also holds per-project allow lists, MCP config and history |
| `.codex/auth.json`, `.codex/config.toml` | same               | Codex login and config |
| `.gemini/oauth_creds.json`, `.gemini/settings.json` | same    | Gemini login and settings |
| `.gitconfig`                        | same                    | Git identity |
| `.config/dev-containers/.env`       | same                    | Environment for login shells |
| `.config/dev-containers/github`     | `.ssh/github`           | Private key used for `github.com` only |

Notes:

- Seeded files are **not** part of the baseline: `reset` wipes them, so re-run
  `seed` afterwards. The image and builder never contain credentials, and only
  project VMs can be seeded.
- `.env` is read by login shells as literal `KEY=VALUE` lines, like
  `podman --env-file`: no quote stripping, no expansion, no host pass-through
  for a bare `KEY`, and no `export` prefix. Blank, `#` and invalid lines are
  ignored.
- The GitHub key is used automatically for `ssh github.com` (an `ssh_config`
  `Match` stanza active only when `~/.ssh/github` exists); host keys are pinned.
- `settings.json` hooks and paths are copied verbatim. The default `rtk hook
  claude` works in the guest; fix any host-only absolute paths inside the VM.
- OAuth refresh tokens rotate: after one side refreshes, the other copy may stop
  working. Re-run `seed` or log in again where needed; a separate login inside
  the guest avoids this.

Security tradeoff: seeded credentials are fully usable (and exfiltratable) by
the agent and anything it runs in the VM. This is no more than the Podman
wrappers expose: they mount these configs (whole directories), `.env` and the
GitHub key. Narrower alternatives: log in inside the guest, use a
project-specific deploy key, or put a fine-grained `GH_TOKEN` in `.env` for `gh`
instead of seeding an SSH key.

## SSH, editor access, and browser ports

```sh
./incus/agent-vm ssh-config project-foo
```

Append the printed stanza to your host `~/.ssh/config` (review it first). Add
`IdentityFile /absolute/path/to/your/key` if you used a nondefault key. This uses
`incus exec ... nc` as an SSH transport, so it doesn't depend on the VM's IP or
expose a host listening port. The VM must be running and the public key must
have been supplied at creation. Your editor can use `project-foo` as an SSH host.

Verify the guest host-key fingerprint before accepting the first connection:

```sh
incus exec project-foo -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
ssh project-foo
```

The simplest way to reach a Compose app is the VM's address on the Incus NAT
bridge, which your host can reach directly (other LAN machines cannot):

```sh
./incus/agent-vm ip project-foo   # e.g. 10.20.30.42
# with a Compose mapping like "3000:3000":
curl http://$(./incus/agent-vm ip project-foo):3000
```

Publish ports as `3000:3000` for this; a `127.0.0.1:3000:3000` mapping is only
reachable inside the guest and needs an SSH forward instead:

```sh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3000:127.0.0.1:3000 project-foo
```

Keep `-L` forwards for OAuth callbacks that bind a guest localhost port; use
provider device-code login where available.

## Working with host files

Host directories are **not** shared with the VM: a shared mount would let the
agent modify host files (git hooks, build scripts) that you later run outside
the boundary, and Incus VM file sharing has uid-mapping caveats. Instead:

- Edit in the VM with VS Code Remote-SSH (or another SSH-capable editor) using
  the `ssh-config` stanza above.
- Mount guest files on the host with `sshfs project-foo:workspace ~/mnt/foo`.
- Move code with git: push from the VM, or add it as a remote
  (`git remote add vm project-foo:workspace/your-project`) and fetch.

A future option is a read-only or `raw.idmap` disk share for specific folders.

## Lifecycle and resources

```sh
./incus/agent-vm stop project-foo    # no-op if already stopped
./incus/agent-vm start project-foo   # no-op if already running; waits for services

# Override defaults when creating a VM or building an image
# (AGENT_VM_BUILD_DISK sizes the builder only):
AGENT_VM_CPU=6 AGENT_VM_MEMORY=12GiB AGENT_VM_DISK=100GiB \
  ./incus/agent-vm create project-big ~/.ssh/id_ed25519.pub

# Change existing VM CPU/RAM while stopped:
incus stop project-foo
incus config set project-foo limits.cpu=6 limits.memory=12GiB
incus start project-foo
```

Defaults: 4 vCPUs, 8 GiB RAM, 60 GiB disk (20 GiB builder). vCPUs share host
CPU time; budget RAM for each running VM. Actual disk allocation depends on the storage backend.
Snapshots and Docker caches consume additional space. A requested disk cannot
be smaller than the source image; root disks generally support growing, not
shrinking. Stop inactive VMs to release their CPU/RAM while retaining data.
`AGENT_VM_WAIT` changes the guest-agent readiness deadline (default 180 seconds).

## Reset, delete, and update

Creation makes a stopped `baseline` snapshot after installing the optional SSH
public key, before any checkout or login credentials. Reset reverts **everything**
inside the VM, including checkouts, Docker volumes, seeded credentials, and tool
updates. It works in any state and restarts the VM only if it was running. A
guest that doesn't shut down within 60 seconds is force-stopped. The baseline is
created with `--no-expiry`, so a profile's `snapshots.expiry` can't remove it:

```sh
# Commit/push or back up work first! Then re-run `seed` if you use it.
./incus/agent-vm reset project-foo --yes
# Deletes a running or stopped project VM, including all snapshots:
./incus/agent-vm delete project-foo --yes
```

These commands require managed project markers; they refuse builder/unmarked
instances. Markers are accident prevention, not a security boundary. Reset keeps
the baseline's SSH key and identity; recreating from an image generates new keys.
Stop/reset aren't a replacement for application-aware database backups.

Publish updates under a new alias:

```sh
AGENT_VM_IMAGE=agent-dev-v2 ./incus/agent-vm build agent-builder-v2
AGENT_VM_IMAGE=agent-dev-v2 ./incus/agent-vm create project-new ~/.ssh/id_ed25519.pub
```

New images do not upgrade existing VMs, and reset restores the original baseline,
not the latest image. Recreate to move to a new image. Snapshots are not off-host
backups; export/back up valuable project state separately.

## Security boundary

The agent controls the **whole guest**: dev has passwordless `sudo`, and Docker
group membership already permits guest root. The VM, not Docker or agent
built-in restrictions, protects the host. Do not share the host engine socket,
Incus socket, home directory, or broad credentials beyond what you deliberately
`seed`. Chromium can use its normal sandbox in this VM; the container README's
`--no-sandbox` requirement doesn't automatically apply here.

NAT is **not** LAN/host isolation. This workflow does not install egress rules:
configure host-side Incus network ACLs/firewall rules if guests must not reach
your workstation, private network, metadata endpoints, or arbitrary internet
services. Credentials given to an agent can be used or exfiltrated regardless of
VM isolation. Persistent VMs retain agent modifications; recreate between trust
contexts. Patch Incus, the host, and the guest regularly.

## Validation

Local, nonprivileged checks:

```sh
bash -n incus/agent-vm incus/provision.sh
shellcheck incus/agent-vm incus/provision.sh
python3 -B -m unittest discover -s incus/tests -v
```

On your KVM workstation, before trusting the image:

1. Build a fresh image. Confirm all installers complete and the builder stops.
2. Create two VMs from it; verify unique `/etc/machine-id` and SSH host-key
   fingerprints, and that neither contains authentication credentials.
3. Enter as dev; verify `node --version`, `uv --version`, each agent's `--version`,
   `docker info`, and `docker compose version`. Confirm Chromium launches.
   Also check: `sudo -n true`; `docker run --rm hello-world`; `id` lists
   `docker`; job control (`sleep 100`, Ctrl-Z, `fg`); `df -h /` shows the full
   project disk; `hostname` is the VM name; `echo $XDG_RUNTIME_DIR` and
   `systemctl --user status` work. On the host, `incus config template list
   project-foo` shows the hostname template.
4. Clone a real project. Exercise Compose build, bind mounts, named database
   volumes, health checks, and a browser via the localhost SSH forward.
5. Stop/start the VM; confirm project data and Compose volumes survive. Services
   only auto-start if their restart policy requests it.
6. Run `seed`, confirm each agent is authenticated and `ssh -T git@github.com`
   succeeds (if a key was seeded). Reach a Compose port with `curl` via
   `agent-vm ip`. Create a disposable file, reset with `--yes`, and confirm the
   file and seeded credentials disappear.
7. Confirm configured CPU/RAM/disk sizes and measure host storage consumption.
8. Verify your intended host/LAN egress policy independently. The default setup
   makes no network-isolation claim.
9. Delete the test VMs explicitly and inspect retained builders/images/snapshots.

## Follow-ups

- Optional read-only/idmapped host folder sharing.
- Optional host-side egress ACL profile.
- Credential refresh without full re-seed (token rotation).
