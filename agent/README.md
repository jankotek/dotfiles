# Local models

All download scripts work without a Hugging Face token for public files. Set
`HF_TOKEN` or `HUGGING_FACE_HUB_TOKEN` when a repository requires access; the
scripts send an authorization header only when a token is set.

Check the fixed filenames against current Hugging Face listings and show GGUFs
published in the last 30 days that the scripts do not select:

```bash
/opt/jan/agent/check-model-downloads.py
```

Use `--since-days 7` for a shorter window. `UPDATED` marks a selected file
changed within the window; `OTHER` marks a GGUF outside the download lists.
The check reads remote metadata only. The download scripts still follow
`main` for each named file; rerunning one downloads that file's current
contents. A renamed file, a new quant, or a new model repository needs a
script update.

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

The ggml-org Qwen3.8-27B repository also publishes DFlash drafters. Add one
to the BF16, Q8_0, or Q4_K_M download with `DOWNLOAD_DFLASH=1`:

```bash
cd /var/models
DOWNLOAD_DFLASH=1 /opt/jan/agent/download-qwen3.8-27b-q8-0.sh
```

The corresponding router presets end in `-DFlash`; the existing presets
continue to use MTP. The Q4_K_M downloader gets the publisher's Q4_0 DFlash
head, while the BF16 and Q8_0 downloaders get matching DFlash heads.

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
