# Local models

All download scripts work without a Hugging Face token for public files. Set
`HF_TOKEN` or `HUGGING_FACE_HUB_TOKEN` when a repository requires access; the
scripts send an authorization header only when a token is set.

The download scripts write beneath the caller's current directory. On a model
build machine, start them from the directory that will contain the model
directories:

```bash
cd /var/models
/opt/jan/agent/download-qwen3.8-27b-q4-k-m.sh
```

That example writes the base model into
`/var/models/Qwen3.8-27B-GGUF-Q4_K_M`. Its router preset shares the BF16 vision
projector and MTP predictor in `/var/models/Qwen3.8-27B`.

For the ggml-org Qwen3.8-27B Q8_0 model with its matching Q8_0 vision
projector and MTP head, run:

```bash
cd /var/models
/opt/jan/agent/download-qwen3.8-27b-q8-0.sh
```

This creates `/var/models/Qwen3.8-27B-GGUF-Q8_0` for the
`Qwen3.8-27B-Q8_0` router preset. Set `OUT_DIR` to use another download
location.

Qwen3.8-Flash-Next is available as Unsloth's `UD-Q4_K_XL` GGUF (four model
shards, about 111 GB total), plus a BF16 vision projector:

```bash
cd /var/models
/opt/jan/agent/download-qwen3.8-flash-next-ud-q4-k-xl.sh
```

The `Qwen3.8-Flash-Next-UD-Q4_K_XL` preset uses the first shard; llama.cpp
loads the other three automatically. It requires llama.cpp b10660 or newer for
the `qwen4exp` architecture. The default binary in `serve-all.sh` is b10456,
so set `LLAMA_BIN` to a newer Vulkan build before serving this preset. This
preset starts with one 32K-token slot to limit cache memory. MTP is omitted
because stock llama.cpp does not support this model's MTP draft heads yet.

Scripts that produce one model directory accept `OUT_DIR`; multi-directory
collections accept `ROOT`:

```bash
OUT_DIR=/data/Qwen3.8-27B-GGUF-Q4_K_M /opt/jan/agent/download-qwen3.8-27b-q4-k-m.sh
ROOT=/data /opt/jan/agent/download-translategemma.sh
```

The completed directories can be copied to `/var/models` on the inference
machine. `llama-models.ini` uses that fixed serving location.

Download all three Qwen3 text-embedding sizes in Q8_0 with one command:

```bash
cd /var/models
/opt/jan/agent/download-qwen3-embedding-q8.sh
```

This creates quant-specific directories for the 0.6B, 4B, and 8B models. Set
`ROOT` to place all three beneath a different directory.
