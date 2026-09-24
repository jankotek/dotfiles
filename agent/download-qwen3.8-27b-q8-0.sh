#!/usr/bin/env bash
# Download the ggml-org Qwen3.8-27B Q8_0 model, vision projector, and MTP head.
# Requires: aria2c. HF_TOKEN or HUGGING_FACE_HUB_TOKEN is optional.
set -euo pipefail

REPO="ggml-org/Qwen3.8-27B-GGUF"
OUT_DIR="${OUT_DIR:-Qwen3.8-27B-GGUF-Q8_0}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

MODELS=(
  "Qwen3.8-27B-Q8_0.gguf"
  "mmproj-Qwen3.8-27B-Q8_0.gguf"
  "mtp-Qwen3.8-27B-Q8_0.gguf"
)
if [[ "${DOWNLOAD_DFLASH:-0}" == 1 ]]; then
  MODELS+=("dflash-Qwen3.8-27B-Q8_0.gguf")
fi

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
echo "Done. Serve with the Qwen3.8-27B-Q8_0 router preset."
echo "Set DOWNLOAD_DFLASH=1 to fetch the optional DFlash drafter."
