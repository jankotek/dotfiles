#!/bin/bash
# =============================================================================
# download-all-models.sh
# =============================================================================
# Downloads all GGUF models for HP ZBook Ultra G1a (Strix Halo, 128GB)
# Requires: hf CLI (pip install -U "huggingface_hub[cli]" hf_transfer)
# Set HF_HUB_ENABLE_HF_TRANSFER=1 for faster downloads (10x speed)
#
# Total estimated download: ~350-400 GB
# Make sure you have enough disk space!
# =============================================================================

set -uo pipefail
export HF_HUB_ENABLE_HF_TRANSFER=1

MODELS_DIR="${1:-/var/models}"
mkdir -p "$MODELS_DIR"

# Retry/resume wrapper. `hf download` is resumable via its on-disk cache,
# so a transient failure (network, server) just retries from where it left off.
dl() {
    local attempt=1
    until hf download "$@"; do
        echo "  [retry $attempt] hf download $* — sleeping 30s" >&2
        sleep 30
        attempt=$((attempt + 1))
    done
}

echo "============================================="
echo " Downloading all models to: $MODELS_DIR"
echo " Make sure HF token is set for gated models"
echo "============================================="

# ─────────────────────────────────────────────────────────────────────────────
# QWEN 3.5 FAMILY (Alibaba, Apache 2.0, 201 languages)
# ─────────────────────────────────────────────────────────────────────────────

# Daily driver. MoE 35B/3B active. Fastest smart model.              ~22 GB
echo ">>> Qwen3.5-35B-A3B (daily driver, 22GB)"
dl unsloth/Qwen3.5-35B-A3B-GGUF \
  --include "Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf" \
  --local-dir "$MODELS_DIR/Qwen3.5-35B-A3B-GGUF"

# Dense 27B. All parameters active. Strong reasoning.                ~17 GB
echo ">>> Qwen3.5-27B (dense reasoning, 17GB)"
dl unsloth/Qwen3.5-27B-GGUF \
  --include "Qwen3.5-27B-UD-Q4_K_XL.gguf" \
  --local-dir "$MODELS_DIR/Qwen3.5-27B-GGUF"

# Smartest Qwen. MoE 122B/10B active. Tight on RAM.                 ~77 GB
echo ">>> Qwen3.5-122B-A10B (smartest Qwen, 77GB)"
dl unsloth/Qwen3.5-122B-A10B-GGUF \
  --include "*Q4_K_M*" \
  --local-dir "$MODELS_DIR/Qwen3.5-122B-A10B-GGUF"

# Small models for titles, previews, summaries                       ~6 GB
echo ">>> Qwen3.5-0.8B (titles/labels, 1.2GB)"
dl unsloth/Qwen3.5-0.8B-GGUF \
  --include "Qwen3.5-0.8B-Q8_0.gguf" "mmproj-BF16.gguf" \
  --local-dir "$MODELS_DIR/Qwen3.5-0.8B-GGUF"

echo ">>> Qwen3.5-2B (light summaries, 2.5GB)"
dl unsloth/Qwen3.5-2B-GGUF \
  --include "Qwen3.5-2B-Q8_0.gguf" "mmproj-BF16.gguf" \
  --local-dir "$MODELS_DIR/Qwen3.5-2B-GGUF"

echo ">>> Qwen3.5-4B (summaries+vision, 4.5GB)"
dl unsloth/Qwen3.5-4B-GGUF \
  --include "Qwen3.5-4B-Q8_0.gguf" "mmproj-BF16.gguf" \
  --local-dir "$MODELS_DIR/Qwen3.5-4B-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# QWEN CODING (Alibaba, Apache 2.0)
# ─────────────────────────────────────────────────────────────────────────────

# Coding agent. MoE 80B/3B active. SWE-bench competitor.            ~45 GB
echo ">>> Qwen3-Coder-Next (coding agent, 45GB)"
dl unsloth/Qwen3-Coder-Next-GGUF \
  --include "Qwen3-Coder-Next-UD-Q4_K_XL.gguf" \
  --local-dir "$MODELS_DIR/Qwen3-Coder-Next-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# QWEN VISION (Alibaba, Apache 2.0) — PDF parsing, document understanding
# ─────────────────────────────────────────────────────────────────────────────

# Fast PDF/image parser. 8B dense + vision encoder.                  ~6 GB
echo ">>> Qwen3-VL-8B (fast PDF parser, 6GB)"
dl unsloth/Qwen3-VL-8B-Instruct-GGUF \
  --include "*UD-Q4_K_XL*" "mmproj-F16.gguf" \
  --local-dir "$MODELS_DIR/Qwen3-VL-8B-GGUF"

# Accurate PDF/image parser. 32B dense + vision encoder.             ~20 GB
echo ">>> Qwen3-VL-32B (accurate PDF parser, 20GB)"
dl unsloth/Qwen3-VL-32B-Instruct-GGUF \
  --include "*UD-Q4_K_XL*" "mmproj-F16.gguf" \
  --local-dir "$MODELS_DIR/Qwen3-VL-32B-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# QWEN TTS (Alibaba, Apache 2.0) — Text-to-speech (Python, NOT llama.cpp)
