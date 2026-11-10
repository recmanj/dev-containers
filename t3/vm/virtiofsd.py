#!/usr/bin/python3 -I
"""Host-owned virtiofsd launcher. Configuration lives beside this file.

Uses upstream's unprivileged namespace and UID/GID translation support:
https://gitlab.com/virtio-fs/virtiofsd/-/blob/main/README.md
"""

import json
import os
from pathlib import Path
import sys


def daemon_args(uid, gid, arguments):
    if uid < 1000 or gid < 1000:
        raise ValueError("Refusing to map guest writes to a privileged host identity")
    # Accept only the separate-options interface used by modern libvirt.
    # In particular, legacy -o options can override otherwise fixed policy.
    flags = {"--readonly", "--print-capabilities", "--version", "--syslog"}
    values = {"--fd", "--shared-dir", "--cache", "--thread-pool-size",
              "--rlimit-nofile", "--log-level", "--sandbox"}
    filtered = []
    seen = set()
    pending = iter(arguments)
    for arg in pending:
        name, separator, value = arg.partition("=")
        if name in seen:
            raise ValueError(f"Duplicate daemon option: {name}")
        seen.add(name)
        if name in flags and not separator:
            filtered.append(name)
            continue
        if name not in values:
            raise ValueError(f"Unsupported daemon option: {name}")
        if not separator:
            value = next(pending, "")
        if not value or value.startswith("-"):
            raise ValueError(f"Missing value for {name}")
        if name == "--sandbox":
            if value != "namespace":
                raise ValueError("Only namespace sandboxing is allowed")
        else:
            filtered.append(f"{name}={value}")
    # Drop real host root *before* virtiofsd starts. Its private user namespace
    # maps only namespace root to the host user. Translation alone is not an
    # isolation boundary: some metadata operations do not switch credentials.
    return ["/usr/bin/setpriv", "--reuid", str(uid), "--regid", str(gid),
            "--clear-groups", "--inh-caps=-all", "--ambient-caps=-all", "--no-new-privs",
            "--", "/usr/lib/virtiofsd", *filtered,
            "--sandbox=namespace", f"--uid-map=:0:{uid}:1:", f"--gid-map=:0:{gid}:1:",
            "--translate-uid=squash-guest:0:0:4294967295",
            "--translate-gid=squash-guest:0:0:4294967295",
            f"--translate-uid=host:0:{uid}:1", f"--translate-gid=host:0:{gid}:1",
            "--inode-file-handles=never",
            "--modcaps=-mknod:-setfcap:-chown:-fowner:-dac_override:-dac_read_search:-fsetid"]


def main():
    config = json.loads(Path(__file__).with_name("virtiofsd.json").read_text())
    command = daemon_args(config["uid"], config["gid"], sys.argv[1:])
    os.execv(command[0], command)


if __name__ == "__main__":
    main()
