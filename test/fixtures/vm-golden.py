"""Offline regression checks for immutable recipe inputs and disposable domains."""
import os
from pathlib import Path
import tempfile
import subprocess
import hashlib
import tomllib
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from herdr_tools.common import ToolError
from vm_golden import (BUILDER_INPUTS, CHECK, Guest, checkout_digest, domain_xml,
                       recipe_fingerprints, wait_provision)
from vm_disks import LAYOUT, clone_bundle, read_bundle
from vm_cloud import load_config, verify_input


class GoldenTests(unittest.TestCase):
    def test_unexpected_compiler_aborts_clone_validation(self):
        stubs = r'''systemctl() { if [[ $1 == get-default ]]; then echo multi-user.target; elif [[ $* == *display-manager* ]]; then return 3; fi; }
ip() { echo default; }
getent() { return 0; }
command() { return 0; }
'''
        result = subprocess.run(['bash', '-euc', stubs + CHECK], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unexpected GUI/compiler tool: go', result.stderr)

    def test_each_required_service_must_be_active(self):
        stubs = r'''systemctl() { if [[ $1 == get-default ]]; then echo multi-user.target; elif [[ $* == *display-manager* || $* == *qemu-guest-agent* ]]; then return 3; fi; }
'''
        result = subprocess.run(['bash', '-euc', stubs + CHECK], capture_output=True, text=True)
        self.assertEqual(result.returncode, 3)

    def test_recipe_tracks_dirty_untracked_and_linked_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ('setup', 'skel', 'usr', 'agent/skills'):
                (root / name).mkdir(parents=True)
            script = root / 'setup/vm-cli'
            script.write_text('first')
            initial = checkout_digest(root)
            script.write_text('dirty change')
            self.assertNotEqual(initial, checkout_digest(root))
            initial = checkout_digest(root)
            (root / 'setup/untracked').write_text('new input')
            self.assertNotEqual(initial, checkout_digest(root))
            initial = checkout_digest(root)
            (root / 'skel/skill').symlink_to('../setup', target_is_directory=True)
            self.assertNotEqual(initial, checkout_digest(root))
            initial = checkout_digest(root)
            script.chmod(0o700)
            self.assertNotEqual(initial, checkout_digest(root))

    def test_other_checkout_recipe_tracks_the_executing_builder_helpers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, library = root / 'guest-checkout', root / 'builder/usr/lib'
            (repo / 'setup').mkdir(parents=True)
            (repo / 'setup/vm-cli').write_text('guest provisioning')
            for name in BUILDER_INPUTS:
                path = library / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('original builder input')
            with patch('vm_golden.__file__', str(library / 'vm_golden.py')):
                initial = recipe_fingerprints(repo, 'a' * 64)
                for name in BUILDER_INPUTS:
                    with self.subTest(module=name):
                        path = library / name
                        path.write_text('changed executing builder input')
                        changed = recipe_fingerprints(repo, 'a' * 64)
                        self.assertEqual(initial[0], changed[0])
                        self.assertNotEqual(initial[1], changed[1])
                        self.assertNotEqual(initial[2], changed[2])
                        path.write_text('original builder input')

    def test_domain_escapes_mounts_and_enforces_readonly_on_host(self):
        xml = ET.fromstring(domain_xml('123', Path('/disk<&.qcow2'), Path('/checkout<&'), 24000))
        self.assertEqual(xml.find('devices/filesystem/source').get('dir'), '/checkout<&')
        self.assertIsNotNone(xml.find('devices/filesystem/readonly'))
        self.assertEqual(xml.find('devices/disk/driver').get('discard'), 'unmap')
        self.assertIsNone(xml.find('devices/graphics'))
        self.assertEqual(xml.find('devices/interface/portForward').get('address'), '127.0.0.1')
        desktop = ET.fromstring(domain_xml('123', Path('/disk'), Path('/repo'), 24000, desktop=True))
        self.assertIsNotNone(desktop.find('devices/video'))

    def test_three_disks_and_host_share_identity_are_explicit(self):
        disks = {name: Path('/images') / (name + '.qcow2') for name in LAYOUT}
        xml = ET.fromstring(domain_xml('123', disks, Path('/checkout'), 24000,
                                      host_opt=Path('/opt'), host_docs=Path('/private/docs')))
        self.assertEqual({disk.find('target').get('dev'): disk.find('source').get('file')
                          for disk in xml.findall('devices/disk')},
                         {'vda': '/images/root.qcow2', 'vdb': '/images/home.qcow2', 'vdc': '/images/swap.qcow2'})
        shares = {fs.find('target').get('dir'): fs for fs in xml.findall('devices/filesystem')}
        self.assertIsNotNone(shares['host-opt'].find('readonly'))
        self.assertIsNone(shares['host-docs'].find('readonly'))
        self.assertEqual(shares['host-docs'].find('idmap/uid').get('start'), '1000')
        self.assertEqual(shares['host-docs'].find('idmap/uid').get('target'), str(os.getuid()))

    def test_clones_get_fresh_swap_instead_of_inheriting_old_pages(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            disks = {name: Path('/parents') / (name + '.qcow2') for name in LAYOUT}
            with patch('vm_disks.run') as run, patch('vm_disks.create_swap') as swap:
                clones = clone_bundle(disks, root, 'test')
            self.assertEqual(run.call_count, 2)
            swap.assert_called_once_with(clones['swap'])
            self.assertTrue(all('-b' in call.args[0] for call in run.call_args_list))

    def test_bundle_rejects_disk_paths_outside_its_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record = {'schema_version': 2, 'disks': {name: {'file': '../outside'} for name in LAYOUT}}
            with patch('vm_disks.read_json', return_value=record), self.assertRaisesRegex(ToolError, 'filename'):
                read_bundle(root)

    def test_unsigned_debian_inputs_still_require_exact_pin_and_artifact_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / 'cloud.qcow2'
            image.write_bytes(b'checked cloud bytes')
            checksums = root / 'checksums'
            pin = hashlib.sha512(image.read_bytes()).hexdigest()
            config = {'provenance': 'https-pinned-checksum', 'checksum_algorithm': 'sha512',
                      'image_url': 'https://cloud.debian.org/cloud.qcow2', 'image_digest': pin}
            checksums.write_text(pin + '  cloud.qcow2\n')
            verify_input(image, checksums, None, None, config)
            image.write_bytes(b'changed disk')
            with self.assertRaisesRegex(ToolError, 'do not agree'):
                verify_input(image, checksums, None, None, config)
            image.write_bytes(b'checked cloud bytes')
            checksums.write_text(pin + '  different.qcow2\n')
            with self.assertRaisesRegex(ToolError, 'do not agree'):
                verify_input(image, checksums, None, None, config)

    def test_debian_config_cannot_claim_nonexistent_publisher_signatures(self):
        source = Path(os.environ['OPT_JAN']) / 'usr/share/vm-image/debian.toml'
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / 'config.toml'
            config.write_text(source.read_text().replace('https-pinned-checksum', 'publisher-signed-checksum'))
            with self.assertRaisesRegex(ToolError, 'Debian cloud provenance'):
                load_config(config)
            config.write_text(source.read_text().replace('https://', 'http://'))
            with self.assertRaisesRegex(ToolError, 'HTTPS'):
                load_config(config)

    def test_cleanup_never_touches_an_undefined_guest(self):
        guest = Guest(Path('/disk'), Path('/repo'), Path('/tmp'))
        with patch.object(guest, 'virsh') as virsh:
            guest.cleanup()
            virsh.assert_not_called()

    def test_cleanup_targets_only_the_allocated_uuid(self):
        guest = Guest(Path('/disk'), Path('/repo'), Path('/tmp'))
        guest.defined = True
        with patch.object(guest, 'virsh', side_effect=['running', '', '']) as virsh:
            guest.cleanup()
        self.assertEqual([c.args for c in virsh.call_args_list], [
            ('domstate', guest.identifier), ('destroy', guest.identifier), ('undefine', guest.identifier)])

    def test_failed_provisioning_is_not_retried_as_transport_loss(self):
        class Failed:
            def exec(self, command):
                return 'ActiveState=failed\nResult=exit-code\nExecMainStatus=7' if 'systemctl' in command else 'specific failure'
        with self.assertRaisesRegex(ToolError, 'specific failure'), patch('vm_golden.time.sleep') as sleep:
            wait_provision(Failed(), Path('/unused'))
        sleep.assert_not_called()

    def test_successful_transport_recovery_retains_complete_log(self):
        with tempfile.TemporaryDirectory() as temporary:
            guest = Guest(Path('/disk'), Path('/repo'), Path(temporary))
            log = Path(temporary) / 'log'
            with patch.object(guest, 'exec', side_effect=[ToolError('restart'),
                              'ActiveState=active\nResult=success\nExecMainStatus=0', 'complete log']), \
                 patch('vm_golden.time.sleep'):
                wait_provision(guest, log)
            self.assertEqual(log.read_text(), 'complete log')


if __name__ == '__main__':
    unittest.main()
