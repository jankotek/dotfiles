#!/usr/bin/env bash
# Download PaddleOCR-VL-1.6 (largest weights) via aria2c.
#   llama.cpp: official F16 GGUF + F16 mmproj
#   Paddle/official: HF safetensors snapshot + PP-DocLayoutV3 paddle weights
# Requires: aria2c, and HF_TOKEN or HUGGING_FACE_HUB_TOKEN in the environment.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="${ROOT:-models}"
HF_TOKEN="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
CONNECTIONS="${ARIA_CONNECTIONS:-16}"

# repo|relative-path|output-dir
DOWNLOADS=(
  "PaddlePaddle/PaddleOCR-VL-1.6-GGUF|PaddleOCR-VL-1.6-GGUF.gguf|${ROOT}/PaddleOCR-VL-1.6-llama"
  "PaddlePaddle/PaddleOCR-VL-1.6-GGUF|PaddleOCR-VL-1.6-GGUF-mmproj.gguf|${ROOT}/PaddleOCR-VL-1.6-llama"
  "PaddlePaddle/PaddleOCR-VL-1.6|model.safetensors|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|config.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|generation_config.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|configuration_paddleocr_vl.py|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|modeling_paddleocr_vl.py|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|image_processing_paddleocr_vl.py|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|processing_paddleocr_vl.py|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|preprocessor_config.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|processor_config.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|tokenizer.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|tokenizer.model|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|tokenizer_config.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|special_tokens_map.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|added_tokens.json|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|chat_template.jinja|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PaddleOCR-VL-1.6|inference.yml|${ROOT}/PaddleOCR-VL-1.6-official"
  "PaddlePaddle/PP-DocLayoutV3|inference.pdiparams|${ROOT}/PaddleOCR-VL-1.6-official/PP-DocLayoutV3"
  "PaddlePaddle/PP-DocLayoutV3|inference.json|${ROOT}/PaddleOCR-VL-1.6-official/PP-DocLayoutV3"
  "PaddlePaddle/PP-DocLayoutV3|inference.yml|${ROOT}/PaddleOCR-VL-1.6-official/PP-DocLayoutV3"
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

for spec in "${DOWNLOADS[@]}"; do
  IFS='|' read -r repo file out_dir <<<"$spec"
  download "$repo" "$file" "$out_dir"
done

echo
echo "Done. llama.cpp F16 (~1.7 GB total):"
echo "  llama-server \\"
echo "    -m $ROOT/PaddleOCR-VL-1.6-llama/PaddleOCR-VL-1.6-GGUF.gguf \\"
echo "    --mmproj $ROOT/PaddleOCR-VL-1.6-llama/PaddleOCR-VL-1.6-GGUF-mmproj.gguf \\"
echo "    --device Vulkan0 -ngl 99 --temp 0 -c 8192 --host 127.0.0.1 --port 8080"
echo
echo "Official Paddle/HF snapshot: $ROOT/PaddleOCR-VL-1.6-official"
echo "  VLM:     model.safetensors (~1.9 GB)"
echo "  layout:  PP-DocLayoutV3/ (~125 MB paddle inference)"
