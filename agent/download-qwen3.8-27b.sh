#!/usr/bin/env bash
# Download Qwen3.8-27B 16-bit GGUFs for llama.cpp via aria2c.
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

REPO="ggml-org/Qwen3.8-27B-GGUF"
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT_DIR="${OUT_DIR:-models/Qwen3.8-27B}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# Main 16-bit dense weights + vision projector + separate MTP draft head.
MODELS=(
  "Qwen3.8-27B-BF16.gguf"
  "mmproj-Qwen3.8-27B-BF16.gguf"
  "mtp-Qwen3.8-27B-BF16.gguf"
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
echo "Done. llama.cpp example:"
echo "  llama-server \\"
echo "    -m $OUT_DIR/Qwen3.8-27B-BF16.gguf \\"
echo "    --mmproj $OUT_DIR/mmproj-Qwen3.8-27B-BF16.gguf \\"
echo "    --spec-draft-model $OUT_DIR/mtp-Qwen3.8-27B-BF16.gguf \\"
echo "    --spec-type draft-mtp --spec-draft-n-max 3 \\"
echo "    --parallel 1 --jinja -c 262144 -ngl 99 \\"
echo "    --reasoning on --reasoning-effort medium \\"
echo "    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0 \\"
echo "    --presence-penalty 0 --repeat-penalty 1"
