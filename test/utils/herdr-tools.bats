#!/usr/bin/env bats
# ci: fixture

setup() {
    OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export OPT_JAN
    chmod 700 "$BATS_TEST_TMPDIR"
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export PYTHONPATH="$OPT_JAN/usr/lib"
    export HERDR_SOCKET_PATH="$BATS_TEST_TMPDIR/herdr.sock" HERDR_ENV=1 HERDR_PANE_ID=w1:p1
    export TRANSPORT_FIXTURE="$BATS_TEST_TMPDIR"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$XDG_CONFIG_HOME/herdr-layout/vms"
    chmod 700 "$XDG_CONFIG_HOME/herdr-layout" "$XDG_CONFIG_HOME/herdr-layout/vms"
    ln -s "$OPT_JAN/test/fixtures/herdr-tools-transport.py" "$BATS_TEST_TMPDIR/bin/virsh"
    ln -s "$OPT_JAN/test/fixtures/herdr-tools-transport.py" "$BATS_TEST_TMPDIR/bin/ssh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    printf '%s' running > "$BATS_TEST_TMPDIR/vm-state"
    python3 "$OPT_JAN/test/fixtures/herdr-tools-server.py" "$BATS_TEST_TMPDIR" &
    FIXTURE_PID=$!
    for _ in {1..100}; do
        [[ -e "$BATS_TEST_TMPDIR/ready" && -e "$BATS_TEST_TMPDIR/port" ]] && break
        sleep 0.02
    done
    python3 - <<'PY'
import os
from pathlib import Path
from herdr_tools.common import atomic_json, config_dir
root = Path(os.environ['BATS_TEST_TMPDIR'])
for name in ['key', 'known_hosts']:
    path = root / name
    path.touch(mode=0o600)
atomic_json(config_dir() / 'vms/dev.json', {
    'schema_version': 1, 'domain_uuid': '12345678-1234-4234-8234-123456789abc',
    'libvirt_uri': 'qemu:///session', 'ssh_host': '127.0.0.1',
    'ssh_port': int((root/'port').read_text()), 'ssh_user': 'worker',
    'ssh_host_key_alias': 'dev-incarnation-one', 'ssh_identity_file': str(root/'key'),
    'ssh_known_hosts_file': str(root/'known_hosts'), 'tmux_session': 'main', 'agent': 'codex'
})
PY
}

teardown() {
    kill "$FIXTURE_PID"
    wait "$FIXTURE_PID" 2>/dev/null || true
}

make_mapping() {
    python3 - <<'PY'
import os
from herdr_tools.common import Herdr, atomic_json, mapping_path
record={'schema_version':1,'id':'mapping-one','argv':['printf','%s','literal $(touch forbidden)'],
        'cwd':os.environ['BATS_TEST_TMPDIR'],'env':{'HERDR_AGENT':'codex'},'agent':'codex','kind':'local'}
atomic_json(mapping_path(record['id']),record)
Herdr().call('fixture.bind',id=record['id'])
PY
}

save_fixture() {
    make_mapping
    "$OPT_JAN/usr/bin/herdr-layout" save --file "$BATS_TEST_TMPDIR/layout.json"
}

empty_fixture() {
    python3 -c 'from herdr_tools.common import Herdr; Herdr().call("fixture.empty")'
}

@test "utilities work through deployment symlinks and expose help" {
    for command in herdr-run herdr-layout vm-tmux; do
        ln -s "$OPT_JAN/usr/bin/$command" "$BATS_TEST_TMPDIR/bin/$command"
        run "$BATS_TEST_TMPDIR/bin/$command" --help
        [ "$status" -eq 0 ]
    done
}

