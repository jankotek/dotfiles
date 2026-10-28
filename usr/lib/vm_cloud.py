"""Verified Debian/Ubuntu cloud boot inputs for the common golden-image pipeline."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import tomllib
from urllib.parse import urlparse

from herdr_tools.common import ToolError, atomic_json, private, read_json
from vm_bootstrap import BOOTSTRAP, SEAL
from vm_image import digest, run, customize_script

FIELDS = {'distro', 'version', 'arch', 'build_id', 'image_url', 'image_digest',
          'checksum_url', 'checksum_algorithm', 'provenance', 'signature_url',
          'key_file', 'signing_fingerprint'}


def load_config(path):
    with path.open('rb') as stream:
        config = tomllib.load(stream)
    if set(config) != FIELDS or not all(isinstance(value, str) for value in config.values()):
        raise ToolError('Unexpected or missing cloud configuration fields')
    if config['distro'] not in ('debian', 'ubuntu') or config['arch'] != platform.machine():
        raise ToolError('Unsupported cloud distribution or architecture')
    if config['version'] != {'debian': '13', 'ubuntu': '26.04'}[config['distro']]:
        raise ToolError('Unsupported cloud release')
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', config['build_id']):
        raise ToolError('Invalid cloud build ID')
    if config['checksum_algorithm'] not in ('sha256', 'sha512'):
        raise ToolError('Unsupported checksum algorithm')
    size = hashlib.new(config['checksum_algorithm']).digest_size * 2
    if not re.fullmatch('[0-9a-f]{' + str(size) + '}', config['image_digest']):
        raise ToolError('Invalid pinned cloud digest')
    for field in ('image_url', 'checksum_url', 'signature_url'):
        if field == 'signature_url' and not config[field]:
            continue
        url = urlparse(config[field])
        if url.scheme != 'https' or not url.netloc or url.query or url.fragment or url.username:
            raise ToolError('Cloud URLs must use HTTPS without credentials/query/fragment')
    if config['distro'] == 'debian':
        if config['provenance'] != 'https-pinned-checksum' or any(config[name] for name in ('signature_url', 'key_file', 'signing_fingerprint')):
            raise ToolError('Debian cloud provenance must explicitly use HTTPS and a pinned checksum')
    elif (config['provenance'] != 'publisher-signed-checksum' or not config['signature_url']
          or not re.fullmatch(r'[A-F0-9]{40}', config['signing_fingerprint'])
          or not config['key_file'] or Path(config['key_file']).name != config['key_file']):
        raise ToolError('Ubuntu cloud input requires its pinned signing key and signature')
    return config


def verify_input(image, checksums, signature, key, config):
    if config['provenance'] == 'publisher-signed-checksum':
        with tempfile.TemporaryDirectory(prefix='vm-cloud-gpg-') as temporary:
            home = Path(temporary)
            shown = run(['gpg', '--homedir', str(home), '--batch', '--show-keys', '--with-colons', str(key)])
            fingerprints = [line.split(':')[9] for line in shown.splitlines() if line.startswith('fpr:')]
            if not fingerprints or fingerprints[0] != config['signing_fingerprint']:
                raise ToolError('Cloud signing-key fingerprint mismatch')
            keyring = home / 'keyring.gpg'
            run(['gpg', '--homedir', str(home), '--batch', '--dearmor', '--output', str(keyring), str(key)])
            status = run(['gpgv', '--homedir', str(home), '--status-fd', '1', '--keyring', str(keyring), str(signature), str(checksums)])
            valid = [line.split() for line in status.splitlines() if line.startswith('[GNUPG:] VALIDSIG ')]
            if not any(config['signing_fingerprint'] in (line[2], line[-1]) for line in valid):
                raise ToolError('Cloud checksum signature does not match the pinned publisher key')
    basename = Path(urlparse(config['image_url']).path).name
    entries = [fields[0].lower() for line in checksums.read_text().splitlines()
               if len(fields := line.split()) == 2 and fields[1].lstrip('*') == basename]
    with image.open('rb') as stream:
        actual = hashlib.file_digest(stream, config['checksum_algorithm']).hexdigest()
    if entries != [config['image_digest']] or actual != config['image_digest']:
        raise ToolError('Cloud image, checksum artifact name, and configured pin do not agree')


def download(config, cache, key):
    directory = cache / config['image_digest']
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(directory)
    image, checksums, signature = [directory / name for name in ('cloud.qcow2', 'checksums', 'checksums.sig')]
    with (directory / 'download.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if image.exists() and checksums.exists() and (not config['signature_url'] or signature.exists()):
            verify_input(image, checksums, signature, key, config)
            return image
        with tempfile.TemporaryDirectory(prefix='download-', dir=directory) as temporary:
            stage = Path(temporary)
            for target, url in ((image, config['image_url']), (checksums, config['checksum_url']),
                                (signature, config['signature_url'])):
                if not url:
                    continue
                print('Downloading ' + config['distro'] + ' cloud ' + target.name, flush=True)
                if target == image:
                    run(['aria2c', '--continue=true', '--allow-overwrite=true', '--auto-file-renaming=false',
                         '--file-allocation=none', '--max-connection-per-server=4', '--split=4',
                         '--max-tries=5', '--retry-wait=2', '--summary-interval=0', '--console-log-level=warn',
                         '--show-console-readout=false',
                         '--dir=' + str(stage), '--out=' + target.name, url], timeout=1800)
                else:
                    run(['curl', '--fail', '--location', '--silent', '--show-error', '--proto', '=https',
                         '--proto-redir', '=https', '--retry', '4', '--retry-all-errors', '--retry-max-time', '180',
                         '--output', str(stage / target.name), url], timeout=1800)
            verify_input(stage / image.name, stage / checksums.name, stage / signature.name, key, config)
            for target in (image, checksums, signature):
                if (stage / target.name).exists():
                    os.replace(stage / target.name, target)
        return image


def build_boot(distro, output_dir=None, cache_dir=None, config_path=None):
    share = Path(__file__).resolve().parents[1] / 'share/vm-image'
    config_path = config_path or share / (distro + '.toml')
    config = load_config(config_path)
    if config['distro'] != distro:
        raise ToolError('Cloud config does not match the requested distribution')
    key = share / config['key_file'] if config['key_file'] else None
    for tool in ('curl', 'aria2c', 'qemu-img', 'guestfish', 'virt-cat', 'virt-resize', 'virt-customize', 'gpg', 'gpgv'):
        if not shutil.which(tool):
            raise ToolError('Required cloud-image tool missing: ' + tool)
    output_dir = output_dir or Path.home() / '.local/share/libvirt/images/dotfiles-cloud'
    cache_dir = cache_dir or Path.home() / '.cache/dotfiles/vm-images'
    output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    private(output_dir)
    recipe = hashlib.sha256(Path(__file__).read_bytes() + Path(__file__).with_name("vm_image.py").read_bytes() + BOOTSTRAP.encode() + SEAL.encode() + config_path.read_bytes()
                            + (key.read_bytes() if key else b'')).hexdigest()
    destination = output_dir / f"{distro}-{config['version']}-{recipe[:12]}.qcow2"
    manifest = destination.with_suffix('.manifest.json')
    with (output_dir / f'.{distro}.build.lock').open('a') as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        if destination.exists():
            recorded = read_json(manifest)
            if recorded.get('recipe_sha256') != recipe or recorded.get('image_sha256') != digest(destination):
                raise ToolError('Existing immutable boot image does not match its manifest')
            return destination
        cloud = download(config, cache_dir, key)
        info = json.loads(run(['qemu-img', 'info', '--output=json', str(cloud)]))
        if info['format'] != 'qcow2' or info.get('backing-filename'):
            raise ToolError('Verified cloud input must be standalone qcow2')
        release = run(['virt-cat', '-a', str(cloud), '/etc/os-release'])
        for field, value in (('ID', distro), ('VERSION_ID', config['version'])):
            if not re.search(r'^' + field + r'="?' + re.escape(value) + r'"?$', release, re.M):
                raise ToolError('Cloud release does not match its configured OS/version')
        roots = run(['guestfish', '--ro', '-a', str(cloud), '-i', 'inspect-get-roots']).splitlines()
        if len(roots) != 1 or not re.fullmatch(r'/dev/[a-z]+[0-9]+', roots[0]):
            raise ToolError('Expected one plain cloud root partition')
        with tempfile.TemporaryDirectory(prefix='boot-', dir=output_dir) as temporary:
            stage = Path(temporary)
            candidate = stage / 'boot.qcow2'
            run(['qemu-img', 'create', '-f', 'qcow2', str(candidate), '25G'])
            run(['virt-resize', '--quiet', '--no-extra-partition', '--expand', roots[0], str(cloud), str(candidate)])
            recipe_script = stage / 'bootstrap.sh'
            recipe_script.write_text(BOOTSTRAP)
            print('Preparing ' + distro + ' boot prerequisites in libguestfs', flush=True)
            customize_script(candidate, recipe_script, resolve_dns=True)
            # Identity is removed after all package/initramfs work, offline.
            seal = stage / 'seal.sh'
            seal.write_text(SEAL)
            customize_script(candidate, seal)
            run(['qemu-img', 'check', str(candidate)])
            record = {'schema_version': 1, 'builder': 'dotfiles/usr/bin/vm-image-build',
                      'source': 'original-' + distro + '-cloud', 'config': config,
                      'verification': config['provenance'], 'recipe_sha256': recipe,
                      'image_sha256': digest(candidate)}
            os.chmod(candidate, 0o444)
            atomic_json(manifest, record)
            os.rename(candidate, destination)
        return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--distro', choices=('debian', 'ubuntu'), required=True)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--cache-dir', type=Path)
    args = parser.parse_args()
    print(build_boot(args.distro, args.output_dir, args.cache_dir, args.config), flush=True)
