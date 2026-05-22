# Galileo AI Observability — Operator Runbook

See [ADR 0003](../adr/0003-galileo-ai-observability.md) for design decisions
and [system-integration-map](../architecture/system-integration-map.md) for topology.

## Prerequisites (one-time setup)

All five rows in the ADR's cross-repo table must be complete before any traces
reach Galileo. Check each before assuming the pipeline is live:

1. `programs.mlx.telemetry.enable = true` in your nix-darwin config (this repo).
2. `orbstack-kubernetes`: OTEL Collector has `otlphttp/galileo` exporter, routing
   connector, and content denylist processor deployed.
3. `orbstack-kubernetes`: Bifrost emits OTel spans and maps `X-Trace-Sink` header
   to `trace.sink` span attribute.
4. `nix-home`: `galileo-on` zsh function and `gcurl` wrapper are activated.
5. Doppler (`ai-ci-automation/prd`): `GALILEO_API_KEY` is set, Doppler Operator
   has synced it to the OTEL Collector pod.

## Daily use

```bash
# From an allowlisted working directory (e.g. ~/git/nix-ai/main):
galileo-on          # sets GALILEO_TRACE=1, prints confirmation

# Hit MLX directly with trace header:
gcurl http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"default","messages":[{"role":"user","content":"hello"}]}'

# Hit Bifrost with trace header (cloud model):
gcurl http://127.0.0.1:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"anthropic/claude-opus-4-7","messages":[{"role":"user","content":"hello"}]}'

# Check Galileo console:
# app.galileo.ai → project: homelab → log stream: default
```

Without running `galileo-on` first, `gcurl` sends no `X-Trace-Sink` header and
the OTEL Collector routing connector drops the span before it reaches Galileo.
Splunk still receives every span regardless.

## Add a path to the allowlist

Edit `~/.config/galileo/allowlist.toml` (not committed — user-owned):

```toml
[[paths]]
path = "~/git/nix-ai"

[[paths]]
path = "~/git/nix-darwin"
```

## Add a denylist term

The content denylist lives in `/etc/galileo/denylist.txt` on the OrbStack node,
injected by Doppler. To add a term:

1. Add the regex pattern to the `GALILEO_CONTENT_DENYLIST` secret in Doppler
   (`ai-ci-automation/prd`). Format: one pattern per line, POSIX ERE, case-insensitive.
2. Restart the OTEL Collector pod: `kubectl rollout restart deployment otel-collector -n monitoring`.
3. Verify the updated denylist is loaded: check collector logs for `denylist loaded N patterns`.

## If a trace lands in Galileo that shouldn't have

1. **Rotate the API key immediately**: Doppler → `ai-ci-automation/prd` → regenerate
   `GALILEO_API_KEY`. Old key stops working within seconds.
2. **Delete the trace in Galileo**: `app.galileo.ai` → project → log stream → find
   the trace → delete (Galileo supports individual trace deletion from the UI).
3. **Expand the denylist**: add the pattern that should have matched.
4. **Redeploy**: restart the OTEL Collector pod to pick up the new key and denylist.

## Check trace count vs. Free tier cap

Free tier allows 5,000 traces per month. To check current usage:

- `app.galileo.ai` → project settings → Usage shows the monthly trace count.

If trending to exceed 5K at your current rate, add tail-sampling to the collector:

```yaml
processors:
  probabilistic_sampler:
    hash_seed: 42
    sampling_percentage: 20   # 20% of MLX-internal traces; keep 100% CLI traces
```

Apply to the `traces/galileo` sub-pipeline only, not the Cribl/Splunk pipeline.

## Kill switches

| Action | Effect |
|--------|--------|
| `programs.mlx.telemetry.enable = false` + rebuild | Removes OTel env vars from vllm-mlx LaunchAgent; MLX stops sending to collector |
| Remove `otlphttp/galileo` from collector pipeline | Stops all Galileo exports; Splunk unaffected |
| Delete `GALILEO_API_KEY` in Doppler | Collector authentication fails; no traces accepted by Galileo |
| Unset `GALILEO_TRACE` in shell | No `X-Trace-Sink` header sent; routing connector drops all spans before Galileo exporter |
