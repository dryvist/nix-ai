# Every long option `vllm-mlx serve` accepts, as a fixture.
#
# WHY A HAND-PASTED LIST. ./mlx-worker-flag-surface.nix derives its allowed set
# from the builder's own vllm-mlx branch, which is circular: a flag the builder
# emits is allowed BECAUSE the builder emits it, so a spelling the CLI has never
# accepted passes. That is exactly how `--draft-block-size` (mlx-vlm's spelling,
# not vllm-mlx's) survived under a green check. This list is the external truth
# that closes the loop.
#
# PROVENANCE. Captured from the pinned release, filtered to long options:
#
#   uvx --from 'vllm-mlx==0.4.1' vllm-mlx serve --help \
#     | grep -oE '^  --[a-z0-9-]+' | tr -d ' ' | sort -u
#
# BUMP RULE. Re-run the command above when versions.vllmMlx moves and replace
# this list wholesale. Editing an entry to make a check pass inverts the point
# of the file: the list states what the CLI accepts, never what we wish it did.
#
# `model` is positional on the real CLI and is NOT here. The rendered command
# spells it `--model`, which the mlx-model-server adapter (modules/mlx/
# default.nix) consumes itself before exec'ing `vllm-mlx serve "$model"`, so it
# never reaches argparse. The check allows it explicitly for that reason.
{
  version = "0.4.1";
  flags = [
    "--api-key"
    "--auto-unload-idle-seconds"
    "--cache-memory-mb"
    "--cache-memory-percent"
    "--chunked-prefill-tokens"
    "--completion-batch-size"
    "--continuous-batching"
    "--default-chat-template-kwargs"
    "--default-min-p"
    "--default-presence-penalty"
    "--default-repetition-penalty"
    "--default-temperature"
    "--default-thinking-token-budget"
    "--default-top-k"
    "--default-top-p"
    "--disable-prefix-cache"
    "--download-retries"
    "--download-timeout"
    "--embedding-model"
    "--enable-auto-tool-choice"
    "--enable-metrics"
    "--enable-mtp"
    "--enable-prefix-cache"
    "--gpu-memory-utilization"
    "--host"
    "--kv-cache-min-quantize-tokens"
    "--kv-cache-quantization"
    "--kv-cache-quantization-bits"
    "--kv-cache-quantization-group-size"
    "--lazy-load-model"
    "--max-audio-upload-mb"
    "--max-cache-blocks"
    "--max-kv-size"
    "--max-num-seqs"
    "--max-request-tokens"
    "--max-tokens"
    "--max-tts-input-chars"
    "--mcp-config"
    "--mllm"
    "--mllm-draft-block-size"
    "--mllm-draft-kind"
    "--mllm-draft-model"
    "--mllm-prefill-step-size"
    "--models-config"
    "--mtp-num-draft-tokens"
    "--mtp-optimistic"
    "--no-memory-aware-cache"
    "--offline"
    "--paged-cache-block-size"
    "--port"
    "--prefill-batch-size"
    "--prefill-step-size"
    "--prefix-cache-size"
    "--rate-limit"
    "--reasoning-parser"
    "--rerank-model"
    "--served-model-name"
    "--specprefill"
    "--specprefill-backbone-pct"
    "--specprefill-draft-model"
    "--specprefill-keep-pct"
    "--specprefill-threshold"
    "--ssd-cache-dir"
    "--ssd-cache-max-gb"
    "--stream-interval"
    "--timeout"
    "--tool-call-parser"
    "--trust-remote-code"
    "--use-paged-cache"
    "--warm-prompts"
  ];
}
