#!/usr/bin/env bats

setup() {
    OPT_JAN="${OPT_JAN:-$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)}"
    MODELS_INI="$OPT_JAN/agent/llama-models.ini"
}

teardown() {
    if [[ -n "${TEST_TEMP:-}" ]]; then
        rm -rf -- "$TEST_TEMP"
    fi
}

preset() {
    local name="$1"
    awk -v section="[$name]" '
        $0 == section { found = 1; next }
        found && /^\[/ { exit }
        found { print }
    ' "$MODELS_INI"
}

@test "download scripts use the caller directory and retain destination overrides" {
    run grep -lF 'cd "$(dirname "${BASH_SOURCE[0]}")"' "$OPT_JAN"/agent/download-*.sh
    [ "$status" -eq 1 ]

    run grep -F 'OUT_DIR="${OUT_DIR:-Qwen3.8-27B-GGUF-Q4_K_M}"' "$OPT_JAN/agent/download-qwen3.8-27b-q4-k-m.sh"
    [ "$status" -eq 0 ]

    run grep -F 'ROOT="${ROOT:-.}"' "$OPT_JAN/agent/download-translategemma.sh"
    [ "$status" -eq 0 ]
}

@test "all download scripts accept no token and send authorization only when set" {
    TEST_TEMP="$(mktemp -d)"
    mkdir -p "$TEST_TEMP/bin"
    cat > "$TEST_TEMP/bin/aria2c" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest_dir=
output=
header=
for argument in "$@"; do
    case "$argument" in
        --dir=*) dest_dir="${argument#--dir=}" ;;
        --out=*) output="${argument#--out=}" ;;
        --header=Authorization:*) header="${argument#--header=}" ;;
    esac
done
[[ -n "$dest_dir" && -n "$output" ]]
printf '%s\n' "$header" >> "$DOWNLOAD_LOG"
mkdir -p "$dest_dir"
printf fixture > "$dest_dir/$output"
EOF
    chmod +x "$TEST_TEMP/bin/aria2c"

    for script in "$OPT_JAN"/agent/download-*.sh; do
        name="$(basename "$script" .sh)"
        for token_source in none hf hub; do
            dir="$TEST_TEMP/$name/$token_source"
            mkdir -p "$dir"
            case "$token_source" in
                none)
                    run env -u HF_TOKEN -u HUGGING_FACE_HUB_TOKEN \
                        PATH="$TEST_TEMP/bin:$PATH" DOWNLOAD_LOG="$dir/headers" \
                        ROOT="$dir" OUT_DIR="$dir" "$script"
                    ;;
                hf)
                    run env -u HUGGING_FACE_HUB_TOKEN \
                        HF_TOKEN=fixture-hf PATH="$TEST_TEMP/bin:$PATH" \
                        DOWNLOAD_LOG="$dir/headers" ROOT="$dir" OUT_DIR="$dir" "$script"
                    ;;
                hub)
                    run env -u HF_TOKEN \
                        HUGGING_FACE_HUB_TOKEN=fixture-hub PATH="$TEST_TEMP/bin:$PATH" \
                        DOWNLOAD_LOG="$dir/headers" ROOT="$dir" OUT_DIR="$dir" "$script"
                    ;;
            esac
            [ "$status" -eq 0 ]
            [ -s "$dir/headers" ]
            case "$token_source" in
                none) ! grep -q . "$dir/headers" ;;
                hf) ! grep -vxq 'Authorization: Bearer fixture-hf' "$dir/headers" ;;
                hub) ! grep -vxq 'Authorization: Bearer fixture-hub' "$dir/headers" ;;
            esac
        done
    done
}

@test "Qwen downloaders keep BF16 and Q4_K_M bases side by side" {
    run grep -F '"Qwen3.8-27B-BF16.gguf"' "$OPT_JAN/agent/download-qwen3.8-27b.sh"
    [ "$status" -eq 0 ]

    run grep -F 'MODEL="Qwen3.8-27B-Q4_K_M.gguf"' "$OPT_JAN/agent/download-qwen3.8-27b-q4-k-m.sh"
    [ "$status" -eq 0 ]

    run grep -F '"mmproj-Qwen3.8-27B-BF16.gguf"' "$OPT_JAN/agent/download-qwen3.8-27b.sh"
    [ "$status" -eq 0 ]

    run grep -F '"mtp-Qwen3.8-27B-BF16.gguf"' "$OPT_JAN/agent/download-qwen3.8-27b.sh"
    [ "$status" -eq 0 ]
}

@test "Flash-Next downloader fetches every shard and projector to the preset paths" {
    TEST_TEMP="$(mktemp -d)"
    mkdir -p "$TEST_TEMP/bin"
    cat > "$TEST_TEMP/bin/aria2c" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest_dir=
output=
url=
for argument in "$@"; do
    case "$argument" in
        --dir=*) dest_dir="${argument#--dir=}" ;;
        --out=*) output="${argument#--out=}" ;;
        https://*) url="$argument" ;;
    esac