# ─────────────────────────────────────────────────────────────────────────────

# 10 languages, voice cloning, voice design. Run via: pip install qwen-tts
echo ">>> Qwen3-TTS models (Python-based TTS, ~12GB total)"
dl Qwen/Qwen3-TTS-Tokenizer-12Hz \
  --local-dir "$MODELS_DIR/Qwen3-TTS-Tokenizer-12Hz"
dl Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice \
  --local-dir "$MODELS_DIR/Qwen3-TTS-12Hz-1.7B-CustomVoice"
dl Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign \
  --local-dir "$MODELS_DIR/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
dl Qwen/Qwen3-TTS-12Hz-1.7B-Base \
  --local-dir "$MODELS_DIR/Qwen3-TTS-12Hz-1.7B-Base"
dl Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice \
  --local-dir "$MODELS_DIR/Qwen3-TTS-12Hz-0.6B-CustomVoice"
dl Qwen/Qwen3-TTS-12Hz-0.6B-Base \
  --local-dir "$MODELS_DIR/Qwen3-TTS-12Hz-0.6B-Base"

# ─────────────────────────────────────────────────────────────────────────────
# GPT-OSS (OpenAI, Apache 2.0, American)
# ─────────────────────────────────────────────────────────────────────────────

# OpenAI's open model. MoE 117B/5.1B active. Superfast.             ~70 GB
echo ">>> gpt-oss-120B (OpenAI open model, 70GB)"
dl unsloth/gpt-oss-120B-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir "$MODELS_DIR/gpt-oss-120B-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# MISTRAL (Mistral AI, Paris, Apache 2.0)
# ─────────────────────────────────────────────────────────────────────────────

# Unified model: chat+code+vision+reasoning. MoE 119B/6B active.    ~74 GB
echo ">>> Mistral Small 4 (unified European model, 74GB)"
dl unsloth/Mistral-Small-4-119B-2603-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir "$MODELS_DIR/Mistral-Small-4-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# GLM FAMILY (Zhipu AI / Z.ai, Beijing, MIT license)
# ─────────────────────────────────────────────────────────────────────────────

# Fast coding agent. MoE 30B/3B active.                             ~18 GB
echo ">>> GLM-4.7-Flash (fast agent/coder, 18GB)"
dl unsloth/GLM-4.7-Flash-GGUF \
  --include "GLM-4.7-Flash-UD-Q4_K_XL.gguf" \
  --local-dir "$MODELS_DIR/GLM-4.7-Flash-GGUF"

# Purpose-built agent model. MoE 106B/12B active. Tool use king.    ~55 GB
echo ">>> GLM-4.5-Air (dedicated agent model, 55GB)"
dl bartowski/zai-org_GLM-4.5-Air-GGUF \
  --include "zai-org_GLM-4.5-Air-Q4_K_M.gguf" \
  --local-dir "$MODELS_DIR/GLM-4.5-Air-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# NVIDIA NEMOTRON (NVIDIA, open license)
# ─────────────────────────────────────────────────────────────────────────────

# Small reasoning model. MoE 30B/3B active.                         ~23 GB
echo ">>> Nemotron-3-Nano (small reasoner, 23GB)"
dl unsloth/Nemotron-3-Nano-30B-A3B-GGUF \
  --include "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf" \
  --local-dir "$MODELS_DIR/Nemotron-3-Nano-GGUF"

# Large reasoning model. MoE 120B/12B active. Very new.             ~83 GB
echo ">>> Nemotron-3-Super (large reasoner, 83GB)"
dl unsloth/NVIDIA-Nemotron-3-Super-120B-A12B-GGUF \
  --include "*UD-Q4_K_XL*" \
  --local-dir "$MODELS_DIR/Nemotron-3-Super-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# LFM2 FAMILY (Liquid AI, MIT-ish, hybrid non-transformer architecture)
# 2x faster than transformers on CPU. Minimal KV cache overhead.
# ─────────────────────────────────────────────────────────────────────────────

# Tiny models — instant responses                                   ~0.4 GB
echo ">>> LFM2-350M (instant classifier, 0.4GB)"
dl LiquidAI/LFM2-350M-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-350M-GGUF"

#                                                                    ~0.8 GB
echo ">>> LFM2-700M (fast extraction, 0.8GB)"
dl LiquidAI/LFM2-700M-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-700M-GGUF"

#                                                                    ~1.4 GB
echo ">>> LFM2-1.2B (light tasks, 1.4GB)"
dl LiquidAI/LFM2-1.2B-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-1.2B-GGUF"

# Best instruction following at this size. Has thinking mode.        ~3 GB
echo ">>> LFM2-2.6B (general small model, 3GB)"
dl LiquidAI/LFM2-2.6B-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-2.6B-GGUF"

