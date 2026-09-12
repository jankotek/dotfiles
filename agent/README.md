# Local models

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

Scripts that produce one model directory accept `OUT_DIR`; multi-directory
collections accept `ROOT`:

```bash
OUT_DIR=/data/Qwen3.8-27B-GGUF-Q4_K_M /opt/jan/agent/download-qwen3.8-27b-q4-k-m.sh
ROOT=/data /opt/jan/agent/download-translategemma.sh
```

The completed directories can be copied to `/var/models` on the inference
machine. `llama-models.ini` uses that fixed serving location.
