# Local LLM Model Collection

**Hardware:** 2× HP ZBook Ultra G1a — AMD Ryzen AI Max+ 395 (Strix Halo), 128GB LPDDR5x each  
**OS:** openSUSE Tumbleweed — Vulkan backend via kyuz0 container  
**Inference:** llama-server (llama.cpp) in Podman, router mode with auto-load/unload  

---

## Daily Drivers

| Model | Params (total/active) | Size Q4 | Context | License | Origin |
|---|---|---|---|---|---|
| **Qwen3.5-35B-A3B** | 35B / 3B | ~22 GB | 262K | Apache 2.0 | Alibaba, Hangzhou |
| **Qwen3.5-27B** | 27B / 27B (dense) | ~17 GB | 131K | Apache 2.0 | Alibaba, Hangzhou |
| **Qwen3.5-122B-A10B** | 122B / 10B | ~77 GB | 32K (tight) | Apache 2.0 | Alibaba, Hangzhou |

- **Qwen3.5-35B-A3B** — Primary daily driver. MoE, fast, 201 languages, multimodal (text+vision). Best all-rounder.
- **Qwen3.5-27B** — Dense model, every parameter active. Stronger per-token reasoning than MoE models. Great for math, logic.
- **Qwen3.5-122B-A10B** — Smartest Qwen on single machine. Tight on RAM with large context — reduce to 16-32K ctx.

---

## Coding

| Model | Params (total/active) | Size Q4 | Context | License | Origin |
|---|---|---|---|---|---|
| **Qwen3-Coder-Next** | 80B / 3B | ~45 GB | 65K | Apache 2.0 | Alibaba, Hangzhou |
| **GLM-4.7-Flash** | 30B / 3B | ~18 GB | 32K | MIT | Zhipu AI (Z.ai), Beijing |

- **Qwen3-Coder-Next** — Dedicated coding agent. 44.3% SWE-Bench Pro. Comparable to Sonnet 4.5 on agentic coding.
- **GLM-4.7-Flash** — Fast coding + agent tool calling. MIT license. Strong on terminal-based tasks.

---

## Agentic / Tool Calling

| Model | Params (total/active) | Size Q4 | Context | License | Origin |
|---|---|---|---|---|---|
| **GLM-4.5-Air** | 106B / 12B | ~55 GB | 128K | MIT | Zhipu AI (Z.ai), Beijing |
| **gpt-oss-120B** | 117B / 5.1B | ~61 GB | 128K | Apache 2.0 | OpenAI, San Francisco |
| **Mistral Small 4** | 119B / 6B | ~74 GB | 128K | Apache 2.0 | Mistral AI, Paris |

- **GLM-4.5-Air** — Purpose-built for agents. Best tool calling benchmarks (τ-Bench, BFCL v3). Hybrid thinking/non-thinking modes.
- **gpt-oss-120B** — OpenAI's first open model. 128 experts, top-4 routing, only 4.4% activation = extremely fast. Text-only, no vision.
- **Mistral Small 4** — Unified model: chat + reasoning + vision + coding. European (Paris). Good at generating concise output.

---

## NVIDIA Models

| Model | Params (total/active) | Size Q4 | Context | License | Origin |
|---|---|---|---|---|---|
| **Nemotron-3-Nano** | 30B / 3B | ~23 GB | 32K | NVIDIA Open | NVIDIA, Santa Clara |
| **Nemotron-3-Super** | 120B / 12B | ~83 GB | 32K | NVIDIA Open | NVIDIA, Santa Clara |

- **Nemotron-3-Nano** — Lightweight reasoning. Good for constrained workloads.
- **Nemotron-3-Super** — Very new, may need latest llama.cpp build. Requires container rebuild to work in kyuz0.

---

## LFM2 Family (Liquid AI) — Hybrid Architecture

Non-transformer models. 2× faster decode than equivalent Qwen on CPU. Minimal KV cache overhead. Best for fast structured tasks: titles, labels, extraction, classification.

