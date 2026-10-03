#!/usr/bin/env bash
# Download only the native JEV-27B decision adapter/head and serving metadata.
# Not a speculative drafter or a llama.cpp GGUF; no backbone is downloaded.
# Adapter precision is published BF16/FP32, not Q8_0. Pair with a compatible
# HF Qwen3.8-27B text backbone in Transformers/vLLM (8-bit if supported).
# Requires: aria2c. HF_TOKEN or HUGGING_FACE_HUB_TOKEN is optional.
set -euo pipefail

REPO="autotrust/JEV-27B"
OUT_DIR="${OUT_DIR:-JEV-27B-adapter}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

MODELS=(
  "adapter/adapter_config.json"
  "adapter/adapter_model.safetensors"
  "adapter_vllm/adapter_config.json"
  "adapter_vllm/adapter_model.safetensors"
  "adapter_vllm/decision_head.json"
  "head.safetensors"
  "judge_config.json"
  "calibration.json"
  "README.md"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
AUTH_HEADER=()
[[ -z "$HF_TOKEN" ]] || AUTH_HEADER=(--header="Authorization: Bearer ${HF_TOKEN}")

mkdir -p "$OUT_DIR"

hf_url() {
  local file="$1"
  printf 'https://huggingface.co/%s/resolve/main/%s' "$REPO" "$file"
}

download() {
  local file="$1"
  local dest="$OUT_DIR/$file"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  mkdir -p "$dest_dir"

  printf '\n==> %s\n    %s\n' "$file" "$(hf_url "$file")"

  aria2c \
    --continue=true \
    --always-resume=true \
    --max-connection-per-server="$CONNECTIONS" \
    --split="$CONNECTIONS" \
    --min-split-size=8M \
    --max-tries=0 \
    --retry-wait=5 \
    --timeout=60 \
    --connect-timeout=30 \
    --file-allocation=none \
    --auto-file-renaming=false \
    --allow-overwrite=true \
    --dir="$dest_dir" \
    --out="$(basename "$file")" \
    "${AUTH_HEADER[@]}" \
    --header="User-Agent: aria2-hf-download" \
    "$(hf_url "$file")"

  [[ -s "$dest" ]] || die "download finished but file is missing or empty: $dest"
}

echo "Destination: $OUT_DIR"
echo "Repository:  $REPO"
echo "Files:       ${#MODELS[@]}"

for file in "${MODELS[@]}"; do
  download "$file"
done

echo
echo "Done. Copy $OUT_DIR into /var/models/ for a separate Transformers/vLLM service."
echo "The included README documents the backbone, adapter, calibration, and serving requirements."
echo "Your existing Qwen GGUF and llama.cpp router cannot load this native adapter/head."