# Experimental RL-trained. Beats DeepSeek R1 on IFBench.             ~3 GB
echo ">>> LFM2-2.6B-Exp (best instruction follower, 3GB)"
dl LiquidAI/LFM2-2.6B-Exp-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-2.6B-Exp-GGUF"

# MoE 8B/1.5B active. Quality of 3-4B dense, faster than Qwen 1.7B. ~5 GB
echo ">>> LFM2-8B-A1B (fast MoE, 5GB)"
dl LiquidAI/LFM2-8B-A1B-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2-8B-A1B-GGUF"

# Biggest LFM2. MoE 24B/2B active. 112 tok/s on AMD CPU!            ~25 GB
# Downloads ALL quantizations (~185GB). Remove --local-dir line and
# use --include "*Q8_0*" for Q8 only (25GB).
echo ">>> LFM2-24B-A2B (all quants, 185GB)"
dl LiquidAI/LFM2-24B-A2B-GGUF \
  --local-dir "$MODELS_DIR/LFM2-24B-A2B-GGUF"

# Newer 1.2B with RL training. Extended pretraining on 28T tokens.   ~1.4 GB
echo ">>> LFM2.5-1.2B-Instruct (RL-trained, 1.4GB)"
dl LiquidAI/LFM2.5-1.2B-Instruct-GGUF \
  --include "*Q8_0*" \
  --local-dir "$MODELS_DIR/LFM2.5-1.2B-Instruct-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# TRANSLATION (Cohere, CC-BY-NC for Aya)
# ─────────────────────────────────────────────────────────────────────────────

# 23 languages including Czech. Best open translation model.         ~8.5 GB
echo ">>> Aya-23-8B (translation specialist, 8.5GB)"
dl QuantFactory/aya-23-8B-GGUF \
  --include "aya-23-8B.Q8_0.gguf" \
  --local-dir "$MODELS_DIR/aya-23-8B-GGUF"

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo " All downloads complete!"
echo "============================================="
echo ""
echo " Directory sizes:"
echo ""
du -sh "$MODELS_DIR"/*/ | sort -h
echo ""
echo " Total:"
du -sh "$MODELS_DIR"
echo ""
echo "============================================="
echo " SUMMARY"
echo "============================================="
cat << 'EOF'

 MODEL                     SIZE     PARAMS      ACTIVE    ROLE
 ─────────────────────────────────────────────────────────────────
 Qwen3.5-35B-A3B           22 GB   35B MoE     3B        Daily driver
 Qwen3.5-27B               17 GB   27B dense   27B       Reasoning
 Qwen3.5-122B-A10B         77 GB   122B MoE    10B       Smartest Qwen
 Qwen3.5-0.8B              1.2 GB  0.8B dense  0.8B      Titles/labels
 Qwen3.5-2B                2.5 GB  2B dense    2B        Light summaries
 Qwen3.5-4B                4.5 GB  4B dense    4B        Summaries+vision
 Qwen3-Coder-Next          45 GB   80B MoE     3B        Coding agent
 Qwen3-VL-8B               6 GB    8B dense    8B        Fast PDF parser
 Qwen3-VL-32B              20 GB   32B dense   32B       Accurate PDF parser
 Qwen3-TTS (all)           12 GB   0.6-1.7B    -         Text-to-speech (Python)
 gpt-oss-120B              70 GB   117B MoE    5.1B      OpenAI, superfast
 Mistral Small 4           74 GB   119B MoE    6B        European unified
 GLM-4.7-Flash             18 GB   30B MoE     3B        Fast agent/coder
 GLM-4.5-Air               55 GB   106B MoE    12B       Agent specialist
 Nemotron-3-Nano           23 GB   30B MoE     3B        Small reasoner
 Nemotron-3-Super          83 GB   120B MoE    12B       Large reasoner
 LFM2-350M                 0.4 GB  350M dense  350M      Instant classifier
 LFM2-700M                 0.8 GB  700M dense  700M      Fast extraction
 LFM2-1.2B                 1.4 GB  1.2B dense  1.2B      Light tasks
 LFM2-2.6B                 3 GB    2.6B dense  2.6B      General small
 LFM2-2.6B-Exp             3 GB    2.6B dense  2.6B      Best instr. following
 LFM2-8B-A1B               5 GB    8B MoE      1.5B      Fast MoE
 LFM2-24B-A2B              185 GB  24B MoE     2B        All quants (Q4=14GB)
 LFM2.5-1.2B               1.4 GB  1.2B dense  1.2B      RL-trained
 Aya-23-8B                 8.5 GB  8B dense    8B        Translation (23 langs)
 ─────────────────────────────────────────────────────────────────

 NOTE: Qwen3-TTS runs via Python (pip install qwen-tts), not llama.cpp.
 NOTE: Vision models (Qwen3-VL) need --mmproj flag, serve separately.
 NOTE: LFM2-24B downloads ALL quants. Use Q8_0 (25GB) or Q4_K_M (14GB).

EOF
