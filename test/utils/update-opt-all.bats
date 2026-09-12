#!/usr/bin/env bats
# Full network integration test for every tool in host-optupdate's default set.

@test "default host-optupdate installs every expected executable" {
    local target="$BATS_TEST_TMPDIR/opt"
    local binary version
    local -a binaries=(
        idea nu herdr codex grok pi claude obsidian fresh gradle mvn
        kubectl kind k9s helm stern skaffold jq yq
        ffmpeg ffplay ffprobe
    )
    mkdir -p "$target"

    run env JAN_OPT="$target" GITHUB_API_TOKEN="${GITHUB_API_TOKEN:-}" \
        "$OPT_JAN/usr/sbin/host-optupdate"
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
}
