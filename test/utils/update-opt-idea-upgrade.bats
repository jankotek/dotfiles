#!/usr/bin/env bats
# Offline regression tests for upgrading an existing IntelliJ IDEA tree.

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/idea-upgrade"
    export JAN_OPT="$TEST_ROOT/opt"
    export FIXTURE_DIR="$TEST_ROOT/fixture"
    export FIXTURE_BIN="$TEST_ROOT/bin"
    export FIXTURE_DOWNLOAD_LOG="$TEST_ROOT/downloads"
    export FIXTURE_MV_FAILURE_LOG="$TEST_ROOT/mv-failure"
    mkdir -p "$JAN_OPT" "$FIXTURE_DIR/archive/idea-2026.2.2/bin" "$FIXTURE_BIN"

    printf '#!/bin/sh\nprintf "IntelliJ fixture 2026.2.2\\n"\n' \
        > "$FIXTURE_DIR/archive/idea-2026.2.2/bin/idea.sh"
    chmod 0755 "$FIXTURE_DIR/archive/idea-2026.2.2/bin/idea.sh"
    tar czf "$FIXTURE_DIR/idea.tar.gz" -C "$FIXTURE_DIR/archive" idea-2026.2.2
    sha256sum "$FIXTURE_DIR/idea.tar.gz" | awk '{print $1}' \
        > "$FIXTURE_DIR/idea.tar.gz.sha256"

    cat > "$FIXTURE_DIR/release.json" <<'EOF'
{"IIU":[{"date":"2026-09-02","type":"release","version":"2026.2.2","build":"262.10315.125","downloads":{"linux":{"link":"https://fixture.invalid/idea-2026.2.2.tar.gz","checksumLink":"https://fixture.invalid/idea-2026.2.2.tar.gz.sha256"}}}]}
EOF

    cat > "$FIXTURE_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
url=${!#}
case "$url" in
    *data.services.jetbrains.com*) cat "$FIXTURE_DIR/release.json" ;;
    *.sha256) cat "$FIXTURE_DIR/idea.tar.gz.sha256" ;;
    *) echo "unexpected curl URL: $url" >&2; exit 1 ;;
esac
EOF
    cat > "$FIXTURE_BIN/aria2c" <<'EOF'
#!/bin/bash
set -euo pipefail
for argument in "$@"; do
    case "$argument" in
        --dir=*) destination_dir=${argument#--dir=} ;;
        --out=*) destination_name=${argument#--out=} ;;
    esac
done
printf 'download\n' >> "$FIXTURE_DOWNLOAD_LOG"
cp "$FIXTURE_DIR/idea.tar.gz" "$destination_dir/$destination_name"
EOF
    cat > "$FIXTURE_BIN/mv" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${FAIL_IDEA_ACTIVATION:-0} == 1 && $# == 3 && $1 == -T \
    && $2 == "$JAN_OPT"/.jan-update-idea.staging.* && $3 == "$JAN_OPT/idea" ]]; then
    printf 'injected activation failure\n' > "$FIXTURE_MV_FAILURE_LOG"
    exit 1
fi
exec /usr/bin/mv "$@"
EOF
    chmod 0755 "$FIXTURE_BIN/curl" "$FIXTURE_BIN/aria2c" "$FIXTURE_BIN/mv"
}

seed_old_idea() {
    mkdir -p "$JAN_OPT/idea/bin" "$JAN_OPT/bin" "$JAN_OPT/applications"
    printf '#!/bin/sh\nprintf "old IntelliJ 2025.2.5\\n"\n' \
        > "$JAN_OPT/idea/bin/idea.sh"
    chmod 0755 "$JAN_OPT/idea/bin/idea.sh"
    printf '2025.2.5\n' > "$JAN_OPT/idea/.version"
    printf 'obsolete\n' > "$JAN_OPT/idea/obsolete-file"
    printf 'old desktop\n' > "$JAN_OPT/applications/intellij-idea.desktop"
    ln -s "$JAN_OPT/idea/bin/idea.sh" "$JAN_OPT/bin/idea"
}

run_idea_update() {
    run env PATH="$FIXTURE_BIN:/usr/bin:/bin" \
        JAN_OPT="$JAN_OPT" \
        FIXTURE_DIR="$FIXTURE_DIR" \
        FIXTURE_DOWNLOAD_LOG="$FIXTURE_DOWNLOAD_LOG" \
        FIXTURE_MV_FAILURE_LOG="$FIXTURE_MV_FAILURE_LOG" \
        FAIL_IDEA_ACTIVATION="${FAIL_IDEA_ACTIVATION:-0}" \
        "$OPT_JAN/usr/sbin/host-optupdate" idea
}

@test "existing Community install upgrades to unified IntelliJ IDEA" {
    seed_old_idea

    run_idea_update
    [[ $status -eq 0 ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2026.2.2 ]]
    [[ -x $JAN_OPT/idea/bin/idea.sh ]]
    [[ $($JAN_OPT/bin/idea) == "IntelliJ fixture 2026.2.2" ]]
    [[ ! -e $JAN_OPT/idea/obsolete-file ]]
    [[ -s $JAN_OPT/idea/.installed-sha256 ]]
    [[ $(stat -c %a "$JAN_OPT/idea/bin/idea.sh") == 755 ]]
    grep -q "Exec=$JAN_OPT/idea/bin/idea.sh" \
        "$JAN_OPT/applications/intellij-idea.desktop"
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]

    run_idea_update
    [[ $status -eq 0 ]]
    [[ $output == *"IntelliJ IDEA already at version 2026.2.2"* ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]
}

@test "failed IntelliJ checksum preserves the old install" {
    seed_old_idea
    printf '%064d\n' 0 > "$FIXTURE_DIR/idea.tar.gz.sha256"

    run_idea_update
    [[ $status -ne 0 ]]
    [[ $output == *"Checksum mismatch"* ]]
    [[ $($JAN_OPT/bin/idea) == "old IntelliJ 2025.2.5" ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2025.2.5 ]]
    [[ -e $JAN_OPT/idea/obsolete-file ]]
    [[ $(<"$JAN_OPT/applications/intellij-idea.desktop") == "old desktop" ]]
}

@test "failed IntelliJ activation rolls back the old install" {
    seed_old_idea
    export FAIL_IDEA_ACTIVATION=1

    run_idea_update
    [[ $status -ne 0 ]]
    [[ -s $FIXTURE_MV_FAILURE_LOG ]]
    [[ $($JAN_OPT/bin/idea) == "old IntelliJ 2025.2.5" ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2025.2.5 ]]
    [[ -e $JAN_OPT/idea/obsolete-file ]]
    [[ $(<"$JAN_OPT/applications/intellij-idea.desktop") == "old desktop" ]]
    ! compgen -G "$JAN_OPT/.jan-update-idea.backup.*" >/dev/null
}
