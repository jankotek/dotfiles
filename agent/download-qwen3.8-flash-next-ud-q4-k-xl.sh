#!/usr/bin/env bash
# Download Unsloth's Qwen3.8-Flash-Next UD-Q4_K_XL GGUF and vision projector.
# Requires: aria2c. HF_TOKEN or HUGGING_FACE_HUB_TOKEN is optional.
set -euo pipefail

REPO="unsloth/Qwen3.8-Flash-Next-GGUF"
OUT_DIR="${OUT_DIR:-Qwen3.8-Flash-Next-GGUF-UD-Q4_K_XL}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

FILES=(
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf"
  "UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf"
  "mmproj-BF16.gguf"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
AUTH_HEADER=()
[[ -z "$HF_TOKEN" ]] || AUTH_HEADER=(--header="Authorization: Bearer ${HF_TOKEN}")

echo "Destination: $OUT_DIR"
echo "Repository:  $REPO"
echo "Files:       ${#FILES[@]}"

for file in "${FILES[@]}"; do
  dir="$OUT_DIR/$(dirname "$file")"
  name="$(basename "$file")"
  url="https://huggingface.co/${REPO}/resolve/main/${file}"
  mkdir -p "$dir"
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
    --dir="$dir" \
    --out="$name" \
    "${AUTH_HEADER[@]}" \
    --header="User-Agent: aria2-hf-download" \
    "$url"

  [[ -s "$dir/$name" ]] || die "download finished but file is missing or empty: $dir/$name"
done

echo
echo "Done. Serve with the Qwen3.8-Flash-Next-UD-Q4_K_XL router preset."
