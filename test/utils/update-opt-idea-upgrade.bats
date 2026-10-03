#!/usr/bin/env bats
# ci: fixture
# Offline regression tests for upgrading an existing IntelliJ IDEA tree.

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/idea-upgrade"
    export JAN_OPT="$TEST_ROOT/opt"
    export FIXTURE_DIR="$TEST_ROOT/fixture"
    export FIXTURE_BIN="$TEST_ROOT/bin"
    export FIXTURE_DOWNLOAD_LOG="$TEST_ROOT/downloads"
    export FIXTURE_PLUGIN_LOG="$TEST_ROOT/plugins"
    export FIXTURE_MV_FAILURE_LOG="$TEST_ROOT/mv-failure"
    mkdir -p "$JAN_OPT" "$FIXTURE_DIR/archive/idea-2026.2.2/bin" "$FIXTURE_BIN"

    cat > "$FIXTURE_DIR/plugin-files" <<'EOF'
PythonCore python-ce/lib/python-ce.jar
Pythonid python/lib/python.jar
org.jetbrains.plugins.go go-plugin/lib/go-plugin.jar
com.jetbrains.rust intellij-rust/lib/intellij-rust.jar
org.jetbrains.plugins.clion.radler clion-radler/lib/clion-radler.jar
com.intellij.clion clion/lib/clion.jar
com.intellij.nativeDebug nativeDebug-plugin/lib/nativeDebug-plugin.jar
com.intellij.cmake cmake/lib/cmake.jar
com.intellij.clion.meson clion-meson/lib/clion-meson.jar
com.intellij.clion-compdb clion-compdb/lib/clion-compdb.jar
name.kropp.intellij.makefile makefile/lib/makefile.jar
com.jetbrains.plugins.ini4idea ini/lib/ini.jar
EOF
    mkdir -p "$FIXTURE_DIR/archive/idea-2026.2.2/plugins"
    printf 'publisher plugin index\n' > "$FIXTURE_DIR/archive/idea-2026.2.2/plugins/plugin-classpath.txt"
    python3 - "$FIXTURE_DIR" <<'PYTHON'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
