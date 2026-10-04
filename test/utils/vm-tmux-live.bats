#!/usr/bin/env bats
# ci: manual

@test "disposable session VM preserves guest tmux through handoff pause and managed save" {
    [[ -n ${HERDR_VM_TEST_BASE:-} ]] || skip "set HERDR_VM_TEST_BASE to a trusted qdistro BIOS qcow2 base with QGA"
    [[ -f $HERDR_VM_TEST_BASE ]] || skip "VM base does not exist"
    export OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export PYTHONPATH="$OPT_JAN/usr/lib"
    for command in virsh qemu-img ssh ssh-keygen passt; do
        command -v "$command" >/dev/null || skip "$command is required"
    done
    run python3 "$OPT_JAN/test/fixtures/vm-tmux-live.py"
    echo "$output"
    [ "$status" -eq 0 ]
}
