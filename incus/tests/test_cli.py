"""CLI contract tests; no Incus daemon, VMs, network, or root required."""
import base64
import json
import os
import struct
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

CLI = Path(__file__).resolve().parents[1] / "agent-vm"
MOCK = '''#!/usr/bin/env python3
import json, os, subprocess, sys
a = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps(a) + '\\n')
if os.environ.get('FAIL') and a[:2] == os.environ['FAIL'].split():
    sys.exit(1)
if os.environ.get('FAIL_EXACT') and a == json.loads(os.environ['FAIL_EXACT']):
    sys.exit(1)
if a[:2] == ['config', 'get']:
    if os.environ.get('STATE', 'RUNNING') == '':
        sys.exit(1)
    print(os.environ.get('MOCK_MARKER', 'dev-containers-v1') if a[-1] == 'user.dev-containers' else os.environ.get('ROLE', 'project'))
if a[:3] == ['image', 'alias', 'list']:
    if '-c' in a or '--columns' in a:
        sys.exit('Error: unknown shorthand flag: c')  # Incus 6.0 client
    for alias in filter(None, os.environ.get('ALIASES', '').split()):
        print(f'{alias},0123456789ab,x86_64,VIRTUAL-MACHINE,')
if a[:2] == ['snapshot', 'list']:
    if '-c' in a or '--columns' in a:
        sys.exit('Error: unknown shorthand flag: c')  # Incus 6.0 client
    for snap in filter(None, os.environ.get('SNAPSHOTS', 'baseline').split()):
        print(f'{snap},2026/01/01 00:00 UTC,,NO')
if a[0] == 'list':
    # Replay successful calls on top of STATE; print only the csv state column.
    state = os.environ.get('STATE', 'RUNNING')
    with open(os.environ['CALLS']) as f:
        for c in map(json.loads, f):
            if os.environ.get('FAIL') and c[:2] == os.environ['FAIL'].split():
                continue
            if os.environ.get('FAIL_EXACT') and c == json.loads(os.environ['FAIL_EXACT']):
                continue
            if c[0] in ('launch', 'start'):
                state = 'RUNNING'
            elif c[0] == 'stop':
                state = 'STOPPED'
    if state:
        print(state)
if a[0] == 'exec':
    cmd = a[a.index('--') + 1:]
    if cmd[0] in ('sh', 'systemctl'):
        sys.exit(subprocess.run(cmd).returncode)
    if cmd[0] == 'ip':
        route = os.environ.get('ROUTE', '1.1.1.1 via 10.20.30.1 dev enp5s0 src 10.20.30.42 uid 0')
        if route:
            print(route)
'''
SYSTEMCTL = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS']) as f:
    calls = [json.loads(line) for line in f]
failed = os.environ.get('FAIL_SERVICE')
if os.environ.get('FAIL_AFTER_RESTART') and not any(c[0] == 'start' for c in calls):
    failed = None
