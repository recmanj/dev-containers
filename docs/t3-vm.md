# T3 VM

Debian 13 on KVM: native T3, Claude Code, Codex, Docker and Compose.
Defaults: 24 GiB RAM, 8 CPUs, 120 GiB sparse disk. Only selected directories
are shared; agents can modify those files and control the VM.

## Install (CachyOS host)

```sh
sudo pacman -Syu --needed qemu-base libvirt virt-install virtiofsd \
  cloud-image-utils dnsmasq python openssh curl
sudo systemctl enable --now libvirtd
sudo virsh -c qemu:///system net-start default
sudo virsh -c qemu:///system net-autostart default
```

Skip `net-start` if already active. Arch supplies the network definition at
`/etc/libvirt/qemu/networks/default.xml`.

If UFW is enabled, allow guest DHCP, DNS and internet access (replace `wlan0`
with your uplink). The bridge name is `virbr0`:

```sh
sudo ufw allow in on virbr0 to any port 67 proto udp
sudo ufw allow in on virbr0 to any port 53 proto udp
sudo ufw allow in on virbr0 to any port 53 proto tcp
sudo ufw route allow in on virbr0 out on wlan0
```

Download the image; require an `OK` checksum result:

```sh
mkdir -p ~/.cache/t3-vm
cd ~/.cache/t3-vm
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
curl -fLO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
sha512sum --check --ignore-missing SHA512SUMS
```

Use an existing SSH key or create one with `ssh-keygen -t ed25519 -f ~/.ssh/t3-vm`.
From the repository, run as your host user, without sudo:

```sh
python t3/vm/prepare.py \
  --share /home/rjak/Code \
  --share /home/rjak/Oxidian/Code \
  --ssh-key ~/.ssh/t3-vm.pub \
  --image ~/.cache/t3-vm/debian-13-genericcloud-amd64.qcow2 \
  --output ~/.config/dev-containers/t3-vm
```

Review the generated `create.sh`, `network.py`, `virtiofsd.py`, `virtiofsd.json`
and `user-data` before executing:

```sh
bash ~/.config/dev-containers/t3-vm/create.sh
```

Repeat `--share` to choose directories. They must exist below your home,
not overlap, and have no spaces or special characters. UID/GID and paths
match the host. Options: `--memory`, `--cpus`, `--disk`, `--name`, `--ip`.
The default IP is `192.168.122.50`; choose an unused address on your libvirt NAT subnet.
Existing output directories, VM definitions and disks are never overwritten.
Keep the image and generated installer outside all shares. The generator rejects
overlapping paths, symlink aliases and hard-linked images.

## Connect

Log in to finish setup:

```sh
ssh -o ForwardAgent=no -i ~/.ssh/t3-vm rjak@192.168.122.50
```

In the VM:

```sh
sudo cloud-init status --wait --long
systemctl --user status t3
~/.local/bin/t3 pair
```

First boot downloads the tools. Errors: `/var/log/cloud-init-output.log`.
Authenticate Claude/Codex in the VM; host credentials aren't copied.

Prefer the app's SSH connection to `rjak@192.168.122.50` using your VM key.
For browser access, pair with `http://192.168.122.50:3773` (or your `--ip`);
this direct connection is unencrypted.
The DHCP reservation persists across restarts. The host and other guests on
the NAT network can reach T3; physical LAN access isn't forwarded automatically.

To migrate threads, stop both T3 services and copy the old `.t3` directory
into the guest's `~/.t3` before restarting.

## Daily use

On the host:

```sh
install -Dm755 t3/vm/t3-vm ~/.local/bin/t3-vm
t3-vm start
t3-vm status
t3-vm ssh
t3-vm run docker ps
t3-vm run bash -lc 'cd ~/Code/project && npm test'
t3-vm logs
t3-vm stop
```

The wrapper defaults to `t3-dev`, `192.168.122.50`, your host username and
`~/.ssh/t3-vm`. Override with `T3_VM_NAME`, `T3_VM_HOST`, `T3_VM_USER`,
or `T3_VM_KEY`. `stop` requests shutdown; use `status` to confirm it finished.
`start` does not wait for SSH readiness. `console` opens the serial console.

RAM is allocated on demand. Free-page reporting can return unused pages, but
guest caches may retain most of the 24 GiB. Shutdown releases it fully once
the state is `shut off`. Host files stay accessible.