done
[[ -n "$dest_dir" && -n "$output" && -n "$url" ]]
printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
printf fixture > "$dest_dir/$output"
EOF
    chmod +x "$TEST_TEMP/bin/aria2c"

    run env \
        PATH="$TEST_TEMP/bin:$PATH" \
        HF_TOKEN=fixture-token \
        DOWNLOAD_LOG="$TEST_TEMP/urls" \
        OUT_DIR="$TEST_TEMP/Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL" \
        "$OPT_JAN/agent/download-qwen3.8-flash-next-ud-q4-k-xl.sh"
    [ "$status" -eq 0 ]

    for shard in 1 2 3 4; do
        printf -v number '%05d' "$shard"
        file="UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-${number}-of-00004.gguf"
        [ -s "$TEST_TEMP/Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL/$file" ]
        grep -Fx "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/$file" "$TEST_TEMP/urls"
    done
    [ -s "$TEST_TEMP/Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL/mmproj-BF16.gguf" ]
    grep -Fx "https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/resolve/main/mmproj-BF16.gguf" "$TEST_TEMP/urls"
    [ "$(wc -l < "$TEST_TEMP/urls")" -eq 5 ]

    run preset Qwen3.8-Flash-Next-UD-Q4_K_XL
    [ "$status" -eq 0 ]
    [[ "$output" == *"model = /var/models/Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf"* ]]
    [[ "$output" == *"mmproj = /var/models/Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL/mmproj-BF16.gguf"* ]]
}

@test "single Qwen embedding downloader creates all Q8_0 model directories" {
    TEST_TEMP="$(mktemp -d)"
    mkdir -p "$TEST_TEMP/bin" "$TEST_TEMP/models"
    cat > "$TEST_TEMP/bin/aria2c" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
dest_dir=
output=
for argument in "$@"; do
    case "$argument" in
        --dir=*) dest_dir="${argument#--dir=}" ;;
        --out=*) output="${argument#--out=}" ;;
    esac
done
[[ -n "$dest_dir" && -n "$output" ]]
mkdir -p "$dest_dir"
printf fixture > "$dest_dir/$output"
EOF
    chmod +x "$TEST_TEMP/bin/aria2c"

    run env \
        PATH="$TEST_TEMP/bin:$PATH" \
        HF_TOKEN=fixture-token \
        ROOT="$TEST_TEMP/models" \
        "$OPT_JAN/agent/download-qwen3-embedding-q8.sh"
    [ "$status" -eq 0 ]

    for size in 0.6B 4B 8B; do
        [ -s "$TEST_TEMP/models/Qwen3-Embedding-${size}-GGUF-Q8_0/Qwen3-Embedding-${size}-Q8_0.gguf" ]
    done
}

@test "Qwen embedding presets use Q8_0 weights and last-token pooling" {
    local size output
    for size in 0.6B 4B 8B; do
        run preset "Qwen3-Embedding-${size}-Q8_0"
        [ "$status" -eq 0 ]
        [[ "$output" == *"model = /var/models/Qwen3-Embedding-${size}-GGUF-Q8_0/Qwen3-Embedding-${size}-Q8_0.gguf"* ]]
        [[ "$output" == *"embedding = true"* ]]
        [[ "$output" == *"pooling = last"* ]]
        [[ "$output" == *"parallel = 4"* ]]
        [[ "$output" == *"ctx-size = 32768"* ]]
        [[ "$output" == *"batch-size = 8192"* ]]
        [[ "$output" == *"ubatch-size = 8192"* ]]
        [[ "$output" == *"cache-type-k = bf16"* ]]
        [[ "$output" == *"cache-type-v = bf16"* ]]
    done
}

@test "Qwen BF16 router preset remains available" {
    run preset Qwen3.8-27B
    [ "$status" -eq 0 ]
    [[ "$output" == *"model = /var/models/Qwen3.8-27B/Qwen3.8-27B-BF16.gguf"* ]]
    [[ "$output" == *"parallel = 1"* ]]
    [[ "$output" == *"ctx-size = 262144"* ]]
    [[ "$output" == *"cache-type-k = bf16"* ]]
    [[ "$output" == *"cache-type-v = bf16"* ]]
}

@test "Qwen Q4 preset shares BF16 auxiliaries and has two 160K BF16 slots" {
    run preset Qwen3.8-27B-Q4_K_M
    [ "$status" -eq 0 ]
    [[ "$output" == *"model = /var/models/Qwen3.8-27B-GGUF-Q4_K_M/Qwen3.8-27B-Q4_K_M.gguf"* ]]
    [[ "$output" == *"mmproj = /var/models/Qwen3.8-27B/mmproj-Qwen3.8-27B-BF16.gguf"* ]]
    [[ "$output" == *"spec-draft-model = /var/models/Qwen3.8-27B/mtp-Qwen3.8-27B-BF16.gguf"* ]]
    [[ "$output" == *"spec-draft-type-k = bf16"* ]]
    [[ "$output" == *"spec-draft-type-v = bf16"* ]]
    [[ "$output" == *"parallel = 2"* ]]
    [[ "$output" == *"ctx-size = 327680"* ]]
    [[ "$output" == *"cache-type-k = bf16"* ]]
    [[ "$output" == *"cache-type-v = bf16"* ]]
}

@test "Muse Glimmer uses BF16 KV for four 80K slots" {
    run preset Muse-Glimmer-30B
    [ "$status" -eq 0 ]
    [[ "$output" == *"ctx-size = 327680"* ]]
    [[ "$output" == *"cache-type-k = bf16"* ]]
    [[ "$output" == *"cache-type-v = bf16"* ]]
    [[ "$output" == *"spec-draft-type-k = bf16"* ]]
    [[ "$output" == *"spec-draft-type-v = bf16"* ]]

    run awk '
        $0 == "[*]" { found = 1; next }
        found && /^\[/ { exit }
        found && /^parallel = 4$/ { seen = 1 }
        END { exit !seen }
    ' "$MODELS_INI"
    [ "$status" -eq 0 ]
}
