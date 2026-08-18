#!/usr/bin/env bash
# Download LiquidAI LFM2.5-2.6B Q8_0 GGUF for llama.cpp via aria2c.
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

REPO="LiquidAI/LFM2.5-2.6B-GGUF"
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT_DIR="${OUT_DIR:-models/LFM2.5-2.6B}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# Text-only 8-bit weights (no vision projector).
MODELS=(
  "LFM2.5-2.6B-Q8_0.gguf"
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
echo "Done. llama.cpp example (~2.87 GB, text only):"
echo "  llama-server \\"
echo "    -m $OUT_DIR/LFM2.5-2.6B-Q8_0.gguf \\"
echo "    --device Vulkan0 -ngl 99 --sleep-idle-seconds 300 \\"
echo "    --parallel 4 --jinja -c 262144 \\"
echo "    --temp 0.1 --top-k 50 --top-p 1 --min-p 0 --repeat-penalty 1.1 \\"
echo "    --host 127.0.0.1 --port 8080"
