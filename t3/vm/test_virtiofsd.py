import unittest

from virtiofsd import daemon_args


class SharePolicyTests(unittest.TestCase):
    def test_all_guest_ids_map_to_unprivileged_owner(self):
        args = daemon_args(1234, 2345, ["--fd=10", "--shared-dir=/home/dev/Code"])
        self.assertEqual(args[:6], ["/usr/bin/setpriv", "--reuid", "1234", "--regid", "2345", "--clear-groups"])
        for flag in ("--inh-caps=-all", "--ambient-caps=-all", "--no-new-privs"):
            self.assertIn(flag, args)
        self.assertIn("--uid-map=:0:1234:1:", args)
        self.assertIn("--gid-map=:0:2345:1:", args)
        self.assertIn("--translate-uid=squash-guest:0:0:4294967295", args)
        self.assertIn("--translate-gid=squash-guest:0:0:4294967295", args)
        self.assertIn("--translate-uid=host:0:1234:1", args)
        caps = next(arg.split("=", 1)[1].split(":") for arg in args if arg.startswith("--modcaps="))
        for cap in ("-mknod", "-setfcap", "-chown", "-fowner", "-dac_override", "-fsetid"):
            self.assertIn(cap, caps)

    def test_privileged_mapping_or_policy_override_rejected(self):
        for uid, gid in ((0, 1000), (1000, 0)):
            with self.assertRaises(ValueError):
                daemon_args(uid, gid, [])
        for option in ("--xattr", "--posix-acl", "--security-label", "--modcaps=+mknod",
                       "--translate-uid=map:0:0:1", "--uid-map=:0:0:1:"):
            with self.subTest(option=option), self.assertRaises(ValueError):
                daemon_args(1000, 1000, [option])

    def test_legacy_options_and_unknown_flags_are_rejected(self):
        for arguments in (["-o", "modcaps=+mknod,xattr"], ["--unknown"],
                          ["--cache", "--xattr"], ["--readonly=true"],
                          ["--fd=3", "--fd=4"]):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                daemon_args(1000, 1000, arguments)

    def test_libvirt_separate_options_are_preserved(self):
        arguments = ["--fd=3", "--shared-dir", "/home/dev/Code", "--cache", "never",
                     "--thread-pool-size=4", "--rlimit-nofile=1000000", "--log-level", "debug",
                     "--readonly"]
        args = daemon_args(1000, 1000, arguments)
        for expected in ("--fd=3", "--shared-dir=/home/dev/Code", "--cache=never", "--readonly"):
            self.assertIn(expected, args)

    def test_libvirt_sandbox_arguments_cannot_disable_namespace(self):
        for arguments in (["--sandbox", "none"], ["--sandbox=chroot"], ["--sandbox"]):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                daemon_args(1000, 1000, arguments)
        for arguments in ([], ["--sandbox", "namespace"], ["--sandbox=namespace"]):
            args = daemon_args(1000, 1000, arguments)
            self.assertEqual(args.count("--sandbox=namespace"), 1)


if __name__ == "__main__":
    unittest.main()