@test "Bash detector recognizes SSH and vm-tmux, leaving ordinary commands alone" {
    run bash "$OPT_JAN/usr/share/herdr-layout/agent-env" ssh -t devbox codex
    [ "$status" -eq 0 ]
    [ "$output" = HERDR_AGENT=codex ]
    run bash "$OPT_JAN/usr/share/herdr-layout/agent-env" vm-tmux attach dev --session claude
    [ "$output" = HERDR_AGENT=claude ]
    run bash "$OPT_JAN/usr/share/herdr-layout/agent-env" nano /some/file
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "herdr-run records exact arguments, cwd and explicit environment without executing labels" {
    export INHERITED_SECRET=do-not-save
    run "$OPT_JAN/usr/bin/herdr-run" --env TEST_VALUE=literal python3 -c 'import os,sys; print(os.environ["TEST_VALUE"]); print(sys.argv[1])' '$(touch forbidden)'
    [ "$status" -eq 0 ]
    [[ "$output" == *'$(touch forbidden)'* ]]
    [ ! -e forbidden ]
    python3 - <<'PY'
import json,os
from herdr_tools.common import state_dir
record=json.loads(next((state_dir()/'mappings').glob('*.json')).read_text())
assert record['argv'][-1]=='$(touch forbidden)'
assert record['env']=={'TEST_VALUE':'literal'}
assert record['cwd']==os.getcwd()
PY
}

@test "herdr-run requires calling pane context and rejects stale Herdr env overrides" {
    run env -u HERDR_PANE_ID "$OPT_JAN/usr/bin/herdr-run" true
    [ "$status" -ne 0 ]
    [[ "$output" == *'inside a Herdr pane'* ]]
    run "$OPT_JAN/usr/bin/herdr-run" --env HERDR_PANE_ID=other true
    [ "$status" -ne 0 ]
    [[ "$output" == *'caller context'* ]]
}

@test "detector output is parsed as data and never evaluated" {
    cat > "$XDG_CONFIG_HOME/herdr-layout/agent-env" <<'SH'
printf '%s\n' 'HERDR_AGENT=codex; touch forbidden'
SH
    chmod 600 "$XDG_CONFIG_HOME/herdr-layout/agent-env"
    run "$OPT_JAN/usr/bin/herdr-run" true
    [ "$status" -ne 0 ]
    [[ "$output" == *'must output nothing or one'* ]]
    [ ! -e forbidden ]
}

@test "agent none overrides detector and VM profile fallback" {
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/herdr-run" --agent none vm-tmux attach dev --menu-first'
    [ "$status" -eq 0 ]
    python3 - <<'PY'
import json
from herdr_tools.common import state_dir
record=json.loads(next((state_dir()/'mappings').glob('*.json')).read_text())
assert record['agent']=='none' and 'HERDR_AGENT' not in record['env']
PY
    [ ! -e "$BATS_TEST_TMPDIR/transport.jsonl" ]
}

@test "layout captures mappings and excludes inherited or exported arbitrary commands" {
    save_fixture
    python3 - <<'PY'
import json,os
from pathlib import Path
saved=json.loads((Path(os.environ['BATS_TEST_TMPDIR'])/'layout.json').read_text())
leaf=saved['workspaces'][0]['tabs'][0]['root']
assert leaf['mapping']=='mapping-one' and 'command' not in leaf and 'env' not in leaf
assert 'SECRET' not in str(saved)
assert saved['mappings']['mapping-one']['env']=={'HERDR_AGENT':'codex'}
assert (Path(os.environ['BATS_TEST_TMPDIR'])/'layout.json').stat().st_mode & 0o777 == 0o600
PY
}

@test "failed capture preserves the previous valid snapshot" {
    save_fixture
    cp "$BATS_TEST_TMPDIR/layout.json" "$BATS_TEST_TMPDIR/expected.json"
    printf '%s' layout.export > "$BATS_TEST_TMPDIR/fail"
    run "$OPT_JAN/usr/bin/herdr-layout" save --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/expected.json" "$BATS_TEST_TMPDIR/layout.json"
}

@test "restore refuses to duplicate an existing native/source layout" {
    save_fixture
    run "$OPT_JAN/usr/bin/herdr-layout" restore --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'avoid duplicates'* ]]
}

