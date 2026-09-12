#!/usr/bin/env bats

setup() {
    OPT_JAN="${OPT_JAN:-$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)}"
    MODELS_INI="$OPT_JAN/agent/llama-models.ini"
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
