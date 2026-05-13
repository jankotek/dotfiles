#!/bin/bash
# =============================================================================
# serve-all.sh — Serve all GGUF models via llama-server router mode
# =============================================================================
# Strix Halo 128GB / Vulkan / openSUSE Tumbleweed
#
# Usage:  ./serve-all.sh
# API:    http://localhost:8080/v1/chat/completions
# Web UI: http://localhost:8080
# Models: http://localhost:8080/v1/models
#
# Request a specific model in API calls:
#   curl http://localhost:8080/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "qwen3.5-35b", "messages": [{"role": "user", "content": "Hi"}]}'
#
# The server auto-loads models on first request and unloads after idle timeout.
# Max 2 models loaded simultaneously (adjustable with --models-max).
# =============================================================================

set -euo pipefail

MODELS_INI="/var/models/models.ini"
PORT=8080
HOST=0.0.0.0

# Max models loaded in RAM simultaneously
# 2 = safe for most combos (e.g. 35B + 24B = ~40GB)
# 3 = fine for small models (e.g. lfm2 + qwen-0.8b + aya)
# 1 = if loading 122B or glm-4.5-air (they use 55-77GB alone)
MODELS_MAX=2

# Idle timeout: unload model after 5 minutes of no requests
IDLE_SECONDS=300

if [ ! -r "$MODELS_INI" ]; then
    echo "ERROR: models config '$MODELS_INI' not found or not readable." >&2
    exit 1
fi

# Allocate a TTY only when stdin is a TTY — otherwise podman -it fails when
# launched from a service or under nohup.
if [ -t 0 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG=""
fi

echo "============================================="
echo " llama-server Router Mode"
echo " Port: $PORT"
echo " Models config: $MODELS_INI"
echo " Max simultaneous: $MODELS_MAX"
echo " Idle timeout: ${IDLE_SECONDS}s"
echo "============================================="
echo ""
echo " List models:  curl http://localhost:$PORT/v1/models"
echo " Chat:         curl http://localhost:$PORT/v1/chat/completions"
echo ""
echo " Available model names (use in 'model' field):"
grep '^\[' "$MODELS_INI" | tr -d '[]' | while read -r name; do
    echo "   - $name"
done
echo ""
echo "============================================="

# --- Run via Podman (kyuz0 Vulkan container) ---
podman run $TTY_FLAG --rm \
    --name llama-router \
    --device /dev/dri \
    --group-add video \
    --security-opt seccomp=unconfined \
    -v /var/models:/var/models:Z \
    -p ${PORT}:${PORT} \
    docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv \
    llama-server \
        --models-preset /var/models/models.ini \
        --models-max $MODELS_MAX \
        --host $HOST \
        --port $PORT \
        --sleep-idle-seconds $IDLE_SECONDS

# --- Alternative: Run native llama-server (if installed locally) ---
# Uncomment below and comment out the podman block above:
#
# llama-server \
#     --models-preset /var/models/models.ini \
#     --models-max $MODELS_MAX \
#     --host $HOST \
#     --port $PORT \
#     --sleep-idle-seconds $IDLE_SECONDS
