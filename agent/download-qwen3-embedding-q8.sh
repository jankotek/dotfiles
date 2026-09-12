#!/usr/bin/env bash
# Download all official Qwen3 text-embedding models in Q8_0 GGUF format.
# Run from the directory that should contain the model directories, or set ROOT.
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

ROOT="${ROOT:-.}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# Hugging Face repo | filename | quant-specific local directory
DOWNLOADS=(
  "Qwen/Qwen3-Embedding-0.6B-GGUF|Qwen3-Embedding-0.6B-Q8_0.gguf|${ROOT}/Qwen3-Embedding-0.6B-GGUF-Q8_0"
  "Qwen/Qwen3-Embedding-4B-GGUF|Qwen3-Embedding-4B-Q8_0.gguf|${ROOT}/Qwen3-Embedding-4B-GGUF-Q8_0"
  "Qwen/Qwen3-Embedding-8B-GGUF|Qwen3-Embedding-8B-Q8_0.gguf|${ROOT}/Qwen3-Embedding-8B-GGUF-Q8_0"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
[[ -n "$HF_TOKEN" ]] || die "set HF_TOKEN or HUGGING_FACE_HUB_TOKEN"

download() {
  local repo="$1"
  local file="$2"
  local dest_dir="$3"
  local url="https://huggingface.co/${repo}/resolve/main/${file}"

  mkdir -p "$dest_dir"
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
    --dir="$dest_dir" \
    --out="$file" \
    --header="Authorization: Bearer ${HF_TOKEN}" \
    --header="User-Agent: aria2-hf-download" \
    "$url"

  [[ -s "$dest_dir/$file" ]] || die "download finished but file is missing or empty: $dest_dir/$file"
}

printf 'Destination root: %s\nModels:           %s\n' "$ROOT" "${#DOWNLOADS[@]}"

for item in "${DOWNLOADS[@]}"; do
  IFS='|' read -r repo file dest_dir <<< "$item"
  download "$repo" "$file" "$dest_dir"
done

echo
echo "Done. llama-models.ini serves all three with last-token pooling."
