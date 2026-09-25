#!/usr/bin/env bats
# ci: fixture
# Offline regression tests for the complete Mjolnir release bundle.

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/mjolnir"
    export JAN_OPT="$TEST_ROOT/opt"
    export FIXTURE_DIR="$TEST_ROOT/fixture"
    export FIXTURE_BIN="$TEST_ROOT/bin"
    export FIXTURE_DOWNLOAD_LOG="$TEST_ROOT/downloads"
    local version=v9.8.7
    local platform=x86_64-unknown-linux-gnu
    local archive="brokk-mjolnir-${version}-${platform}.tar.gz"
    local root="$FIXTURE_DIR/brokk-mjolnir-${version}-${platform}"
    local binary

    mkdir -p "$JAN_OPT" "$root" "$FIXTURE_BIN"
    for binary in mj mj-desktop mj-voice-worker \
        mj-worker-x86_64-unknown-linux-musl \
        mj-worker-aarch64-unknown-linux-musl; do
        printf '#!/bin/sh\nprintf "Mjolnir fixture 9.8.7\\n"\n' > "$root/$binary"
        chmod 0755 "$root/$binary"
    done
    tar czf "$FIXTURE_DIR/$archive" -C "$FIXTURE_DIR" "${root##*/}"
    (cd "$FIXTURE_DIR" && sha256sum "$archive") > "$FIXTURE_DIR/$archive.sha256"

    cat > "$FIXTURE_DIR/release.json" <<'EOF'
{"tag_name":"v9.8.7"}
EOF
    cat > "$FIXTURE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
url=${!#}
case "$url" in
    *api.github.com/repos/BrokkAi/mjolnir/releases/latest) cat "$FIXTURE_DIR/release.json" ;;
    *.tar.gz.sha256) cat "$FIXTURE_DIR/${url##*/}" ;;
    *) echo "unexpected curl URL: $url" >&2; exit 1 ;;
esac
EOF
    cat > "$FIXTURE_BIN/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
url=${!#}
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
    esac
done
printf 'download\n' >> "$FIXTURE_DOWNLOAD_LOG"
cp "$FIXTURE_DIR/${url##*/}" "$destination_dir/$destination_name"
EOF
    chmod 0755 "$FIXTURE_BIN/curl" "$FIXTURE_BIN/aria2c"
}

run_mjolnir_update() {
    run env PATH="$FIXTURE_BIN:/usr/bin:/bin" \
        JAN_OPT="$JAN_OPT" \
        FIXTURE_DIR="$FIXTURE_DIR" \
        FIXTURE_DOWNLOAD_LOG="$FIXTURE_DOWNLOAD_LOG" \
        "$OPT_JAN/usr/sbin/optupdate" mjolnir
}

@test "Mjolnir tar archive installs its complete bundle and is idempotent" {
    run_mjolnir_update
    [[ $status -eq 0 ]]
    [[ $(<"$JAN_OPT/mjolnir/.version") == 9.8.7 ]]
    [[ -s "$JAN_OPT/mjolnir/.installed-sha256" ]]
    [[ -L "$JAN_OPT/bin/mj" ]]
    [[ $($JAN_OPT/bin/mj --version) == "Mjolnir fixture 9.8.7" ]]

    local binary
    for binary in mj mj-desktop mj-voice-worker \
        mj-worker-x86_64-unknown-linux-musl \
        mj-worker-aarch64-unknown-linux-musl; do
        [[ -x "$JAN_OPT/mjolnir/$binary" ]]
    done
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]

    run_mjolnir_update
    [[ $status -eq 0 ]]
    [[ $output == *"Mjolnir already at version 9.8.7"* ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]
}

@test "Mjolnir repairs a same-version install missing a worker" {
    run_mjolnir_update
    [[ $status -eq 0 ]]
    rm "$JAN_OPT/mjolnir/mj-worker-aarch64-unknown-linux-musl"

    run_mjolnir_update
    [[ $status -eq 0 ]]
    [[ $output == *"Repairing incomplete Mjolnir 9.8.7 installation"* ]]
    [[ -x "$JAN_OPT/mjolnir/mj-worker-aarch64-unknown-linux-musl" ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 2 ]]
}
