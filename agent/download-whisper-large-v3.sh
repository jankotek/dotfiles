#!/usr/bin/env bash
# Download OpenAI Whisper large-v3 in whisper.cpp ggml format via aria2c.
# This is for whisper.cpp (whisper-cli), not llama-server.
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

REPO="ggerganov/whisper.cpp"
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT_DIR="${OUT_DIR:-models/whisper-large-v3}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# Full large-v3 (~2.9 GiB). Not turbo, not quantized.
MODELS=(
  "ggml-large-v3.bin"
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
echo "Done. ~2.9 GiB ggml for whisper.cpp (not llama-server):"
echo "  whisper-cli -m $OUT_DIR/ggml-large-v3.bin -f talk.wav -l auto -otxt -osrt"
echo "Convert first if needed:"
echo "  ffmpeg -i talk.mp3 -ar 16000 -ac 1 -c:a pcm_s16le talk.wav"