| Model | Params (total/active) | Size Q8 | Context | License | Origin |
|---|---|---|---|---|---|
| **LFM2-350M** | 350M / 350M | ~0.4 GB | 8K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-700M** | 700M / 700M | ~0.8 GB | 8K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-1.2B** | 1.2B / 1.2B | ~1.4 GB | 16K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-2.6B** | 2.6B / 2.6B | ~3 GB | 16K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-2.6B-Exp** | 2.6B / 2.6B | ~3 GB | 16K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-8B-A1B** | 8.3B / 1.5B | ~5 GB | 16K | LFM 1.0 | Liquid AI, Boston |
| **LFM2-24B-A2B** | 24B / 2B | ~25 GB | 32K | LFM 1.0 | Liquid AI, Boston |
| **LFM2.5-1.2B** | 1.2B / 1.2B | ~1.4 GB | 16K | LFM 1.0 | Liquid AI, Boston |

- **LFM2-2.6B-Exp** — Best instruction following at this size. IFBench score surpasses DeepSeek R1 (263× larger).
- **LFM2-24B-A2B** — Star of the family. 112 tok/s on AMD CPU. Only 2B active from 24B total. Downloaded with all quants (Q4–BF16).
- **LFM2-8B-A1B** — MoE, quality of 3-4B dense, faster than Qwen3-1.7B.

---

## Small Models (Previews, Titles, Summaries)

| Model | Params | Size Q8 | Context | License | Origin |
|---|---|---|---|---|---|
| **Qwen3.5-0.8B** | 0.8B | ~1.2 GB | 32K | Apache 2.0 | Alibaba, Hangzhou |
| **Qwen3.5-2B** | 2B | ~2.5 GB | 32K | Apache 2.0 | Alibaba, Hangzhou |
| **Qwen3.5-4B** | 4B | ~4.5 GB | 32K | Apache 2.0 | Alibaba, Hangzhou |

- All three are multimodal (text + vision). Useful when small model needs to "see" an image.
- For pure text speed tasks, LFM2 models are faster due to hybrid architecture.

---

## Translation

| Model | Params | Size Q8 | Languages | License | Origin |
|---|---|---|---|---|---|
| **Aya-23-8B** | 8B | ~8.5 GB | 23 (incl. Czech) | CC-BY-NC 4.0 | Cohere, Toronto |

- Dedicated multilingual translation model. Supports Czech, English, German, French, Japanese, Korean, and 17 more.
- For casual translation, Qwen3.5-35B handles Czech well via prompting — Aya is for dedicated translation pipelines.

---

## Vision / PDF Parsing

| Model | Params | Size Q4 | Notes | License | Origin |
|---|---|---|---|---|---|
| **Qwen3-VL-8B** | 8B | ~5 GB | Fast PDF OCR | Apache 2.0 | Alibaba |
| **Qwen3-VL-32B** | 32B | ~20 GB | Best accuracy | Apache 2.0 | Alibaba |

- Feed PDF pages rendered as images → model extracts text, tables, layout.
- Requires `--mmproj` flag — serve separately from router mode.
- Also available: **GLM-OCR** (0.9B, Python SDK: `pip install glmocr`) and **MinerU** (`pip install mineru[all]`) for PDF→Markdown pipelines.

---

## Text-to-Speech

| Model | Params | Languages | License | Origin |
|---|---|---|---|---|
| **Qwen3-TTS-1.7B-CustomVoice** | 1.7B | 10 (EN, DE, FR, JA, KO...) | Apache 2.0 | Alibaba |
| **Qwen3-TTS-1.7B-VoiceDesign** | 1.7B | 10 | Apache 2.0 | Alibaba |
| **Qwen3-TTS-1.7B-Base** | 1.7B | 10 | Apache 2.0 | Alibaba |
| **Qwen3-TTS-0.6B-CustomVoice** | 0.6B | 10 | Apache 2.0 | Alibaba |
| **Qwen3-TTS-0.6B-Base** | 0.6B | 10 | Apache 2.0 | Alibaba |
| **Qwen3-TTS-Tokenizer-12Hz** | small | — | Apache 2.0 | Alibaba |

