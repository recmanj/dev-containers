#!/usr/bin/env python3
"""Render a reviewable VM installer on the physical host; never run sudo here."""

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shlex


HERE = Path(__file__).resolve().parent


def tool_versions():
    versions = []
    for relative, variable in (("t3/Dockerfile", "T3CODE_VERSION"),
                               ("claude/Dockerfile", "CLAUDE_CODE_VERSION"),
                               ("claude/Dockerfile", "CODEX_CLI_VERSION")):
        source = (HERE.parent.parent / relative).read_text()
        match = re.search(rf"^ARG {variable}=([0-9][0-9.a-z-]*)$", source, re.MULTILINE)
        if not match:
            raise ValueError(f"Cannot find a pinned {variable} in {relative}")
        versions.append(match[1])
    return versions


def render(args, identity):
    home = Path(identity.pw_dir).resolve()
    user, uid, gid = identity.pw_name, identity.pw_uid, identity.pw_gid
    if uid < 1000 or gid < 1000 or not re.fullmatch(r"[a-z_][a-z0-9_-]*", user):
        raise ValueError("Run as your regular host user, without sudo (UID/GID >= 1000).")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,40}", args.name):
        raise ValueError("VM name must be a short lowercase name, digits and hyphens only.")
    address = str(ipaddress.IPv4Address(args.ip))
    suffix = hashlib.sha256(args.name.encode()).digest()[:3]
    mac = "52:54:00:" + ":".join(f"{octet:02x}" for octet in suffix)
    shares = []
    for value in args.share:
        path = Path(value).expanduser().resolve(strict=True)
        # Limit exports to explicitly selected directories within this user's home.
        # Resolve symlinks before checking, and reject syntax interpreted by fstab,
        # systemd, or virt-install rather than trying to escape three formats.
        if not path.is_dir() or not path.is_relative_to(home) or path == home:
            raise ValueError(f"Share must be a directory strictly below {home}: {path}")
        if not re.fullmatch(r"/[A-Za-z0-9_./-]+", str(path)):
            raise ValueError(f"Share paths must not contain whitespace or special characters: {path}")
        if any(path == other or path.is_relative_to(other) or other.is_relative_to(path)
               for other in shares):
            raise ValueError(f"Duplicate or overlapping share: {path}")
        shares.append(path)
    output = Path(args.output).expanduser().resolve()
    image = Path(args.image).expanduser().resolve(strict=True)
    for label, path in (("output", output), ("image", image)):
        if any(path == share or path.is_relative_to(share) or share.is_relative_to(path)
               for share in shares):
            raise ValueError(f"--{label} must be outside, and not contain, every shared directory: {path}")
    if image.stat().st_nlink != 1:
        raise ValueError("--image must not have hard links; copy it into private host storage")
    key = Path(args.ssh_key).expanduser().read_text().strip()
    if "\n" in key or not key.startswith(("ssh-ed25519 ", "ssh-rsa ", "ecdsa-sha2-")):
        raise ValueError("--ssh-key must contain one OpenSSH public key, never a private key.")
    if not image.is_file():
        raise ValueError("--image must be a downloaded Debian 13 amd64 qcow2 image.")
    if args.memory < 1 or args.cpus < 1 or args.disk < 10:
        raise ValueError("Memory/CPUs must be positive; disk must be at least 10 GiB.")

    service = """[Unit]
Description=t3code server

[Service]
Type=simple
WorkingDirectory=%h
Environment=PATH=%h/.local/bin:%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin
Environment=T3CODE_HOST=0.0.0.0
Environment=T3CODE_PORT=3773
ExecStartPre=/usr/bin/docker info
ExecStart=%h/.local/bin/t3 serve
Restart=on-failure
RestartSec=5
"""
    # User units cannot order against the system manager's mount units.
    # Fail closed if a share was not mounted by the system's fstab processing.
    service += "".join(f"ExecStartPre=/usr/bin/mountpoint -q {p}\n" for p in shares)
    service += """

[Install]
WantedBy=default.target
"""
    files = []
    for name, contents, mode in (
        ("install-tools.sh", (HERE / "install-tools.sh").read_text(), "0755"),
        ("install-dev-tools.sh", (HERE / "install-dev-tools.sh").read_text(), "0755"),
        ("install-monitoring.sh", (HERE / "install-monitoring.sh").read_text(), "0755"),
        ("install-share-guard.sh", (HERE / "install-share-guard.sh").read_text(), "0755"),
        ("mise.toml", (HERE / "mise.toml").read_text(), "0644"),
        ("guest-setup.sh", (HERE / "guest-setup.sh").read_text(), "0755"),
        ("t3.service", service, "0644"),
    ):
        files.append({"path": f"/opt/t3/{name}", "permissions": mode, "content": contents})
    cloud = {
        "hostname": args.name,
        "ssh_pwauth": False,
        "disable_root": True,
        "package_update": True,
        "packages": ["dbus-user-session", "qemu-guest-agent", "git", "gh",
                     "curl", "ca-certificates", "nodejs", "npm", "python3", "python3-venv",
                     "build-essential", "ripgrep", "jq", "unzip", "bubblewrap", "chromium"],
        "bootcmd": [["cloud-init-per", "once", "t3-group", "groupadd", "--gid", str(gid), user]],
        "groups": ["docker"],
        "users": [{"name": user, "uid": uid, "primary_group": user,
                   "groups": ["docker"],
                   "homedir": str(home), "shell": "/bin/bash", "lock_passwd": True,
                   "sudo": "ALL=(ALL) NOPASSWD:ALL", "ssh_authorized_keys": [key]}],
        "mounts": [[f"code{i}", str(p), "virtiofs", "rw,nosuid,nodev,nofail", "0", "0"]
                   for i, p in enumerate(shares)],
        "write_files": files,
        "runcmd": [["bash", "/opt/t3/guest-setup.sh", user, str(uid), str(home), *tool_versions()]],
    }
    disk_dir = f"/var/lib/libvirt/images/{args.name}"
    daemon_dir = f"/usr/local/libexec/{args.name}"
    command = ["sudo", "virt-install", "--connect", "qemu:///system", "--name", args.name,
               "--virt-type", "kvm", "--arch", "x86_64", "--machine", "q35",
               "--memory", str(args.memory * 1024), "--vcpus", str(args.cpus),
               "--cpu", "host-passthrough", "--osinfo", "debian13",
               "--features", "smm.state=off",
               "--memorybacking", "source.type=memfd,access.mode=shared,allocation.mode=ondemand",
               "--memballoon", "virtio,freePageReporting=on",
               "--disk", f"path={disk_dir}/root.qcow2,format=qcow2,bus=virtio",
               "--disk", f"path={disk_dir}/seed.iso,device=cdrom",
               "--network", f"network=default,model=virtio,mac={mac}", "--graphics", "none",
               "--channel", "unix,target.type=virtio,target.name=org.qemu.guest_agent.0",
               "--import", "--noautoconsole", "--print-xml"]
    for i, path in enumerate(shares):
        command += ["--filesystem", f"source={path},target=code{i},driver.type=virtiofs,accessmode=passthrough,"
                    f"binary.path={daemon_dir}/virtiofsd.py,binary.xattr=off,binary.sandbox.mode=namespace"]
    install = f"""#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "${{BASH_SOURCE[0]}}")"
for tool in sudo virsh virt-install cloud-localds qemu-img python3 setpriv; do
    command -v "$tool" >/dev/null || {{ echo "Missing host tool: $tool" >&2; exit 1; }}
done
test -c /dev/kvm || {{ echo 'Run this on the physical KVM host.' >&2; exit 1; }}
if sudo virsh -c qemu:///system dominfo {shlex.quote(args.name)} >/dev/null 2>&1; then
    echo 'VM already exists; refusing to overwrite it.' >&2
    exit 1
fi
# Validate libvirt connectivity and the network before allocating storage.
sudo virsh -c qemu:///system net-info default
sudo python3 -I network.py check {args.name} {address} {mac}
# Fail before creating a VM if this virtiofsd lacks ownership translation.
sudo python3 -I virtiofsd.py --print-capabilities >/dev/null
cloud-localds seed.iso user-data meta-data
# mkdir deliberately fails if storage already exists, including after a partial run.
sudo mkdir -- {shlex.quote(disk_dir)}
sudo install -d -m 0755 {daemon_dir}
sudo install -o root -g root -m 0755 virtiofsd.py {daemon_dir}/virtiofsd.py
sudo install -o root -g root -m 0644 virtiofsd.json {daemon_dir}/virtiofsd.json
sudo cp --reflink=auto --sparse=always -- {shlex.quote(str(image))} {disk_dir}/root.qcow2
sudo qemu-img resize {disk_dir}/root.qcow2 {args.disk}G
sudo install -m 0644 seed.iso {disk_dir}/seed.iso
{shlex.join(command)} > domain.xml
sudo virsh -c qemu:///system define domain.xml
sudo python3 -I network.py reserve {args.name} {address} {mac}
sudo virsh -c qemu:///system start {args.name}
echo 'VM started. After first boot, pair with http://{address}:3773'
"""
    return {"user-data": "#cloud-config\n" + json.dumps(cloud, indent=2) + "\n",
            "meta-data": json.dumps({"instance-id": args.name, "local-hostname": args.name}) + "\n",
            "create.sh": install,
            "virtiofsd.py": (HERE / "virtiofsd.py").read_text(),
            "virtiofsd.json": json.dumps({"uid": uid, "gid": gid}) + "\n",
            "network.py": (HERE / "network.py").read_text(),
            "reservation.xml": f'<host mac="{mac}" name="{args.name}" ip="{address}"/>\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--share", action="append", required=True, help="Host directory; repeat for each share")
    parser.add_argument("--ssh-key", required=True, help="Host SSH public key for VM login")
    parser.add_argument("--image", required=True, help="Verified Debian 13 amd64 qcow2 image")
    parser.add_argument("--output", required=True, help="New directory for generated configuration")
    parser.add_argument("--name", default="t3-dev")
    parser.add_argument("--ip", default="192.168.122.50", help="Reserved IPv4 address on the default NAT network")
    parser.add_argument("--memory", type=int, default=24, help="Guest RAM in GiB (default: 24)")
    parser.add_argument("--cpus", type=int, default=8)
    parser.add_argument("--disk", type=int, default=120, help="Sparse guest disk size in GiB")
    args = parser.parse_args()
    try:
        artifacts = render(args, pwd.getpwuid(os.getuid()))
        output = Path(args.output).expanduser().resolve()
        output.mkdir(mode=0o700, parents=True, exist_ok=False)
        for name, contents in artifacts.items():
            path = output / name
            path.write_text(contents)
            path.chmod(0o700 if name.endswith(".sh") else 0o600)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    print(f"Prepared {output}. Review user-data, create.sh, network.py, virtiofsd.py and virtiofsd.json "
          f"before running: bash {shlex.quote(str(output / 'create.sh'))}")


if __name__ == "__main__":
    main()