plugins = [line.split()[0] for line in (root / 'plugin-files').read_text().splitlines()]
(root / 'plugins.json').write_text(json.dumps([
    dict(pluginXmlId=plugin, id=index, version='262.1')
    for index, plugin in enumerate(plugins, 1)
]))
PYTHON

    cat > "$FIXTURE_DIR/archive/idea-2026.2.2/bin/idea.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ ${1:-} == installPlugins ]]; then
    expected="installPlugins $(cut -d ' ' -f 1 "$FIXTURE_DIR/plugin-files" | paste -sd ' ')"
    [[ $* == "$expected" ]]
    [[ -f $IDEA_PROPERTIES ]]
    plugin_dir=$(sed -n 's/^idea.plugins.path=//p' "$IDEA_PROPERTIES")
    [[ $plugin_dir == "$JAN_OPT"/.jan-update-idea.staging.*/.plugin-install/plugins ]]
    tree=${plugin_dir%/.plugin-install/plugins}
    while read -r _ file; do
        [[ ! -e $tree/plugins/${file%%/*} ]]
    done < "$FIXTURE_DIR/plugin-files"
    printf '%s\n' "$*" >> "$FIXTURE_PLUGIN_LOG"
    [[ ${FAIL_IDEA_PLUGINS:-0} != 1 ]] || exit 1
    while read -r plugin file; do
        if [[ ${INCOMPLETE_IDEA_PLUGINS:-0} == 1 && $plugin == com.jetbrains.rust ]]; then
            continue
        fi
        mkdir -p "$(dirname "$plugin_dir/$file")"
        printf '%s fixture\n' "$plugin" > "$plugin_dir/$file"
    done < "$FIXTURE_DIR/plugin-files"
else
    printf 'IntelliJ fixture 2026.2.2\n'
fi
EOF
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
    *plugins.jetbrains.com/api/search/updates/compatible) cat "$FIXTURE_DIR/plugins.json" ;;
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
        "$OPT_JAN/usr/sbin/optupdate" idea
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

@test "JetBrains language and build plugins are bundled for all users and skipped on repeat" {
    run_idea_update
    [[ $status -eq 0 ]]
    [[ -s $JAN_OPT/idea/plugins/python/lib/python.jar ]]
    [[ -s $JAN_OPT/idea/plugins/go-plugin/lib/go-plugin.jar ]]
    [[ $(stat -c %a "$JAN_OPT/idea/plugins/python/lib/python.jar") == 644 ]]
    [[ ! -e $JAN_OPT/idea/.plugin-install ]]
    [[ ! -e $JAN_OPT/idea/plugins/plugin-classpath.txt ]]
    [[ $(wc -l < "$JAN_OPT/idea/.jetbrains-plugins") -eq 12 ]]
    grep -q '^com.jetbrains.rust 4 262.1$' "$JAN_OPT/idea/.jetbrains-plugins"
    while read -r _ file; do
        [[ -s $JAN_OPT/idea/plugins/$file ]]
    done < "$FIXTURE_DIR/plugin-files"

    run_idea_update
    [[ $status -eq 0 ]]
    [[ $(wc -l < "$FIXTURE_PLUGIN_LOG") -eq 1 ]]
}

@test "same-version IDEA without bundled plugins is repaired" {
    run_idea_update
    [[ $status -eq 0 ]]
    rm -rf "$JAN_OPT/idea/plugins/go-plugin"
    run_idea_update
    [[ $status -eq 0 ]]
    [[ -s $JAN_OPT/idea/plugins/go-plugin/lib/go-plugin.jar ]]
    [[ $(wc -l < "$FIXTURE_PLUGIN_LOG") -eq 2 ]]
}

@test "plugin download failure preserves old IDEA and cleans staging" {
    seed_old_idea
    export FAIL_IDEA_PLUGINS=1
    run_idea_update
    [[ $status -ne 0 ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2025.2.5 ]]
    [[ -e $JAN_OPT/idea/obsolete-file ]]
    [[ $(<"$JAN_OPT/applications/intellij-idea.desktop") == 'old desktop' ]]
    ! compgen -G "$JAN_OPT/.jan-update-idea.staging.*" >/dev/null
}

@test "installer success without all plugins preserves old IDEA" {
    seed_old_idea
    export INCOMPLETE_IDEA_PLUGINS=1
    run_idea_update
    [[ $status -ne 0 ]]
    [[ $output == *'plugin installation is incomplete'* ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2025.2.5 ]]
}

@test "new compatible plugin version updates without downloading IDEA again" {
    run_idea_update
    [[ $status -eq 0 ]]
    sed -i 's/262.1/262.2/g' "$FIXTURE_DIR/plugins.json"
    run_idea_update
    [[ $status -eq 0 ]]
    [[ $output == *'Updating IntelliJ IDEA 2026.2.2 plugins'* ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]
    [[ $(wc -l < "$FIXTURE_PLUGIN_LOG") -eq 2 ]]
    grep -q '^com.jetbrains.rust 4 262.2$' "$JAN_OPT/idea/.jetbrains-plugins"
}

@test "failed same-version plugin update preserves active plugins and marker" {
    run_idea_update
    [[ $status -eq 0 ]]
    cp "$JAN_OPT/idea/.jetbrains-plugins" "$TEST_ROOT/old-manifest"
    sed -i 's/262.1/262.2/g' "$FIXTURE_DIR/plugins.json"
    export FAIL_IDEA_PLUGINS=1
    run_idea_update
    [[ $status -ne 0 ]]
    cmp "$JAN_OPT/idea/.jetbrains-plugins" "$TEST_ROOT/old-manifest"
    [[ -s $JAN_OPT/idea/plugins/intellij-rust/lib/intellij-rust.jar ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]
    ! compgen -G "$JAN_OPT/.jan-update-idea.staging.*" >/dev/null
}

@test "missing compatible release fails before changing IDEA" {
    seed_old_idea
    printf '[]\n' > "$FIXTURE_DIR/plugins.json"
    run_idea_update
    [[ $status -ne 0 ]]
    [[ $output == *'No compatible JetBrains plugin found'* ]]
    [[ $(<"$JAN_OPT/idea/.version") == 2025.2.5 ]]
    [[ ! -e $FIXTURE_DOWNLOAD_LOG ]]
}

@test "publisher plugin index is removed on same-version repair" {
    run_idea_update
    [[ $status -eq 0 ]]
    printf 'stale publisher index\n' > "$JAN_OPT/idea/plugins/plugin-classpath.txt"
    run_idea_update
    [[ $status -eq 0 ]]
    [[ ! -e $JAN_OPT/idea/plugins/plugin-classpath.txt ]]
    [[ $(wc -l < "$FIXTURE_DOWNLOAD_LOG") -eq 1 ]]
}
