"""Promote only a verified golden image's disposable clone; never mutate the base."""
import os
from pathlib import Path
import tempfile
import time

from herdr_tools.common import read_json
from vm_golden import Guest, wait_provision
from vm_disks import read_bundle, clone_bundle
from vm_image import digest, run

repo = Path(os.environ['OPT_JAN']).resolve()
base = Path(os.environ['GOLDEN_TEST_BASE']).resolve(strict=True)
manifest, parents = read_bundle(base)
root = Path(tempfile.mkdtemp(prefix='workstation-test-', dir=base.parent))
disks = clone_bundle(parents, root, 'workstation')
guest = Guest(disks, repo, root, desktop=True)
success = False
try:
    guest.start()
    original = guest.exec('cat /etc/machine-id; cat /etc/ssh/ssh_host_ed25519_key.pub')
    guest.exec("printf preserved > /home/jan/workstation-sentinel; "
               "cat > /etc/systemd/system/golden-provision.service <<'UNIT'\n"
               "[Service]\nType=oneshot\nRemainAfterExit=yes\nTimeoutStartSec=1800\n"
               "ExecStart=/opt/jan/setup/vm-workstation jan\n"
               "StandardOutput=append:/var/log/golden-provision.log\n"
               "StandardError=append:/var/log/golden-provision.log\nUNIT\n"
               "systemctl daemon-reload; systemctl start --no-block golden-provision.service")
    wait_provision(guest, root / 'provision.log')
    guest.stop()
    guest.virsh('start', guest.identifier)
    run([str(repo / 'usr/bin/vm-wait'), guest.identifier], timeout=180)
    deadline = time.monotonic() + 120
    while True:
        try:
            guest.exec('pgrep -u jan xfce4-panel; pgrep -u jan xfdesktop')
            break
        except Exception:
            if time.monotonic() > deadline:
                print(guest.exec('journalctl -b -u lightdm -u display-manager --no-pager -n 70'), flush=True)
                print(guest.exec('lightdm --show-config; for log in /var/log/lightdm/*.log; do '
                                 'test -f "$log" || continue; printf "\\n%s\\n" "$log"; tail -n 60 "$log"; done'), flush=True)
                raise
            time.sleep(2)
    if manifest.get('distro') in ('debian', 'ubuntu'):
        # Exercise the autologin greeter after logout, beyond initial startup.
        session = guest.exec('pgrep -u jan -x xfce4-session')
        guest.exec('kill -TERM "$(pgrep -u jan -x xfce4-session)"')
        deadline = time.monotonic() + 120
        while True:
            try:
                replacement = guest.exec('pgrep -u jan -x xfce4-session')
                if replacement == session:
                    raise RuntimeError('Original XFCE session is still exiting')
                guest.exec('pgrep -u jan xfce4-panel; pgrep -u jan xfdesktop')
                break
            except Exception:
                if time.monotonic() > deadline:
                    print(guest.exec('tail -n 80 /var/log/lightdm/lightdm.log'), flush=True)
                    raise
                time.sleep(2)
    assert original == guest.exec('cat /etc/machine-id; cat /etc/ssh/ssh_host_ed25519_key.pub')
    guest.exec('test "$(cat /home/jan/workstation-sentinel)" = preserved; '
               'test "$(systemctl get-default)" = graphical.target; '
               'systemctl is-active --quiet lightdm; test -e /usr/local/bin/vm-exec; '
               'test "$(blockdev --getsize64 "$(findmnt -n -o SOURCE --target /)")" = 4294967296; '
               'test "$(blockdev --getsize64 /dev/vdb1)" = 6442450944; '
               'if command -v go; then exit 1; fi')
    print('PASS: XFCE/LightDM autologin, original identity and workspace, no Go compiler', flush=True)
    guest.stop()
    assert all(digest(path) == manifest['disks'][role]['sha256'] for role, path in parents.items())
    success = True
finally:
    guest.cleanup()
    if success:
        for disk in disks.values():
            disk.unlink(missing_ok=True)
    else:
        print('Workstation failure diagnostics retained in ' + str(root), flush=True)
