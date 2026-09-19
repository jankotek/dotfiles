#!/usr/bin/env bats
#
# Fixture-only checks for setup/bootstrap. No root, no VM, no package manager
# and no Ansible: the supervisor's argument parser, pipeline-status selection
# and guard-ownership logic are extracted from the real script and exercised
# against stubs, so a regression in any of them fails in CI.
#
#   OPT_JAN="$PWD" bats test/utils/bootstrap-supervisor.bats

load ../helpers

BOOTSTRAP="${OPT_JAN:-/opt/jan}/setup/bootstrap"

setup() {
    WORK="$BATS_TEST_TMPDIR"
    mkdir -p "$WORK/bin"
}

# --- argument parser -------------------------------------------------------

parser_lib() {
    local lib="$WORK/parser.sh"
    sed -n '/^valid_tag_name() {/,/^}$/p;/^valid_tag_list() {/,/^}$/p;/^parse_supervisor_args() {/,/^}$/p' \
        "$BOOTSTRAP" > "$lib"
    grep -q '^parse_supervisor_args()' "$lib" || {
        echo "could not extract parse_supervisor_args from $BOOTSTRAP" >&2
        return 1
    }
    echo "$lib"
}

# Prints "<check-mode>|<forwarded args, comma separated>" or "reject|".
parse() {
    local lib
    lib=$(parser_lib) || return 1
    (
        # shellcheck source=/dev/null
        source "$lib"
        if parse_supervisor_args "$@" >/dev/null 2>&1; then
            printf '%s|%s' "$JAN_BOOTSTRAP_CHECK_MODE" \
                "$(IFS=,; printf '%s' "${JAN_BOOTSTRAP_PLAYBOOK_ARGS[*]:-}")"
        else
            printf 'reject|'
        fi
    )
}

@test "parser: no arguments is a real run with nothing forwarded" {
    [[ "$(parse)" == "0|" ]]
}

@test "parser: --check and -C both select check mode" {
    [[ "$(parse --check)" == "1|--check" ]]
    [[ "$(parse -C)" == "1|--check" ]]
}

@test "parser: --diff and -D are forwarded without selecting check mode" {
    [[ "$(parse --diff)" == "0|--diff" ]]
    [[ "$(parse -D)" == "0|--diff" ]]
}

@test "parser: check and diff combine" {
    [[ "$(parse --check --diff)" == "1|--check,--diff" ]]
    [[ "$(parse -C -D)" == "1|--check,--diff" ]]
}

@test "parser: verbosity flags are forwarded verbatim" {
    [[ "$(parse -v)" == "0|-v" ]]
    [[ "$(parse -vv)" == "0|-vv" ]]
    [[ "$(parse -vvv)" == "0|-vvv" ]]
}

@test "parser: tag lists are normalised to the long form" {
    [[ "$(parse --tags xdg)" == "0|--tags,xdg" ]]
    [[ "$(parse -t xdg)" == "0|--tags,xdg" ]]
    [[ "$(parse --tags=xdg)" == "0|--tags,xdg" ]]
    [[ "$(parse --tags xdg,units)" == "0|--tags,xdg,units" ]]
    [[ "$(parse --skip-tags laptop_power)" == "0|--skip-tags,laptop_power" ]]
}

@test "parser: flags combine in one invocation" {
    [[ "$(parse --check --tags xdg -v)" == "1|--check,--tags,xdg,-v" ]]
}

@test "parser: clustered short options are rejected, never silently split" {
    # -CD would ask ansible-playbook for check mode while leaving the
    # supervisor in real mode, which is how the guard got acquired during a
    # purported preview.
    [[ "$(parse -CD)" == "reject|" ]]
    [[ "$(parse -DC)" == "reject|" ]]
    [[ "$(parse -vvC)" == "reject|" ]]
}

@test "parser: unsupported ansible-playbook options are rejected" {
    [[ "$(parse -e foo=1)" == "reject|" ]]
    [[ "$(parse --limit lab-vm)" == "reject|" ]]
    [[ "$(parse --extra-vars=x=1)" == "reject|" ]]
    [[ "$(parse --)" == "reject|" ]]
    [[ "$(parse -vvvv)" == "reject|" ]]
}

