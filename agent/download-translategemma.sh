#!/usr/bin/env bash
# Download TranslateGemma GGUFs + official 27B BF16 for llama.cpp via aria2c.
#   - 12B Q8_0 + F16 mmproj (image translation)
#   - 27B Q8_0 + F16 mmproj (image translation)
#   - 27B official BF16 safetensors (no public 16-bit GGUF exists)
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="${ROOT:-models}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# repo|relative-path|output-dir
DOWNLOADS=(
  "mradermacher/translategemma-12b-it-GGUF|translategemma-12b-it.Q8_0.gguf|${ROOT}/translategemma-12B"
  "mradermacher/translategemma-12b-it-GGUF|translategemma-12b-it.mmproj-f16.gguf|${ROOT}/translategemma-12B"
  "mradermacher/translategemma-27b-it-GGUF|translategemma-27b-it.Q8_0.gguf|${ROOT}/translategemma-27B"
  "mradermacher/translategemma-27b-it-GGUF|translategemma-27b-it.mmproj-f16.gguf|${ROOT}/translategemma-27B"
  "google/translategemma-27b-it|model-00001-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00002-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00003-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00004-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00005-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00006-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00007-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00008-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00009-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00010-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00011-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model-00012-of-00012.safetensors|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|model.safetensors.index.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|config.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|generation_config.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|tokenizer.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|tokenizer.model|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|tokenizer_config.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|special_tokens_map.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|added_tokens.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|preprocessor_config.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|processor_config.json|${ROOT}/translategemma-27B-BF16-hf"
  "google/translategemma-27b-it|chat_template.jinja|${ROOT}/translategemma-27B-BF16-hf"
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v aria2c >/dev/null 2>&1 || die "aria2c is not installed (package: aria2)"
[[ -n "$HF_TOKEN" ]] || die "set HF_TOKEN or HUGGING_FACE_HUB_TOKEN"

hf_url() {
  local repo="$1" file="$2"
  printf 'https://huggingface.co/%s/resolve/main/%s' "$repo" "$file"
}

download() {
  local repo="$1" file="$2" out_dir="$3"
  local dest="$out_dir/$file"

  mkdir -p "$out_dir"
  printf '\n==> %s/%s\n    %s\n' "$repo" "$file" "$(hf_url "$repo" "$file")"

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
    --dir="$out_dir" \
    --out="$file" \
    --header="Authorization: Bearer ${HF_TOKEN}" \
    --header="User-Agent: aria2-hf-download" \
    "$(hf_url "$repo" "$file")"

  [[ -s "$dest" ]] || die "download finished but file is missing or empty: $dest"
}

echo "Destination root: $ROOT"
echo "Files:            ${#DOWNLOADS[@]}"
echo
echo "Note: no public 16-bit GGUF exists for TranslateGemma 27B."
echo "      BF16 is official Hugging Face safetensors (~55 GB), not llama-server -m."

for spec in "${DOWNLOADS[@]}"; do
  IFS='|' read -r repo file out_dir <<<"$spec"
  download "$repo" "$file" "$out_dir"
done

echo
echo "Done. llama.cpp (GGUF only):"
echo "  llama-server \\"
echo "    -m $ROOT/translategemma-12B/translategemma-12b-it.Q8_0.gguf \\"
echo "    --mmproj $ROOT/translategemma-12B/translategemma-12b-it.mmproj-f16.gguf \\"
echo "    --device Vulkan0 -ngl 99 --jinja --temp 0 -c 8192 --host 127.0.0.1 --port 8080"
echo
echo "  llama-server \\"
echo "    -m $ROOT/translategemma-27B/translategemma-27b-it.Q8_0.gguf \\"
echo "    --mmproj $ROOT/translategemma-27B/translategemma-27b-it.mmproj-f16.gguf \\"
echo "    --device Vulkan0 -ngl 99 --jinja --temp 0 -c 8192 --host 127.0.0.1 --port 8080"
echo
echo "27B BF16 safetensors: $ROOT/translategemma-27B-BF16-hf"
echo "Convert to GGUF later with llama.cpp convert_hf_to_gguf.py if you want -m."
