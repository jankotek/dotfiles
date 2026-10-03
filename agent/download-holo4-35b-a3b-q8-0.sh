#!/usr/bin/env bash
# Download Holo4-35B-A3B Q8_0 weights and its Q8_0 vision projector.
# Community GGUF conversion of Hcompany/Holo4-35B-A3B by mradermacher.
# Requires: aria2c. HF_TOKEN or HUGGING_FACE_HUB_TOKEN is optional.
set -euo pipefail

REPO="mradermacher/Holo4-35B-A3B-GGUF"
OUT_DIR="${OUT_DIR:-Holo4-35B-A3B-GGUF-Q8_0}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

MODELS=(
  "Holo4-35B-A3B.Q8_0.gguf"
  "Holo4-35B-A3B.mmproj-Q8_0.gguf"
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
echo "Done. Copy $OUT_DIR into /var/models/ and select Holo4-35B-A3B-Q8_0 in serve-all.sh."