@test "parser: positional arguments are rejected" {
    [[ "$(parse pilot.yml)" == "reject|" ]]
    [[ "$(parse /etc/passwd)" == "reject|" ]]
}

@test "parser: a tag option must not swallow the next option as its value" {
    [[ "$(parse --tags --check)" == "reject|" ]]
    [[ "$(parse --tags=--check)" == "reject|" ]]
    [[ "$(parse -t -D)" == "reject|" ]]
    [[ "$(parse --skip-tags --diff)" == "reject|" ]]
}

@test "parser: empty and malformed tag lists are rejected" {
    [[ "$(parse --tags)" == "reject|" ]]
    [[ "$(parse --tags '')" == "reject|" ]]
    [[ "$(parse --tags=)" == "reject|" ]]
    [[ "$(parse --tags ,)" == "reject|" ]]
    [[ "$(parse --tags ,,)" == "reject|" ]]
    [[ "$(parse --tags xdg,)" == "reject|" ]]
    [[ "$(parse --tags ,xdg)" == "reject|" ]]
    [[ "$(parse --tags xdg,,units)" == "reject|" ]]
}

@test "parser: shell punctuation in a tag list is rejected" {
    [[ "$(parse --tags 'xdg;rm -rf /')" == "reject|" ]]
    [[ "$(parse --tags 'xdg$(id)')" == "reject|" ]]
    [[ "$(parse --tags 'xdg units')" == "reject|" ]]
}

# --- pipeline status -------------------------------------------------------

pipeline_runner() {
    local runner="$WORK/runner.sh"
    {
        echo '#!/bin/bash'
        echo 'set -Eeuo pipefail'
        # The real ERR trap must be installed: `set +e` does not disable it,
        # and without it this fixture cannot see the defect it guards against.
        sed -n '/^error_trap() {/,/^}$/p' "$BOOTSTRAP"
        echo 'trap error_trap ERR'
        echo 'limit_host=lab-vm; profile=pilot; log_file=/dev/null'
        echo 'playbook_args=()'
        sed -n '/^run_playbook() {/,/^}$/p' "$BOOTSTRAP"
        echo 'run_playbook || exit "$?"'
    } > "$runner"
    chmod +x "$runner"
    grep -q 'PIPESTATUS' "$runner" || {
        echo "could not extract run_playbook from $BOOTSTRAP" >&2
        return 1
    }
    printf '#!/bin/bash\necho play output\nexit "${FAKE_PLAY_RC:-0}"\n' > "$WORK/bin/ansible-playbook"
    printf '#!/bin/bash\ncat >/dev/null\nexit "${FAKE_TEE_RC:-0}"\n' > "$WORK/bin/tee"
    chmod +x "$WORK/bin/ansible-playbook" "$WORK/bin/tee"
    echo "$runner"
}

run_pipeline() { # run_pipeline <play rc> <tee rc>; prints the resulting status
    local runner
    runner=$(pipeline_runner) || return 1
    PATH="$WORK/bin:$PATH" FAKE_PLAY_RC="$1" FAKE_TEE_RC="$2" "$runner" >/dev/null 2>&1
    echo $?
}

@test "pipeline: a failing play wins over a failing logger" {
    # The ERR trap used to fire on the pipeline and exit with tee's status
    # before PIPESTATUS could be read.
    [[ "$(run_pipeline 7 1)" == "7" ]]
}

@test "pipeline: a failing play propagates its own status" {
    [[ "$(run_pipeline 7 0)" == "7" ]]
    [[ "$(run_pipeline 2 0)" == "2" ]]
}

@test "pipeline: a logging failure surfaces only when the play succeeded" {
    [[ "$(run_pipeline 0 1)" != "0" ]]
}

@test "pipeline: success is success" {
    [[ "$(run_pipeline 0 0)" == "0" ]]
}

