# qwen3-next-80b-instruct — split out of catalog-data.nix for the per-file
# 12KB gate (same split-rather-than-exempt pattern as catalog-lib.nix). Merged
# into the same catalog attrset by catalog-data.nix; see that file for the
# entry schema and catalog-lib.nix for the shared serve-arg helpers.
let
  inherit (import ./catalog-lib.nix) hybridNoPaged swapFlags;
in
{
  # Instruct sibling of the Thinking brain (catalog-data.nix qwen3-next-80b) —
  # the 2026-07-17 agentic-bench winner and new fleet brain (perfect 1.0
  # valid_tool_call_rate across every single-stream cell, thinking on/off x
  # ctx small/large x stream/nostream; envelopes in HF JacobPEvans/mlx-benchmarks).
  # Same qwen3_next hybrid-attention constraint as the Thinking entry: paged
  # cache off (hybridNoPaged) because paged-block reconstruction fails every
  # multi-turn request; the standard KV cache runs instead. Resident profile
  # mirrors the OptiQ brain it replaces — 65536 serving window (Hermes' >=64K
  # floor; also serves as the compression model), 16 GB KV. SINGLE-SLOT (40B+
  # policy, below): maxNumSeqs=1 at the engine AND concurrencyLimit=1 at the
  # proxy — this family's ceiling crashes hit under any concurrency, and
  # prefix-cache reconstruction is broken upstream (mlx-lm#1162) so
  # every tool turn full-reprefills 85-100s; batching multiple such requests
  # only time-slices one GPU and balloons every caller's latency into the 429
  # storm. One request at a time, queue the rest.
  qwen3-next-80b-instruct = {
    model = "mlx-community/Qwen3-Next-80B-A3B-Instruct-4bit";
    weightGb = 42.0;
    # qwen3_next HYBRID: 48 layers, full_attention_interval=4 → only 12
    # full-attention layers carry paged KV; the other 36 gated-delta-net layers
    # carry none (mlx-lm qwen3_next.py:360 is_linear, :450 make_cache). Counting
    # all 48 would over-reserve KV by 4x. kvHeads=2, headDim=256.
    # perTokenKvBytes = 2*12*2*256*2 = 24576 B/token (24 KiB/token) — LOWER than
    # the 30B dense models despite 2.4x the weights, because 3/4 of its layers
    # are KV-free. (Thinking sibling qwen3-next-80b has identical arch.)
    kv = {
      kvLayers = 12;
      kvHeads = 2;
      headDim = 256;
      kvDtypeBytes = 2;
    };
    args = [ ];
    # 40B+ SINGLE-SLOT POLICY (user directive 2026-07-21): no concurrency on any
    # 40B+ model. Two layers, defense in depth: concurrencyLimit=1 makes
    # llama-swap QUEUE excess requests (single in-flight to the worker) instead
    # of parallel-dispatch + 429-storm; maxNumSeqs=1 (in flags) caps the engine
    # batch width so even a proxy regression cannot re-enable batching. This 80B
    # aborts with metal::malloc resource-limit errors under concurrent requests
    # (Hermes crons + fleet traffic), and the crash-loop respawn storm exhausts
    # the per-uid process table — reliability over throughput.
    concurrencyLimit = 1;
    classes = {
      resident.flags = hybridNoPaged // {
        cacheMemoryMb = 8192;
        maxNumSeqs = 1;
        maxRequestTokens = 65536;
      };
      swap.flags =
        swapFlags
        // hybridNoPaged
        // {
          cacheMemoryMb = 4096;
          maxNumSeqs = 1; # 40B+ single-slot policy (overrides swapFlags maxNumSeqs=2)
        };
    };
  };
}