# Match actual systemctl semantics: success if at least one supplied unit is active.
units = [a for a in sys.argv[2:] if not a.startswith('-')]
sys.exit(0 if any(unit != failed for unit in units) else 3)
'''


class CLIContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        mock = self.root / 'incus'
        mock.write_text(MOCK)
        mock.chmod(0o755)
        systemctl = self.root / 'systemctl'
        systemctl.write_text(SYSTEMCTL)
        systemctl.chmod(0o755)
        self.calls = self.root / 'calls'
        self.home = self.root / 'home'
        self.home.mkdir()
        self.env = dict(os.environ, PATH=f'{self.root}:{os.environ["PATH"]}', CALLS=str(self.calls),
                        HOME=str(self.home))
        for key in list(self.env):
            if key.startswith('AGENT_VM_'):
                del self.env[key]

    def run_cli(self, *args, ok=True, **env):
        result = subprocess.run(['bash', str(CLI), *args], env=self.env | env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def recorded(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_help_without_name(self):
        output = self.run_cli('--help').stdout
        for word in ('create', 'seed NAME', 'ip NAME', 'AGENT_VM_BUILD_DISK'):
            self.assertIn(word, output)
        self.assertEqual(self.recorded(), [])

    def test_create_defaults_and_baseline(self):
        self.run_cli('create', 'project-foo')
        calls = self.recorded()
        self.assertEqual(calls[0], ['launch', 'agent-dev', 'project-foo', '--vm',
            '-c', 'limits.cpu=4', '-c', 'limits.memory=8GiB', '-c',
            'user.dev-containers=dev-containers-v1', '-c', 'user.dev-containers.role=project',
            '-d', 'root,size=60GiB'])
        self.assertLess(calls.index(['stop', 'project-foo']), calls.index(['snapshot', 'create', 'project-foo', 'baseline', '--no-expiry']))

    def test_resource_overrides(self):
        self.run_cli('create', 'demo', AGENT_VM_CPU='6', AGENT_VM_MEMORY='12GiB', AGENT_VM_DISK='100GiB', AGENT_VM_IMAGE='v2')
        launch = self.recorded()[0]
        for value in ['v2', 'limits.cpu=6', 'limits.memory=12GiB', 'root,size=100GiB']:
            self.assertIn(value, launch)

    def test_invalid_inputs_do_not_call_incus(self):
        for args, env in [(['create', 'x;touch-pwn'], {}), (['delete', 'demo'], {}),
                          (['reset', 'demo', '--force'], {}), (['create', 'demo'], {'AGENT_VM_CPU': '0'}),
                          (['create', 'demo'], {'AGENT_VM_MEMORY': 'oops'}),
                          (['create', 'demo'], {'AGENT_VM_IMAGE': 'remote:alias'}),
                          (['start', 'demo', 'extra'], {}), (['seed', 'demo', 'extra'], {}),
                          (['ip', 'demo', 'extra'], {}),
                          (['build', 'demo'], {'AGENT_VM_BUILD_DISK': 'oops'})]:
            self.run_cli(*args, ok=False, **env)
        self.assertEqual(self.recorded(), [])

    def test_unmanaged_and_builder_protection(self):
        for command in ('delete', 'reset', 'seed', 'ip', 'enter'):
            args = [command, 'demo'] + (['--yes'] if command in ('delete', 'reset') else [])
            for env in ({'MOCK_MARKER': ''}, {'ROLE': 'builder'}):
                with self.subTest(command=command, env=env):
                    self.calls.unlink(missing_ok=True)
                    self.run_cli(*args, ok=False, **env)
                    self.assertTrue(all(c[0] == 'config' for c in self.recorded()))

    def test_delete_explicit_confirmation(self):
        self.run_cli('delete', 'demo', '--yes')
        self.assertEqual(self.recorded()[-1], ['delete', 'demo', '--force'])

    def test_missing_baseline_does_not_stop(self):
        self.run_cli('reset', 'demo', '--yes', ok=False, SNAPSHOTS='')
        self.assertFalse(any(c[0] == 'stop' for c in self.recorded()))

    def test_reset(self):
        self.run_cli('reset', 'demo', '--yes')
        self.assertIn(['snapshot', 'restore', 'demo', 'baseline'], self.recorded())

    def test_launch_failure_stops_without_cleanup(self):
        self.run_cli('create', 'demo', ok=False, FAIL='launch agent-dev')
        self.assertEqual(len(self.recorded()), 1)

    def test_build_refuses_existing_alias(self):
        self.run_cli('build', 'builder', ok=False, ALIASES='agent-dev')
        self.assertEqual(self.recorded()[0], ['image', 'alias', 'list', '--format', 'csv'])
        self.assertFalse(any(c[0] == 'launch' for c in self.recorded()))

    def test_alias_query_failure_does_not_launch(self):
        self.run_cli('build', 'builder', ok=False, FAIL='image alias')
        self.assertEqual(len(self.recorded()), 1)

    def test_stop_failure_prevents_restore(self):
        self.run_cli('reset', 'demo', '--yes', ok=False, FAIL='stop demo')
        self.assertNotIn(['snapshot', 'restore', 'demo', 'baseline'], self.recorded())

    def test_provisioning_refuses_normal_invocation(self):
        env = dict(self.env)
        env.pop('DEV_CONTAINERS_PROVISION', None)
        result = subprocess.run(['bash', str(CLI.parent / 'provision.sh')], env=env,
                                capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not on the host', result.stderr)

    def test_build_failure_never_publishes(self):
        self.run_cli('build', 'builder', ok=False, FAIL='file push')
        self.assertFalse(any(c[0] in ('publish', 'delete') for c in self.recorded()))

    def test_build_stops_before_publish(self):
        self.run_cli('build', 'builder')
        calls = self.recorded()
        self.assertLess(calls.index(['stop', 'builder']), calls.index(['publish', 'builder', '--alias', 'agent-dev']))

    def test_readiness_timeout(self):
        self.run_cli('create', 'demo', ok=False, FAIL='exec demo', AGENT_VM_WAIT='1')
        self.assertFalse(any(c[0] == 'snapshot' for c in self.recorded()))

    def test_each_service_required_for_start_reset_and_create(self):
        for command in ('start', 'reset', 'create'):
            for service in ('docker', 'ssh'):
                with self.subTest(command=command, service=service):
                    self.calls.unlink(missing_ok=True)
                    args = [command, 'demo'] + (['--yes'] if command == 'reset' else [])
                    result = self.run_cli(*args, ok=False, FAIL_SERVICE=service, AGENT_VM_WAIT='1')
                    self.assertIn('readiness timed out', result.stderr)
                    if command == 'create':
                        self.assertFalse(any(c[0] == 'snapshot' for c in self.recorded()))

    def test_create_requires_services_after_final_restart(self):
        for service in ('docker', 'ssh'):
            with self.subTest(service=service):
                self.calls.unlink(missing_ok=True)
                result = self.run_cli('create', 'demo', ok=False, FAIL_SERVICE=service,
                                      FAIL_AFTER_RESTART='1', AGENT_VM_WAIT='1')
                self.assertIn(['snapshot', 'create', 'demo', 'baseline', '--no-expiry'], self.recorded())
                self.assertIn(['start', 'demo'], self.recorded())
                self.assertIn('readiness timed out', result.stderr)
                self.assertNotIn('Ready:', result.stdout)

    def test_security_key_public_keys(self):
        def wire_string(value):
            return struct.pack('>I', len(value)) + value

        # Build valid public-key wire formats without requiring a FIDO device.
        # ECDSA needs a real curve point; obtain one from a throwaway software key.
        ecdsa = self.root / 'ecdsa'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ecdsa', '-b', '256', '-N', '', '-f', str(ecdsa)], check=True)
        blob = base64.b64decode(Path(str(ecdsa) + '.pub').read_text().split()[1])
        type_length = struct.unpack('>I', blob[:4])[0]
        curve_and_point = blob[4 + type_length:]
        for key_type, fields in (
            ('sk-ssh-ed25519@openssh.com', wire_string(bytes(range(32)))),
            ('sk-ecdsa-sha2-nistp256@openssh.com', curve_and_point),
        ):
            with self.subTest(key_type=key_type):
                self.calls.unlink(missing_ok=True)
                blob = wire_string(key_type.encode()) + fields + wire_string(b'ssh:')
                key = self.root / 'security key.pub'
                key.write_text(f'{key_type} {base64.b64encode(blob).decode()} test-key\n')
                self.run_cli('create', 'demo', str(key))
                self.assertIn(['file', 'push', str(key), 'demo/home/dev/.ssh/authorized_keys',
                               '--uid', '1000', '--gid', '1000', '--mode', '0600'], self.recorded())

    def test_public_key_path_with_spaces(self):
        key = self.root / 'key with spaces'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        self.run_cli('create', 'demo', str(key) + '.pub')
        self.assertIn(['file', 'push', str(key) + '.pub', 'demo/home/dev/.ssh/authorized_keys',
                       '--uid', '1000', '--gid', '1000', '--mode', '0600'], self.recorded())
        self.calls.unlink()
        self.run_cli('create', 'demo', str(key), ok=False)
        self.assertEqual(self.recorded(), [])

    def test_build_uses_build_disk(self):
        for env, size in (({}, '20GiB'), ({'AGENT_VM_BUILD_DISK': '30GiB'}, '30GiB')):
            with self.subTest(size=size):
                self.calls.unlink(missing_ok=True)
                self.run_cli('build', 'builder', **env)
                self.assertIn(f'root,size={size}', self.recorded()[1])
        self.calls.unlink()
        self.run_cli('create', 'demo', AGENT_VM_BUILD_DISK='30GiB')
        self.assertIn('root,size=60GiB', self.recorded()[0])

    def test_build_exec_non_interactive(self):
        self.run_cli('build', 'builder')
        provision = [c for c in self.recorded() if c[0] == 'exec' and '/root/provision.sh' in c]
        self.assertEqual(len(provision), 1)
        for value in ('--mode', 'non-interactive', 'CI=1', 'DEV_CONTAINERS_PROVISION=1'):
            self.assertIn(value, provision[0])

    def test_start_when_running_is_noop(self):
        result = self.run_cli('start', 'demo')
        self.assertIn('already running', result.stdout)
        self.assertNotIn(['start', 'demo'], self.recorded())

    def test_start_when_stopped_starts(self):
        self.run_cli('start', 'demo', STATE='STOPPED')
        self.assertIn(['start', 'demo'], self.recorded())

    def test_stop_when_stopped_is_noop(self):
        result = self.run_cli('stop', 'demo', STATE='STOPPED')
        self.assertIn('already stopped', result.stdout)
        self.assertNotIn(['stop', 'demo'], self.recorded())

    def test_enter_stopped_fails_fast(self):
        start = time.monotonic()
        result = self.run_cli('enter', 'demo', ok=False, STATE='STOPPED')
        self.assertLess(time.monotonic() - start, 15)
        self.assertIn('agent-vm start demo', result.stderr)
        self.assertFalse(any(c[0] == 'exec' for c in self.recorded()))

    def test_enter_uses_setpriv_in_workspace(self):
        self.run_cli('enter', 'demo')
        last = self.recorded()[-1]
        self.assertEqual(last, ['exec', 'demo', '--cwd', '/home/dev/workspace', '--', 'setpriv',
                                '--reuid=1000', '--regid=1000', '--init-groups', '--reset-env', 'bash', '--login'])
        self.assertNotIn('--user', last)

    def test_reset_preserves_run_state(self):
        result = self.run_cli('reset', 'demo', '--yes')
        calls = self.recorded()
        restore = calls.index(['snapshot', 'restore', 'demo', 'baseline'])
        self.assertLess(calls.index(['stop', 'demo', '--timeout', '60']), restore)
        self.assertLess(restore, calls.index(['start', 'demo']))
        self.assertIn('seed demo', result.stderr)
        self.calls.unlink()
        result = self.run_cli('reset', 'demo', '--yes', STATE='STOPPED')
        calls = self.recorded()
        self.assertIn(['snapshot', 'restore', 'demo', 'baseline'], calls)
        self.assertFalse(any(c[0] in ('stop', 'start') for c in calls))
        self.assertIn('left stopped', result.stdout)
        self.assertIn('seed demo', result.stderr)

    def test_missing_instance(self):
        for command in ('start', 'enter', 'seed'):
            with self.subTest(command=command):
                self.calls.unlink(missing_ok=True)
                result = self.run_cli(command, 'demo', ok=False, STATE='')
                self.assertIn('cannot query demo (does it exist?)', result.stderr)
                self.assertFalse(any(c[0] in ('start', 'exec', 'file') for c in self.recorded()))

    def test_ip(self):
        self.assertEqual(self.run_cli('ip', 'demo').stdout, '10.20.30.42\n')
        self.assertIn('no IPv4', self.run_cli('ip', 'demo', ok=False, ROUTE='').stderr)
        self.calls.unlink()
        result = self.run_cli('ip', 'demo', ok=False, STATE='STOPPED')
        self.assertIn('agent-vm start demo', result.stderr)
        self.assertFalse(any(c[0] == 'exec' for c in self.recorded()))

    def pushes(self):
        return [c for c in self.recorded() if c[:2] == ['file', 'push']]

    def touch(self, rel, text='x'):
        path = self.home / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_seed_pushes_existing_allowlisted_files(self):
        files = {'.claude/.credentials.json': '.claude/.credentials.json', '.claude/CLAUDE.md': '.claude/CLAUDE.md',
                 '.claude/RTK.md': '.claude/RTK.md', '.codex/auth.json': '.codex/auth.json',
                 '.config/dev-containers/.env': '.config/dev-containers/.env',
                 '.config/dev-containers/github': '.ssh/github'}
        for rel in files:
            self.touch(rel)
        result = self.run_cli('seed', 'demo')
        calls, pushes = self.recorded(), self.pushes()
        self.assertEqual(len(pushes), len(files))
        for rel, dest in files.items():
            self.assertIn(['file', 'push', str(self.home / rel), f'demo/home/dev/{dest}',
                           '--uid', '1000', '--gid', '1000', '--mode', '0600'], pushes)
        mkdir = next(i for i, c in enumerate(calls) if c[0] == 'exec' and 'install' in c)
        self.assertIn('/home/dev/.ssh', calls[mkdir])
        self.assertLess(mkdir, calls.index(pushes[0]))
        self.assertIn('skipped', result.stderr)
        self.assertIn('.gemini/oauth_creds.json', result.stderr)

    def test_seed_ignores_unlisted(self):
        for rel in ('.claude/history.jsonl', '.ssh/id_ed25519', '.claude/projects/x.md'):
            self.touch(rel)
        (self.home / '.codex/auth.json').mkdir(parents=True)
        self.run_cli('seed', 'demo')
        self.assertEqual(self.pushes(), [])

    def test_seed_resolves_symlinks(self):
        target = self.root / 'dotfiles' / 'gitconfig'
        target.parent.mkdir()
        target.write_text('[user]\n')
        (self.home / '.gitconfig').symlink_to(target)
        self.run_cli('seed', 'demo')
        self.assertEqual(self.pushes(), [['file', 'push', str(target), 'demo/home/dev/.gitconfig',
                                          '--uid', '1000', '--gid', '1000', '--mode', '0600']])

    def test_seed_requires_running(self):
        self.touch('.gitconfig')
        result = self.run_cli('seed', 'demo', ok=False, STATE='STOPPED')
        self.assertIn('agent-vm start demo', result.stderr)
        self.assertEqual(self.pushes(), [])

    def test_create_never_seeds(self):
        self.touch('.claude/.credentials.json')
        self.touch('.gitconfig')
        key = self.root / 'key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
        self.run_cli('create', 'demo', str(key) + '.pub')
        self.assertEqual([c[3] for c in self.pushes()], ['demo/home/dev/.ssh/authorized_keys'])

    def test_provision_static_guards(self):
        text = (CLI.parent / 'provision.sh').read_text()
        self.assertLess(text.index('getent hosts deb.debian.org'), text.index('apt-get update'))
        for needle in ('visudo -cf', 'install -m 0440', '/var/lib/systemd/linger/dev'):
            self.assertIn(needle, text)
        self.assertNotIn('truncate -s 0 /etc/hostname', text)
        self.assertNotRegex(text, r'set -a[^\n]*\n[^\n]*\.env')

    def test_ssh_config_no_agent_forwarding(self):
        output = self.run_cli('ssh-config', 'demo').stdout
        self.assertIn('ProxyCommand incus exec demo -- nc 127.0.0.1 22', output)
        self.assertIn('ForwardAgent no', output)


    def test_reset_forces_stop_when_graceful_stop_fails(self):
        self.run_cli('reset', 'demo', '--yes', FAIL_EXACT=json.dumps(['stop', 'demo', '--timeout', '60']))
        calls = self.recorded()
        self.assertLess(calls.index(['stop', 'demo', '--force']), calls.index(['snapshot', 'restore', 'demo', 'baseline']))

    def test_reset_finds_baseline_among_snapshots(self):
        self.run_cli('reset', 'demo', '--yes', SNAPSHOTS='snap0 baseline')
        self.assertIn(['snapshot', 'restore', 'demo', 'baseline'], self.recorded())

    def test_provision_dev_owns_local(self):
        text = (CLI.parent / 'provision.sh').read_text()
        self.assertIn('install -d -o dev -g dev /home/dev/.local /home/dev/.local/bin', text)


if __name__ == '__main__':
    unittest.main()
