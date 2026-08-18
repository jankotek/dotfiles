#!/usr/bin/env bash
# Download Gemma 4 12B 8-bit GGUFs for llama.cpp via aria2c.
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

REPO="ggml-org/gemma-4-12B-it-GGUF"
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT_DIR="${OUT_DIR:-models/gemma-4-12B}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# 8-bit instruct weights + matching multimodal projector (image/audio).
MODELS=(
  "gemma-4-12B-it-Q8_0.gguf"
  "mmproj-gemma-4-12B-it-Q8_0.gguf"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
[[ -n "$HF_TOKEN" ]] || die "set HF_TOKEN or HUGGING_FACE_HUB_TOKEN"

mkdir -p "$OUT_DIR"

hf_url() {
  local file="$1"
  printf 'https://huggingface.co/%s/resolve/main/%s' "$REPO" "$file"
}

download() {
  local file="$1"
  local dest="$OUT_DIR/$file"

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
    --dir="$OUT_DIR" \
    --out="$file" \
    --header="Authorization: Bearer ${HF_TOKEN}" \
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
echo "Done. llama.cpp example (Q8 weights ~12.7 GB; 64K context needs extra RAM):"
echo "  llama-server \\"
echo "    -m $OUT_DIR/gemma-4-12B-it-Q8_0.gguf \\"
echo "    --mmproj $OUT_DIR/mmproj-gemma-4-12B-it-Q8_0.gguf \\"
echo "    --device Vulkan0 -ngl 99 --sleep-idle-seconds 300 \\"
echo "    --jinja --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0 -c 65536 \\"
echo "    --host 127.0.0.1 --port 8080"
