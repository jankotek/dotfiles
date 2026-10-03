#!/usr/bin/env bats
# ci: portable-tools
# Full network integration test for every tool in optupdate's default set.

@test "default optupdate installs every expected executable" {
    local target="$BATS_TEST_TMPDIR/opt"
    local binary version
    local -a binaries=(
        idea nu herdr mj codex grok pi claude obsidian fresh gradle mvn
        kubectl kind k9s helm stern skaffold jq yq
        ffmpeg ffplay ffprobe
    )
    mkdir -p "$target"

    run env JAN_OPT="$target" GITHUB_API_TOKEN="${GITHUB_API_TOKEN:-}" \
        "$OPT_JAN/usr/sbin/optupdate"
    if [[ $status -ne 0 ]]; then
        echo "$output" >&2
    fi
    [[ $status -eq 0 ]]

    for binary in "${binaries[@]}"; do
        [[ -x $target/bin/$binary ]] || {
            echo "Missing executable: $target/bin/$binary" >&2
            return 1
        }
    done
    for version in 8 11 17 21 23; do
        [[ -x $target/jdk/$version/bin/java ]] || {
            echo "Missing executable: $target/jdk/$version/bin/java" >&2
            return 1
        }
    done
    [[ ! -e $target/idea/plugins/plugin-classpath.txt ]]
    [[ -s $target/idea/plugins/python-ce/lib/python-ce.jar ]]
    [[ -s $target/idea/plugins/python/lib/python.jar ]]
    [[ -s $target/idea/plugins/go-plugin/lib/go-plugin.jar ]]
    [[ -s $target/idea/plugins/intellij-rust/lib/intellij-rust.jar ]]
    [[ -s $target/idea/plugins/clion-radler/lib/clion-radler.jar ]]
    [[ -s $target/idea/plugins/clion/lib/clion.jar ]]
    [[ -s $target/idea/plugins/nativeDebug-plugin/lib/nativeDebug-plugin.jar ]]
    [[ -s $target/idea/plugins/cmake/lib/cmake.jar ]]
    [[ -s $target/idea/plugins/clion-meson/lib/clion-meson.jar ]]
    [[ -s $target/idea/plugins/clion-compdb/lib/clion-compdb.jar ]]
    [[ -s $target/idea/plugins/makefile/lib/makefile.jar ]]
    [[ -s $target/idea/plugins/ini/lib/ini.jar ]]
    for binary in mj mj-desktop mj-voice-worker \
        mj-worker-x86_64-unknown-linux-musl \
        mj-worker-aarch64-unknown-linux-musl; do
        [[ -x $target/mjolnir/$binary ]] || {
            echo "Missing Mjolnir bundle executable: $target/mjolnir/$binary" >&2
            return 1
        }
    done
}