@test "restore replays wrappers, is repeatable, and leaves explicit env to the child" {
    save_fixture
    empty_fixture
    # Emulate a fresh server identity, independently of source capture.
    python3 - <<'PY'
import json,os
from pathlib import Path
p=Path(os.environ['BATS_TEST_TMPDIR'])/'layout.json'
s=json.loads(p.read_text());s['source_instance']='previous-server';p.write_text(json.dumps(s))
PY
    run "$OPT_JAN/usr/bin/herdr-layout" restore --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -eq 0 ]
    run "$OPT_JAN/usr/bin/herdr-layout" restore --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *'already restored'* ]]
    python3 - <<'PY'
import json,os
from pathlib import Path
root=Path(os.environ['BATS_TEST_TMPDIR'])
requests=[json.loads(x) for x in (root/'requests.jsonl').read_text().splitlines()]
applies=[x for x in requests if x['method']=='layout.apply']
assert len(applies)==1
leaf=applies[0]['params']['root']
assert leaf['command'][1:]==['--restore-mapping','mapping-one']
assert leaf['env']=={}
PY
}

@test "restore launcher rebinds saved identity and does not rerun changed detection" {
    make_mapping
    printf '%s\n' 'exit 99' > "$XDG_CONFIG_HOME/herdr-layout/agent-env"
    chmod 600 "$XDG_CONFIG_HOME/herdr-layout/agent-env"
    run "$OPT_JAN/usr/bin/herdr-run" --restore-mapping mapping-one
    [ "$status" -eq 0 ]
    [ "$output" = 'literal $(touch forbidden)' ]
    python3 - <<'PY'
import json,os
from pathlib import Path
requests=[json.loads(x) for x in (Path(os.environ['BATS_TEST_TMPDIR'])/'requests.jsonl').read_text().splitlines()]
assert any(r['params'].get('tokens',{}).get('herdr_mapping')=='mapping-one' for r in requests)
PY
}

@test "uncertain restore refuses replay and blocks capture publication" {
    save_fixture
    python3 - <<'PY'
import os
from pathlib import Path
from herdr_tools.common import Herdr,atomic_json,read_json,state_dir
from herdr_tools.layout import journal_path
s=read_json(Path(os.environ['BATS_TEST_TMPDIR'])/'layout.json')
atomic_json(journal_path(Herdr()),{'generation':s['generation'],'instance':Herdr().instance(),
                                    'status':'restoring','pending':'create tab'})
PY
    run "$OPT_JAN/usr/bin/herdr-layout" restore --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'uncertain object'* ]]
    run "$OPT_JAN/usr/bin/herdr-layout" save --file "$BATS_TEST_TMPDIR/layout.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'incomplete'* ]]
}

@test "VM menu-first does not query libvirt or start a guest" {
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/vm-tmux" attach dev --menu-first'
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/transport.jsonl" ]
}

@test "paused and saved guests use distinct lifecycle transitions" {
    for state in paused saved; do
        printf '%s' "$state" > "$BATS_TEST_TMPDIR/vm-state"
        run bash -c 'printf "s\nq\n" | "$OPT_JAN/usr/bin/vm-tmux" attach dev --menu-first'
        [ "$status" -eq 0 ]
    done
    python3 - <<'PY'
import json,os
from pathlib import Path
rows=[json.loads(x) for x in (Path(os.environ['BATS_TEST_TMPDIR'])/'transport.jsonl').read_text().splitlines()]
transitions=[r['argv'][2] for r in rows if r['tool']=='virsh' and r['argv'][2] in ['start','resume']]
assert transitions==['resume','start']
PY
}

@test "attachment quotes hostile socket paths and scopes agent hint to interactive SSH" {
    python3 - <<'PY'
from herdr_tools.common import config_dir,read_json,atomic_json
p=config_dir()/'vms/dev.json';s=read_json(p);s['tmux_socket']='/tmp/a; touch forbidden';atomic_json(p,s)
PY
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/vm-tmux" attach dev --session code --reclaim'
    [ "$status" -eq 0 ]
    [ ! -e forbidden ]
    python3 - <<'PY'
import json,os
from pathlib import Path
rows=[json.loads(x) for x in (Path(os.environ['BATS_TEST_TMPDIR'])/'transport.jsonl').read_text().splitlines()]
ssh=[r for r in rows if r['tool']=='ssh']
assert len(ssh)==2
assert ssh[0]['agent'] is None and ssh[1]['agent']=='codex'
assert ssh[1]['remote']==['exec','tmux','-S','/tmp/a; touch forbidden','attach-session','-d','-t','=code']
assert 'StrictHostKeyChecking=yes' in ssh[1]['argv'] and 'ForwardAgent=no' in ssh[1]['argv']
PY
}

