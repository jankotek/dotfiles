#!/usr/bin/env bats
# ci: fixture

setup() {
    export CLONE_FIXTURE="$BATS_TEST_TMPDIR/clone"
    export IMAGES_DIR="$CLONE_FIXTURE/images" BASE_VM=base KEEP=0
    export BASE_DISK="$CLONE_FIXTURE/base & disk.qcow2"
    mkdir -p "$CLONE_FIXTURE/bin" "$IMAGES_DIR"
    touch "$BASE_DISK"
    cat > "$CLONE_FIXTURE/bin/virsh" <<'PY'
#!/usr/bin/python3
import json, os, pathlib, sys
root=pathlib.Path(os.environ['CLONE_FIXTURE']); args=sys.argv[3:]; op=args[0]
with (root/'calls').open('a') as log: log.write(json.dumps(args)+'\n')
domain=root/'domain.xml'
if op=='dominfo': sys.exit(0 if os.environ.get('COLLISION') or domain.exists() else 1)
elif op=='domstate': print('running' if args[1]!='base' and os.environ.get('FAIL_DESTROY') else os.environ.get('BASE_STATE','shut off'))
elif op=='dumpxml':
    if args[1]=='base':
        import xml.etree.ElementTree as E
        node=E.Element('domain'); E.SubElement(node,'name').text='base'
        devices=E.SubElement(node,'devices'); disk=E.SubElement(devices,'disk',device='disk')
        E.SubElement(disk,'source',file=os.environ['BASE_DISK'])
        print(E.tostring(node,encoding='unicode'))
    else: print(domain.read_text())
elif op=='domuuid': print('changed' if os.environ.get('CHANGED_UUID') else '12345678-1234-1234-1234-123456789012')
elif op=='define': domain.write_text(sys.stdin.read())
elif op=='destroy': sys.exit(1 if os.environ.get('FAIL_DESTROY') else 0)
elif op=='undefine':
    if os.environ.get('FAIL_UNDEFINE'): sys.exit(1)
    domain.unlink()
elif op=='list':
    if os.environ.get('FOREIGN_STORAGE'): print('foreign-domain')
else: sys.exit(1)
PY
    cat > "$CLONE_FIXTURE/bin/qemu-img" <<'SH'
#!/bin/bash
touch "${!#}"
SH
    cat > "$CLONE_FIXTURE/bin/virt-clone" <<'PY'
#!/usr/bin/python3
import os, sys, xml.etree.ElementTree as E
args=sys.argv[1:]; disk=args[args.index('--file')+1]; nvram=args[args.index('--nvram')+1]
root=E.Element('domain'); E.SubElement(root,'uuid').text='12345678-1234-1234-1234-123456789012'
devices=E.SubElement(root,'devices'); node=E.SubElement(devices,'disk',device='disk')
E.SubElement(node,'source',file=disk)
if os.environ.get('SHARED_NVRAM'):
    E.SubElement(E.SubElement(root,'os'),'nvram').text='/base/nvram.fd'
print(E.tostring(root,encoding='unicode'))
PY
    chmod +x "$CLONE_FIXTURE/bin/"*
}

clone_run() {
    run env PATH="$CLONE_FIXTURE/bin:/usr/bin:/bin" bash -c '
        set -euo pipefail
        source "$1/test/lib/vm-clone.bash"
        init_test_clone fixture
        printf "%s" "$VM_WORK_DIR" > "$CLONE_FIXTURE/workdir"
        prepare_test_clone
        define_test_clone
        "$2"
    ' _ "$OPT_JAN" "${1:-true}"
}

@test "missing base disk cleans only the owned workspace" {
    rm "$BASE_DISK"
    clone_run
    [[ $status -ne 0 ]]
    [[ $output == *'missing base disk'* ]]
    run grep -E 'destroy|undefine' "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
    [[ ! -d $(cat "$CLONE_FIXTURE/workdir") ]]
}

@test "name collision never destroys or undefines the existing VM" {
    export COLLISION=1
    clone_run
    [[ $status -ne 0 && $output == *'already exists'* ]]
    run grep -E 'destroy|undefine' "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
}

@test "successful cleanup removes only the recorded clone identity" {
    clone_run
    [[ $status == 0 ]]
    grep -q 'destroy.*12345678-1234-1234-1234-123456789012' "$CLONE_FIXTURE/calls"
    [[ ! -d $(cat "$CLONE_FIXTURE/workdir") ]]
}

@test "a changed domain identity retains the disk and does not destroy it" {
    export CHANGED_UUID=1
    clone_run
    [[ $status -ne 0 && $output == *'identity changed'* ]]
    [[ -f $(cat "$CLONE_FIXTURE/workdir")/root.qcow2 ]]
    run grep -E 'destroy|undefine' "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
}

@test "failed undefinition retains storage still referenced by the clone" {
    export FAIL_UNDEFINE=1
    clone_run
    [[ $status -ne 0 && $output == *'could not undefine'* ]]
    [[ -f $(cat "$CLONE_FIXTURE/workdir")/root.qcow2 ]]
}

@test "shared firmware-variable paths are rejected before definition" {
    export SHARED_NVRAM=1
    clone_run
    [[ $status -ne 0 && $output == *'shared NVRAM'* ]]
    [[ ! -e $CLONE_FIXTURE/domain.xml ]]
}

@test "running base VM is rejected without stopping it" {
    export BASE_STATE=running
    clone_run
    [[ $status -ne 0 && $output == *'base VM must be shut off'* ]]
    run grep -E 'destroy|undefine|shutdown' "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
}

@test "storage shared by another domain is retained before any destructive cleanup" {
    export FOREIGN_STORAGE=1
    clone_run
    [[ $status -ne 0 && $output == *'exclusive storage ownership'* ]]
    [[ -f $(cat "$CLONE_FIXTURE/workdir")/root.qcow2 ]]
    run grep -E 'destroy|undefine' "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
}

@test "a VM that could not be stopped is never undefined or stripped of its disk" {
    export FAIL_DESTROY=1
    clone_run
    [[ $status -ne 0 && $output == *'did not stop'* ]]
    [[ -f $(cat "$CLONE_FIXTURE/workdir")/root.qcow2 ]]
    run grep undefine "$CLONE_FIXTURE/calls"
    [[ $status == 1 ]]
}
