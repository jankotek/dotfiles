#!/usr/bin/env bats
# ci: fixture

setup() {
    OPT_JAN=${OPT_JAN:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
    export OPT_JAN PYTHONPATH="$OPT_JAN/usr/lib"
    chmod 700 "$BATS_TEST_TMPDIR"
}

@test "image builder exposes help through a deployment symlink" {
    ln -s "$OPT_JAN/usr/bin/vm-image-build" "$BATS_TEST_TMPDIR/vm-image-build"
    run "$BATS_TEST_TMPDIR/vm-image-build" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'--output-dir'* ]]
}

@test "invalid image configuration is rejected before creating output" {
    cp "$OPT_JAN/usr/share/vm-image/tumbleweed.toml" "$BATS_TEST_TMPDIR/bad.toml"
    printf '\nunknown_field = "$(touch forbidden)"\n' >> "$BATS_TEST_TMPDIR/bad.toml"
    run "$OPT_JAN/usr/bin/vm-image-build" --config "$BATS_TEST_TMPDIR/bad.toml" --output-dir "$BATS_TEST_TMPDIR/images"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Unexpected or missing'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/images" ]
    [ ! -e forbidden ]
}

@test "expired snapshot cannot silently use rolling repositories" {
    sed 's/snapshot = "[0-9]*"/snapshot = "20200101"/' "$OPT_JAN/usr/share/vm-image/tumbleweed.toml" > "$BATS_TEST_TMPDIR/old.toml"
    run "$OPT_JAN/usr/bin/vm-image-build" --config "$BATS_TEST_TMPDIR/old.toml" --output-dir "$BATS_TEST_TMPDIR/images"
    [ "$status" -ne 0 ]
    [[ "$output" == *'no more than 14 days old'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/images" ]
}

@test "cloud verification rejects an unsigned image despite a matching checksum" {
    command -v gpg >/dev/null || skip "gpg required"
    command -v gpgv >/dev/null || skip "gpgv required"
    run python3 - <<'PY'
import hashlib,os
from pathlib import Path
from herdr_tools.common import ToolError
from vm_image import verify_cloud
root=Path(os.environ['BATS_TEST_TMPDIR'])
image=root/'image';image.write_bytes(b'Untrusted disk bytes')
checksum=root/'sha256';checksum.write_text(hashlib.sha256(image.read_bytes()).hexdigest()+'  cloud.qcow2\n')
signature=root/'signature';signature.write_text('not a signature')
key=Path(os.environ['OPT_JAN'])/'usr/share/vm-image/opensuse-tumbleweed-signing-key.asc'
config={'cloud_url':'https://example.invalid/cloud.qcow2',
        'cloud_sha256':hashlib.sha256(image.read_bytes()).hexdigest(),
        'signing_fingerprint':'AD485664E901B867051AB15F35A2F86E29B700A4'}
try:
    verify_cloud(image,checksum,signature,key,config)
except ToolError as error:
    assert 'gpgv failed' in str(error),error
else:
    raise AssertionError('Unsigned cloud image accepted')
PY
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "immutable base with changed bytes is rejected without downloading or overwriting" {
    run python3 - <<'PY'
import hashlib,os,re,sys
from datetime import datetime,timezone
from pathlib import Path
from unittest.mock import patch
from herdr_tools.common import ToolError,atomic_json
import vm_image
repo=Path(os.environ['OPT_JAN']);root=Path(os.environ['BATS_TEST_TMPDIR']);output=root/'images';output.mkdir(mode=0o700)
source=repo/'usr/share/vm-image/tumbleweed.toml';key=source.with_name('opensuse-tumbleweed-signing-key.asc')
snapshot=datetime.now(timezone.utc).strftime('%Y%m%d')
config=root/'current.toml'
config.write_text(re.sub(r'snapshot = "[0-9]+"',f'snapshot = "{snapshot}"',source.read_text()))
recipe=hashlib.sha256(Path(vm_image.__file__).read_bytes()+config.read_bytes()+key.read_bytes()).hexdigest()
base=output/f'baseweed-{snapshot}-{recipe[:12]}.qcow2';base.write_bytes(b'tampered disk')
atomic_json(base.with_suffix('.manifest.json'),{'recipe_sha256':recipe,'image_sha256':'0'*64})
with patch.object(sys,'argv',['vm-image-build','--config',str(config),'--output-dir',str(output)]), \
     patch.object(vm_image.shutil,'which',return_value='/tool'),patch.object(vm_image,'download_cloud') as download:
    try:
        vm_image.main()
    except ToolError as error:
        assert 'immutable image' in str(error),error
    else:
        raise AssertionError('Tampered base accepted')
    download.assert_not_called()
assert base.read_bytes()==b'tampered disk'
PY
    echo "$output"
    [ "$status" -eq 0 ]
}
