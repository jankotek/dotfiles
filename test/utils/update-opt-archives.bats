#!/usr/bin/env bats
# ci: fixture
# Verify archive upgrades preserve working installs when a later step fails.

setup() {
    export JAN_OPT="$BATS_TEST_TMPDIR/opt"
    export FIXTURE_DIR="$BATS_TEST_TMPDIR/fixtures"
    export FIXTURE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$JAN_OPT" "$FIXTURE_DIR" "$FIXTURE_BIN"
    python3 - "$FIXTURE_DIR" <<'PY'
import hashlib, pathlib, sys, tarfile, zipfile
root = pathlib.Path(sys.argv[1])
for tool, version, binary, suffix in (
    ('gradle', '9.0', 'gradle', '.zip'),
    ('maven', '3.9.11', 'mvn', '.tar.gz'),
    ('ffmpeg', 'latest', 'ffmpeg', '.tar.xz'),
):
    tree = root / f'{tool}-{version}'
    (tree / 'bin').mkdir(parents=True)
    for name in ([binary, 'ffplay', 'ffprobe'] if tool == 'ffmpeg' else [binary]):
        path = tree / 'bin' / name
        path.write_text(f'#!/bin/sh\necho new-{tool}\n')
        path.chmod(0o755)
    archive = root / (tool + suffix)
    if suffix == '.zip':
        with zipfile.ZipFile(archive, 'w') as bundle:
            for path in tree.rglob('*'):
                bundle.write(path, path.relative_to(root))
    else:
        with tarfile.open(archive, 'w:gz' if suffix == '.tar.gz' else 'w:xz') as bundle:
            bundle.add(tree, arcname=tree.name)
    digest = hashlib.sha512 if tool == 'maven' else hashlib.sha256
    (root / (tool + '.sum')).write_text(digest(archive.read_bytes()).hexdigest() + '\n')
PY
    cat > "$FIXTURE_BIN/curl" <<'SH'
#!/bin/bash
set -euo pipefail
case "${!#}" in
    *gradle/releases/latest) echo '{"tag_name": "v9.0"}' ;;
    *FFmpeg-Builds/releases/latest) echo '{"tag_name": "latest"}' ;;
    *gradle*.sha256) cat "$FIXTURE_DIR/gradle.sum" ;;
    *maven*.sha512) cat "$FIXTURE_DIR/maven.sum" ;;
    *checksums.sha256) printf '%s  ffmpeg-master-latest-linux64-gpl.tar.xz\n' "$(cat "$FIXTURE_DIR/ffmpeg.sum")" ;;
    */maven-3/) echo '<a href="3.9.11/">3.9.11</a>' ;;
    *) echo "unexpected URL: ${!#}" >&2; exit 1 ;;
esac
SH
    cat > "$FIXTURE_BIN/aria2c" <<'SH'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
    esac
done
echo download >> "$FIXTURE_DIR/downloads"
[[ ${FAIL_DOWNLOAD:-0} != 1 ]] || exit 1
case "${!#}" in
    *gradle*) archive=gradle.zip ;;
    *maven*) archive=maven.tar.gz ;;
    *ffmpeg*) archive=ffmpeg.tar.xz ;;
    *) exit 1 ;;
esac
cp "$FIXTURE_DIR/$archive" "$destination_dir/$destination_name"
SH
    cat > "$FIXTURE_BIN/mv" <<'SH'
#!/bin/bash
set -euo pipefail
if [[ ${FAIL_ACTIVATION:-0} == 1 && $# == 3 && $1 == -T && $2 == *'.staging.'* ]]; then
    echo 'injected activation failure' >&2
    exit 1
fi
exec /usr/bin/mv "$@"
SH
    chmod +x "$FIXTURE_BIN/"*
}

seed_old() {
    local tool=$1 binary=$1
    [[ $tool != maven ]] || binary=mvn
    mkdir -p "$JAN_OPT/$tool/bin" "$JAN_OPT/bin"
    printf '#!/bin/sh\necho old-%s\n' "$tool" > "$JAN_OPT/$tool/bin/$binary"
    chmod +x "$JAN_OPT/$tool/bin/$binary"
    echo old-version > "$JAN_OPT/$tool/.version"
    ln -s "$JAN_OPT/$tool/bin/$binary" "$JAN_OPT/bin/$binary"
}

update_tool() {
    run env PATH="$FIXTURE_BIN:/usr/bin:/bin" "$OPT_JAN/usr/sbin/optupdate" "$1"
}

assert_old_preserved() {
    local tool=$1 binary=$1
    [[ $tool != maven ]] || binary=mvn
    [[ $status -ne 0 ]]
    [[ $output != *'All software installed successfully!'* ]]
    [[ $("$JAN_OPT/bin/$binary") == "old-$tool" ]]
    [[ $(< "$JAN_OPT/$tool/.version") == old-version ]]
    local -a leftovers
    mapfile -t leftovers < <(find "$JAN_OPT" -maxdepth 1 -name '.jan-update-*.staging.*' -o -name '.jan-update-*.backup.*')
    [[ ${#leftovers[@]} == 0 ]]
}

@test "Gradle, Maven and FFmpeg upgrade and skip repeat archive downloads" {
    for tool in gradle maven ffmpeg; do
        seed_old "$tool"
        update_tool "$tool"
        [[ $status == 0 ]]
        local binary=$tool
        [[ $tool != maven ]] || binary=mvn
        [[ $("$JAN_OPT/bin/$binary") == "new-$tool" ]]
        local downloads
        downloads=$(wc -l < "$FIXTURE_DIR/downloads")
        update_tool "$tool"
        [[ $status == 0 ]]
        [[ $(wc -l < "$FIXTURE_DIR/downloads") == "$downloads" ]]
    done
    [[ -x $JAN_OPT/bin/ffplay && -x $JAN_OPT/bin/ffprobe ]]
}

@test "failed archive checksums preserve previous installs" {
    for tool in gradle maven ffmpeg; do
        seed_old "$tool"
        local length=64
        [[ $tool != maven ]] || length=128
        printf '%0*d\n' "$length" 0 > "$FIXTURE_DIR/$tool.sum"
        update_tool "$tool"
        [[ $output == *'Checksum mismatch'* ]]
        assert_old_preserved "$tool"
    done
}

@test "failed archive activation rolls back previous installs" {
    export FAIL_ACTIVATION=1
    for tool in gradle maven ffmpeg; do
        seed_old "$tool"
        update_tool "$tool"
        [[ $output == *'injected activation failure'* ]]
        assert_old_preserved "$tool"
    done
}

@test "failed archive downloads preserve previous installs" {
    export FAIL_DOWNLOAD=1
    for tool in gradle maven ffmpeg; do
        seed_old "$tool"
        update_tool "$tool"
        assert_old_preserved "$tool"
    done
}

@test "pgAdmin is no longer an optupdate download" {
    update_tool pgadmin
    [[ $status -ne 0 ]]
    [[ $output == *'Unknown tool: pgadmin'* ]]
    [[ ! -e $FIXTURE_DIR/downloads ]]
}
