#!/usr/bin/env bash
# Serve all llama.cpp GGUFs from llama-models.ini.
# Web UI + OpenAI API on port 7013. Idle unload after 5 minutes.
# Only one model stays loaded (--models-max 1).
# Muse Glimmer needs llama.cpp >= b10353; system package is older (b10154).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
LLAMA_BIN="${LLAMA_BIN:-tools/llama-b10456-vulkan/llama-b10456}"

[[ -x "$LLAMA_BIN/llama-server" ]] || {
  printf 'error: llama-server not found at %s\n' "$LLAMA_BIN/llama-server" >&2
  exit 1
}

export LD_LIBRARY_PATH="${LLAMA_BIN}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$LLAMA_BIN/llama-server" \
  --models-preset llama-models.ini \
  --models-max 1 \
  --sleep-idle-seconds 300 \
  --device Vulkan0 \
  -ngl 99 \
  --jinja \
  --webui \
  --host 127.0.0.1 \
  --port 7013
