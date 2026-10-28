#!/usr/bin/env bats
# ci: fixture

setup() {
    export PROBE_DIR="$BATS_TEST_TMPDIR/probe"
    mkdir -p "$PROBE_DIR/bin"
    cat > "$PROBE_DIR/bin/virsh" <<'PY'
#!/usr/bin/python3
import base64, json, os, pathlib, subprocess, sys
root=pathlib.Path(os.environ['PROBE_DIR'])
request=json.loads(sys.argv[-1])
if request['execute']=='guest-exec':
    if os.environ.get('PROBE_ERROR')=='start':
        print(json.dumps({'error':{'desc':'fixture failure'}})); sys.exit(0)
    result=subprocess.run([request['arguments']['path'],*request['arguments']['arg']], capture_output=True)
    status={'exited': True, 'exitcode': result.returncode,
            'out-data':base64.b64encode(result.stdout).decode(),
            'err-data':base64.b64encode(result.stderr).decode()}
    if os.environ.get('PROBE_SIGNAL'):
        status.pop('exitcode'); status['signal']=15
    if os.environ.get('PROBE_BASE64'):
        status['out-data']='errorAAA'
    (root/'status.json').write_text(json.dumps({'return':status}))
    print(json.dumps({'return':{'pid':123}}))  # Deliberate JSON whitespace.
else:
    if os.environ.get('PROBE_ERROR')=='status':
        print(json.dumps({'error':{'desc':'fixture status error'}}))
    elif os.environ.get('PROBE_INVALID'):
        print('{"return":{"exited":true}}')
    else:
        print((root/'status.json').read_text())
PY
    printf '#!/bin/sh\nexit 0\n' > "$PROBE_DIR/bin/sleep"
    chmod +x "$PROBE_DIR/bin/"*
}

exec_guest() {
    run env PATH="$PROBE_DIR/bin:/usr/bin:/bin" "$OPT_JAN/usr/bin/vm-exec" test --argv "$@"
}

@test "argv preserves empty arguments, hostile syntax, UTF-8 and trailing newlines" {
    exec_guest python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' \
        '' '$(touch /unwanted)' '"quotes"' 'žluťoučký' $'last\n\n'
    [[ $status == 0 ]]
    [[ $output == '["", "$(touch /unwanted)", "\"quotes\"", "\u017elu\u0165ou\u010dk\u00fd", "last\n\n"]' ]]
}

@test "exit code and stderr are preserved" {
    exec_guest sh -c 'echo failure >&2; exit 7'
    [[ $status == 7 ]]
    [[ $output == *failure* ]]
}

@test "successful binary output containing base64 error is not a QGA error" {
    export PROBE_BASE64=1
    # Keep binary bytes outside Bats command substitution.
    run bash -c 'PATH="$1/bin:/usr/bin:/bin" "$2/usr/bin/vm-exec" test --argv true > "$1/output"' _ "$PROBE_DIR" "$OPT_JAN"
    [[ $status == 0 ]]
    [[ $(base64 -w0 "$PROBE_DIR/output") == errorAAA ]]
}

@test "signal completion returns 128 plus the signal instead of polling forever" {
    export PROBE_SIGNAL=1
    exec_guest true
    [[ $status == 143 ]]
}

@test "actual QGA errors fail at start and after bounded status retries" {
    export PROBE_ERROR=start
    exec_guest true
    [[ $status == 1 && $output == *'Failed to start command'* ]]
    export PROBE_ERROR=status
    exec_guest true
    [[ $status == 1 && $output == *'Guest agent returned error'* ]]
}

@test "malformed completion is rejected" {
    export PROBE_INVALID=1
    exec_guest true
    [[ $status == 1 && $output == *'Invalid guest exit status'* ]]
}
