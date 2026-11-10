"""Run with: python3 -m unittest discover -s t3/vm -p 'test_*.py'."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

from prepare import render


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.code = self.home / "Code"
        self.code.mkdir()
        self.other = self.home / "Oxidian" / "Code"
        self.other.mkdir(parents=True)
        self.key = self.home / "key.pub"
        self.key.write_text("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest fixture\n")
        self.image = self.home / "image with ' quotes.qcow2"
        self.image.touch()
        self.identity = SimpleNamespace(pw_name="developer", pw_uid=1234,
                                        pw_gid=2345, pw_dir=str(self.home))
        self.args = argparse.Namespace(share=[str(self.code), str(self.other)],
                                       name="t3-dev", ssh_key=str(self.key),
                                       image=str(self.image), memory=24, cpus=8, disk=120,
                                       ip="192.168.122.50", output=str(self.home / "private-config"))

    def test_exports_identity_and_native_service(self):
        result = render(self.args, self.identity)
        cloud = json.loads(result["user-data"].split("\n", 1)[1])
        self.assertEqual(cloud["users"][0]["uid"], 1234)
        self.assertIn("2345", cloud["bootcmd"][0])
        self.assertEqual([m[1] for m in cloud["mounts"]], [str(self.code), str(self.other)])
        service = next(f["content"] for f in cloud["write_files"]
                       if f["path"].endswith("t3.service"))
        self.assertIn("ExecStart=%h/.local/bin/t3 serve", service)
        self.assertIn("Environment=T3CODE_HOST=0.0.0.0", service)
        self.assertNotIn("CONTAINER_HOST", service)
        self.assertNotIn("DOCKER_HOST", service)
        self.assertNotIn("Volume=", service)
        self.assertNotIn("podman", result["user-data"])
        self.assertIn("ExecStartPre=/usr/bin/docker info", service)
        self.assertIn("docker", cloud["groups"])
        self.assertIn("docker", cloud["users"][0]["groups"])
        for path in (self.code, self.other):
            self.assertIn(f"ExecStartPre=/usr/bin/mountpoint -q {path}", service)
        self.assertTrue(all("nofail" in m[3].split(",") for m in cloud["mounts"]))
        self.assertEqual(len(cloud["runcmd"][0]), 8)
        self.assertTrue(all(v[0].isdigit() for v in cloud["runcmd"][0][-3:]))

    def test_installer_syntax_memory_and_quoting(self):
        script = render(self.args, self.identity)["create.sh"]
        subprocess.run(["bash", "-n"], input=script, text=True, check=True)
        command = next(line for line in script.splitlines() if line.startswith("sudo virt-install"))
        argv = shlex.split(command)
        self.assertEqual(argv[argv.index("--memory") + 1], "24576")
        self.assertEqual(argv[argv.index("--features") + 1], "smm.state=off")
        self.assertIn("virtio,freePageReporting=on", argv)
        self.assertIn("source.type=memfd,access.mode=shared,allocation.mode=ondemand", argv)
        self.assertEqual(argv.count("--filesystem"), 2)
        for index, arg in enumerate(argv):
            if arg == "--filesystem":
                self.assertIn("binary.path=/usr/local/libexec/t3-dev/virtiofsd.py", argv[index + 1])
                self.assertIn("binary.xattr=off", argv[index + 1])
        network = argv[argv.index("--network") + 1]
        self.assertIn("mac=52:54:00:", network)
        self.assertIn(" reserve t3-dev 192.168.122.50 ", script)
        copy = next(line for line in script.splitlines() if line.startswith("sudo cp "))
        self.assertIn(str(self.image), shlex.split(copy))
        self.assertNotIn("--autostart", argv)

    def test_invalid_ip_rejected_before_writing(self):
        self.args.ip = "192.168.122.50; touch /tmp/injected"
        with self.assertRaises(ValueError):
            render(self.args, self.identity)

    def test_private_artifacts_cannot_overlap_shares(self):
        for output in (self.code, self.code / "installer", self.home):
            with self.subTest(output=output), self.assertRaises(ValueError):
                self.args.output = str(output)
                render(self.args, self.identity)
        self.args.output = str(self.home / "private-config")
        shared_image = self.code / "guest.qcow2"
        shared_image.touch()
        self.args.image = str(shared_image)
        with self.assertRaises(ValueError):
            render(self.args, self.identity)

    def test_aliases_cannot_hide_shared_artifacts(self):
        alias = self.home / "alias"
        alias.symlink_to(self.code, target_is_directory=True)
        self.args.output = str(alias / "installer")
        with self.assertRaises(ValueError):
            render(self.args, self.identity)
        self.args.output = str(self.home / "private-config")
        (self.code / "image-hardlink").hardlink_to(self.image)
        with self.assertRaises(ValueError):
            render(self.args, self.identity)

    def test_no_home_or_outside_or_overlapping_exports(self):
        for shares in ([str(self.home)], [self.tmp.name],
                       [str(self.code), str(self.code)],
                       [str(self.home / "Oxidian"), str(self.other)]):
            with self.subTest(shares=shares):
                self.args.share = shares
                with self.assertRaises(ValueError):
                    render(self.args, self.identity)

    def test_symlink_cannot_escape_home(self):
        link = self.home / "outside"
        link.symlink_to(self.tmp.name, target_is_directory=True)
        self.args.share = [str(link)]
        with self.assertRaises(ValueError):
            render(self.args, self.identity)

    def test_format_control_characters_rejected(self):
        for name in ("space path", "colon:path", "percent%h", "comma,path"):
            with self.subTest(name=name):
                path = self.home / name
                path.mkdir()
                self.args.share = [str(path)]
                with self.assertRaises(ValueError):
                    render(self.args, self.identity)

    def test_reject_private_key_and_root(self):
        self.key.write_text("-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n")
        with self.assertRaises(ValueError):
            render(self.args, self.identity)
        self.identity.pw_uid = 0
        with self.assertRaises(ValueError):
            render(self.args, self.identity)


if __name__ == "__main__":
    unittest.main()