- **Not llama.cpp compatible.** Runs via Python: `pip install qwen-tts`
- CustomVoice = 9 built-in voices + style control. VoiceDesign = create voices from text descriptions. Base = 3-second voice cloning.
- 97ms end-to-end latency. No Czech — supports EN, ZH, JA, KO, DE, FR, RU, PT, ES, IT.

---

## Speech-to-Text

| Tool | Model | Size | Czech support | Install |
|---|---|---|---|---|
| **faster-whisper** | large-v3 | ~3 GB | Yes (needs large) | `pip install faster-whisper` |

- CPU inference with int8 quantization. Czech requires `large-v3` minimum — medium is borderline, small is insufficient.

---

## Image Generation

| Tool | Models | Install |
|---|---|---|
| **stable-diffusion.cpp** | FLUX.2 Dev, FLUX.1 Schnell, Qwen-Image, Z-Image | Build from source with `-DGGML_VULKAN=ON` |
| **ComfyUI** | All diffusion models + LoRAs + ControlNet | Python, node-based GUI |

- Not llama.cpp. Separate binary, same ggml library. Runs on Vulkan.
- FLUX.2 Dev Q4 = ~8GB. Your 128GB machine is massive overkill for image gen — can run alongside chat LLMs.

---

## Models Too Big for Single Machine

These need the dual Strix Halo Thunderbolt cluster (256GB combined) or API access.

| Model | Total / Active | Min Size | Notes |
|---|---|---|---|
| **GLM-5** | 744B / 44B | ~180 GB Q2 | Strongest open model. MIT. Trained on Huawei chips. |
| **MiniMax M2.5** | 230B / ? | ~101 GB Q3 | SWE-bench SOTA (80.2%). API: $0.30/$1.20 per 1M tokens. |
| **DeepSeek V3.2** | 685B / 37B | ~200 GB Q2 | Best value via API ($0.14 input). |
| **Qwen3.5-397B-A17B** | 397B / 17B | ~200 GB Q3 | Biggest Qwen. |
| **DeepSeek V4** | ~1T / ~32B | ~250 GB Q2 | Not released yet. Expected imminently. |

---

## Quick Reference: What to Use When

| Task | Best Model | Why |
|---|---|---|
| General chat | qwen3.5-35b | Fast, multilingual, multimodal |
| Deep reasoning | qwen3.5-27b or qwen3.5-122b | Dense = consistent, 122b = smartest |
| Coding agent | qwen3-coder-next | Purpose-built for SWE tasks |
| Fast coding | glm-4.7-flash | 3B active, MIT, great tool calling |
| Agent/tool calling | glm-4.5-air | Designed for agents, best τ-Bench |
| Quick titles/labels | lfm2-2.6b-exp | Hybrid arch, blazing fast |
| Bulk extraction | lfm2-24b | 2B active, 112 tok/s, incredible speed |
| Translation | aya-23-8b or qwen3.5-35b | Aya for dedicated, Qwen for casual |
| PDF parsing | qwen3-vl-8b | Vision model, render pages as images |
| Image generation | FLUX.2 Dev via sd.cpp | Photorealistic, readable text |
| Speech-to-text | faster-whisper large-v3 | Best Czech support |
| Text-to-speech | Qwen3-TTS-1.7B | 97ms latency, 10 languages |

---

## Server Configuration

All models served from single endpoint via llama-server router mode:

```bash
llama-server \
    --models-preset /var/models/models.ini \
    --models-max 2 \
    --host 0.0.0.0 --port 8080 \
    --sleep-idle-seconds 300
```

- Models auto-load on first API request, auto-unload after 5 min idle.
- Max 2 models loaded simultaneously (adjustable).
- API: `http://localhost:8080/v1/chat/completions` — specify model by name.
- Vision models (Qwen3-VL) served separately due to `--mmproj` requirement.
- TTS models run via Python (`qwen-tts` package), not llama-server.