@test "missing tmux session and wrong host identity do not replay or recreate workloads" {
    touch "$BATS_TEST_TMPDIR/missing-session"
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/vm-tmux" attach dev'
    [ "$status" -eq 0 ]
    [[ "$output" == *'missing: main (not recreated)'* ]]
    touch "$BATS_TEST_TMPDIR/ssh-fail"
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/vm-tmux" attach dev'
    [[ "$output" == *'transport/authentication failed'* ]]
    ! rg 'new-session|StrictHostKeyChecking=no' "$BATS_TEST_TMPDIR/transport.jsonl"
}

@test "new maps successful creation to attachment and restored VM stays menu-first" {
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/herdr-run" vm-tmux new dev --session coding --cwd /home/worker/project -- nano "name with spaces"'
    [ "$status" -eq 0 ]
    python3 - <<'PY'
import json,os
from pathlib import Path
from herdr_tools.common import state_dir
record=json.loads(next((state_dir()/'mappings').glob('*.json')).read_text())
assert record['vm']['operation']=='attach' and record['vm']['command']==[]
assert record['argv'][1]=='attach' and record['vm']['session']=='coding'
rows=[json.loads(x) for x in (Path(os.environ['BATS_TEST_TMPDIR'])/'transport.jsonl').read_text().splitlines()]
create=next(r for r in rows if 'new-session' in r['remote'])
assert create['remote'][-3:]==['--','nano','name with spaces']
(Path(os.environ['BATS_TEST_TMPDIR'])/'mapping-id').write_text(record['id'])
PY
    rm "$BATS_TEST_TMPDIR/transport.jsonl"
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/herdr-run" --restore-mapping "$(cat "$BATS_TEST_TMPDIR/mapping-id")"'
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/transport.jsonl" ]
}

@test "saved VM mapping refuses profile identity replacement" {
    run bash -c 'printf "q\n" | "$OPT_JAN/usr/bin/herdr-run" vm-tmux attach dev --menu-first'
    [ "$status" -eq 0 ]
    python3 - <<'PY'
from herdr_tools.common import config_dir,read_json,atomic_json
p=config_dir()/'vms/dev.json';s=read_json(p);s['domain_uuid']='87654321-1234-4234-8234-123456789abc';atomic_json(p,s)
PY
    run python3 - <<'PY'
from herdr_tools.common import state_dir,read_json
from herdr_tools.vm import checked_profile
record=read_json(next((state_dir()/'mappings').glob('*.json')))
checked_profile(record['vm'])
PY
    [ "$status" -ne 0 ]
    [[ "$output" == *'explicitly remap'* ]]
}

@test "cold recovery retries preserve newly started work and mapping conflicts leave no replacement plan" {
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-regressions.py" \
        Regressions.test_interrupted_recovery_rechecks_remaining_tabs \
        Regressions.test_mapping_conflict_does_not_publish_replacement_plan \
        Regressions.test_command_starting_during_guard_is_preserved
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "SSH control timeouts return to menu and creation timeouts do not retry" {
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-regressions.py" \
        Regressions.test_ssh_timeout_returns_to_menu_and_creation_is_uncertain
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "saving during VM creation sees only immutable completed attachment mappings" {
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-regressions.py" \
        Regressions.test_save_during_creation_exposes_only_final_attachment
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "open probes server liveness and only starts absent or refused listeners" {
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-regressions.py" \
        Regressions.test_server_probe_waits_for_api_and_preserves_live_or_inaccessible_servers
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "autosave preserves unchanged generations and refuses incomplete restores or replacement servers" {
    run python3 "$OPT_JAN/test/fixtures/herdr-tools-regressions.py" \
        Regressions.test_autosave_preserves_generation_and_guards_publication
    echo "$output"
    [ "$status" -eq 0 ]
}