In the VM, use `docker`, `docker compose` and `docker buildx` without sudo.
Guest writes to shares are mapped to your host UID/GID, including Docker-root
writes. A root-owned launcher runs virtiofsd as your host user in a private
user namespace, with device creation and file capabilities disabled;
shares don't support arbitrary ownership or extended attributes. Keep databases
in named volumes. Don't run agent-written scripts with host sudo without reviewing them.
After first boot, verify a Docker-root-created file is owned by your user on
the host, and check edits and file watchers from both sides.
Use the share's primary group when writing; supplementary-group-only access
can fail in the single-group namespace. Very large trees may hit the daemon's
file-descriptor limit.

## Add a share

New projects inside existing shares need no configuration. For another directory:

1. Shut down the VM. Use `sudo virsh -c qemu:///system edit t3-dev` to copy an
   existing `<filesystem>` block, changing its source directory and target tag.
   Keep its `<binary>` settings: these enforce the host ownership policy.
2. Start the VM, create its mount directory, and add an `/etc/fstab` entry:
   `code2 /home/rjak/AnotherProject virtiofs rw,nosuid,nodev,nofail 0 0`.
3. Run `sudo systemctl daemon-reload` and `sudo mount /home/rjak/AnotherProject`.
4. Add `ExecStartPre=/usr/bin/mountpoint -q /home/rjak/AnotherProject` under
   `[Service]` in `~/.config/systemd/user/t3.service`, then run
   `systemctl --user daemon-reload`.

After starting, confirm this VM's virtiofsd processes run as your host user
with `ps -eo user,pid,args`; a root-owned process indicates incorrect setup.

To unshare, remove the guest's service check and fstab entry first, then shut
down and remove the VM device. Keep the host directory.

## Recovery

The generator disables guest SMM to avoid the BIOS boot stall observed on
CachyOS. For an older VM stuck at `Booting Debian`, add `<smm state='off'/>`
inside its XML `<features>` section and fully stop/start the VM.

Retry failed provisioning inside the VM:

```sh
sudo sh /var/lib/cloud/instance/scripts/runcmd
```

A failed share mount leaves SSH available but prevents T3 startup. Fix the
mount, then `systemctl --user reset-failed t3 && systemctl --user start t3`.

To discard a failed install, shut it down first. These host commands **delete
the guest disk**, not the shared code:

```sh
sudo virsh -c qemu:///system undefine t3-dev
sudo rm -r /var/lib/libvirt/images/t3-dev /usr/local/libexec/t3-dev
```

If `sudo virsh -c qemu:///system pool-list --all` lists a pool targeting that disk
directory, run `pool-destroy` (if active) and `pool-undefine` for it before deleting
the directory. Keep the generated configuration to retry `create.sh`. Its same
DHCP reservation is reused; to remove it instead, use `net-update default delete
ip-dhcp-host` with the generated `reservation.xml`, for both `--live` and `--config`.

## Update (inside VM)

Development tools include `gh`, uv and mise, with Node 24 as the default.
Use `mise use node@22` in a project to select another version. Mise shims are
on PATH in Bash and T3. uv installs the current release; mise is pinned in
`install-dev-tools.sh` and updated by Renovate. Re-running that script resets the global Node default to 24.

Mise also installs DevOps tools globally: yq, rtk, shellcheck, kubectl, helm,
kustomize, kind, kubeconform, stern, kubectx, k9s, OpenTofu, Terraform and
tflint. uv installs Ansible, ansible-lint and pre-commit. There is no cloud CLI
and no cloud credentials, so agents can render, lint and validate, and test
against a local kind cluster, but not reach real infrastructure.

The mise tools are pinned in `t3/vm/mise.toml`, which Renovate keeps current.
The script copies it to `~/.config/mise/conf.d/t3-vm.toml`. To pick up new
versions, pull this repository and re-run the script. uv tools update to
their current release each time the script runs.

To have agents use rtk, run `rtk init -g` (Claude Code) and
`rtk init -g --codex` once, then restart T3.

To add these tools to an existing VM, run as your guest user from this checkout:

```sh
bash t3/vm/install-dev-tools.sh
systemctl --user daemon-reload
systemctl --user restart t3
```

Reconnect SSH for the updated PATH. Restart T3 when no agent tasks are running.

Replace the version placeholders with release numbers, without a leading `v`:

```sh
systemctl --user stop t3
bash /opt/t3/install-tools.sh T3_VERSION CLAUDE_VERSION CODEX_VERSION
systemctl --user start t3
sudo apt update && sudo apt upgrade
```

Initial tool versions come from the repository's Dockerfiles and are recorded
in the generated `user-data`. Docker packages use Docker's stable Debian repository.
