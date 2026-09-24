#!/usr/bin/env bash
# Download the official llama.cpp Qwen3.8-27B Q4_K_M base model via aria2c.
# The BF16 vision projector and MTP predictor come from download-qwen3.8-27b.sh.
# Requires: aria2c. HF_TOKEN or HUGGING_FACE_HUB_TOKEN is optional.
set -euo pipefail

REPO="ggml-org/Qwen3.8-27B-GGUF"
OUT_DIR="${OUT_DIR:-Qwen3.8-27B-GGUF-Q4_K_M}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"
MODEL="Qwen3.8-27B-Q4_K_M.gguf"
MODELS=("$MODEL")
if [[ "${DOWNLOAD_DFLASH:-0}" == 1 ]]; then
  MODELS+=("dflash-Qwen3.8-27B-Q4_0.gguf")
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
AUTH_HEADER=()
[[ -z "$HF_TOKEN" ]] || AUTH_HEADER=(--header="Authorization: Bearer ${HF_TOKEN}")

mkdir -p "$OUT_DIR"

echo "Destination: $OUT_DIR"
echo "Repository:  $REPO"

for file in "${MODELS[@]}"; do
  url="https://huggingface.co/${REPO}/resolve/main/${file}"
  printf '\n==> %s\n    %s\n' "$file" "$url"

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
    --dir="$OUT_DIR" \
    --out="$file" \
    "${AUTH_HEADER[@]}" \
    --header="User-Agent: aria2-hf-download" \
    "$url"

  [[ -s "$OUT_DIR/$file" ]] || die "download finished but file is missing or empty: $OUT_DIR/$file"
done

echo
echo "Done. Pair this Q4_K_M base with the BF16 mmproj and MTP files from the"
echo "Qwen3.8-27B directory. The llama-models.ini router preset does this."
echo "Set DOWNLOAD_DFLASH=1 to fetch the optional Q4_0 DFlash drafter."