# --- guard ownership -------------------------------------------------------

guard_runner() {
    local runner="$WORK/guard.sh"
    {
        echo '#!/bin/bash'
        echo 'set -Eeuo pipefail'
        echo 'guard_token='
        echo 'inherited_guard=0'
        sed -n '/^acquire_or_verify_guard() {/,/^}$/p' "$BOOTSTRAP"
        sed -n '/^restore_guest_agent() {/,/^}$/p' "$BOOTSTRAP"
        sed -n '/^release_guard() {/,/^}$/p' "$BOOTSTRAP"
        echo 'trap release_guard EXIT'
        echo 'acquire_or_verify_guard'
        echo 'echo "TOKEN=${guard_token:-}"'
        echo 'echo "INHERITED=$inherited_guard"'
    } > "$runner"
    # The guard binary is addressed absolutely on purpose, so point the copy at
    # a stub instead of relying on PATH.
    sed -i "s#/usr/local/sbin/qga-guard#$WORK/bin/qga-guard#g" "$runner"
    chmod +x "$runner"
    grep -q 'acquire_or_verify_guard()' "$runner" || {
        echo "could not extract the guard functions from $BOOTSTRAP" >&2
        return 1
    }
    cat > "$WORK/bin/qga-guard" <<STUB
#!/bin/bash
echo "qga-guard \$*" >> "$WORK/calls"
case "\$1" in
    acquire) echo "4242-99" ;;
    verify)  exit "\${FAKE_VERIFY_RC:-0}" ;;
esac
STUB
    printf '#!/bin/bash\necho "systemctl $*" >> "%s"\n' "$WORK/calls" > "$WORK/bin/systemctl"
    chmod +x "$WORK/bin/qga-guard" "$WORK/bin/systemctl"
    : > "$WORK/calls"
    echo "$runner"
}

@test "guard: with no inherited token the supervisor acquires and releases" {
    local runner
    runner=$(guard_runner)
    PATH="$WORK/bin:$PATH" run env -u JAN_QGA_GUARD_TOKEN "$runner"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"TOKEN=4242-99"* ]]
    [[ "$output" == *"INHERITED=0"* ]]
    grep -q '^qga-guard acquire ' "$WORK/calls"
    grep -q '^qga-guard release 4242-99$' "$WORK/calls"
    # Only the owner restores the agent.
    grep -q '^systemctl enable qemu-guest-agent.service$' "$WORK/calls"
    grep -q '^systemctl start qemu-guest-agent.service$' "$WORK/calls"
}

@test "guard: an inherited token is verified and never acquired or released" {
    local runner
    runner=$(guard_runner)
    PATH="$WORK/bin:$PATH" JAN_QGA_GUARD_TOKEN=1234-56 run "$runner"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"TOKEN="* ]]
    [[ "$output" != *"TOKEN=4242-99"* ]]
    [[ "$output" == *"INHERITED=1"* ]]
    grep -q '^qga-guard verify 1234-56$' "$WORK/calls"
    ! grep -q '^qga-guard acquire' "$WORK/calls"
    ! grep -q '^qga-guard release' "$WORK/calls"
    # The outer owner restores the agent, not this run.
    ! grep -q 'qemu-guest-agent' "$WORK/calls"
}

@test "guard: a stale inherited token aborts before any work" {
    local runner
    runner=$(guard_runner)
    PATH="$WORK/bin:$PATH" JAN_QGA_GUARD_TOKEN=1234-56 FAKE_VERIFY_RC=1 run "$runner"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not a live lease"* ]]
    ! grep -q '^qga-guard acquire' "$WORK/calls"
    ! grep -q 'qemu-guest-agent' "$WORK/calls"
}

# --- supported profiles ----------------------------------------------------

@test "every accepted profile has a playbook, and vm-helpers is the VM one" {
    local profile
    for profile in pilot vm-helpers; do
        assert_file "$OPT_JAN/ansible/$profile.yml"
        assert_file_contains "$OPT_JAN/setup/bootstrap" "$profile"
    done
}
