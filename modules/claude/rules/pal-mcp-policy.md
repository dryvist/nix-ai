---
description: PAL MCP availability protocol — clink/consensus have no native fallback; chat/listmodels re-enabled
---

# PAL MCP Policy

PAL MCP exposes four enabled tools:

| Tool | Purpose |
| ---- | ------- |
| `chat` | Single-model inference via Bifrost. Local MLX and cloud models. |
| `listmodels` | Enumerate available models (local MLX + cloud via OpenRouter). |
| `clink` | Parallel multi-model prompting. No native equivalent. |
| `consensus` | Multi-model voting/agreement. No native equivalent. |

All other PAL tools have native Claude Code or Bifrost equivalents and are
disabled. See the Phase 3 audit matrix on `JacobPEvans/nix-ai#450` for the
full mapping.

The availability-check protocol below **applies to `clink` and `consensus`**
— the two tools with no fallback. `chat` and `listmodels` have degraded
alternatives (`curl http://localhost:30080/v1/chat/completions` and
`curl http://localhost:30080/v1/models`), so a failed PAL server is less
critical for them.

Silently skipping a multi-model step because `ToolSearch` came back empty is
the failure mode this rule exists to prevent.

## Configuration

- **DEFAULT_MODEL=auto**: PAL picks a model alias per-task; for single-model
  work this flows through `CUSTOM_API_URL` → Bifrost → the right provider.
  `clink`/`consensus` use their own multi-provider fan-out, not Bifrost.
- **MLX model prefix**: Bifrost requires `provider/model` format. Local MLX
  models are addressed as `mlx-local/mlx-community/<model-id>` (e.g.
  `mlx-local/mlx-community/Qwen3.5-35B-A3B-4bit`). The `mlx-local/` prefix
  is baked into `custom_models.json` and `CUSTOM_MODEL_NAME` by the Nix module
  — do not use bare `mlx-community/` names when calling Bifrost directly.
- **Secrets**: Local PAL subprocess secrets (API keys, config) are injected by
  the `doppler-mcp` wrapper at launch time. This is separate from the Doppler
  **K8s Operator** that syncs Bifrost's in-cluster provider keys — different
  layer, don't conflate.
- **Bifrost is not a replacement** for `clink`/`consensus` — Bifrost is a
  single-request router, not a parallel orchestrator.

## Availability Check Protocol (MANDATORY for clink/consensus)

Three-step escalation. All three steps MUST be followed before declaring
`clink` or `consensus` unavailable.

### Step 1: ToolSearch (target the specific tool you need)

Search directly for the tool you're about to use rather than relying on a
generic `mcp__pal` prefix — PAL exposes ~18 tools and a low `max_results`
will truncate the list before `consensus`/`clink` appear.

```text
ToolSearch("select:mcp__pal__clink", max_results=5)
ToolSearch("select:mcp__pal__consensus", max_results=5)
```

If the target tool appears → proceed directly to using it.
If not found → **DO NOT STOP. Go to Step 2.** (deferred tools may not be populated yet)

### Step 2: Check server status

```bash
claude mcp list 2>/dev/null | grep "^pal:"
```

| Status | Action |
| ------ | ------ |
| `✓ Connected` | ToolSearch again for whichever tool is missing: `select:mcp__pal__clink` or `select:mcp__pal__consensus` |
| `✗ Failed` | Go to Step 3 |
| Not listed | Tell user: "PAL not registered. Run `check-pal-mcp` to diagnose." |

### Step 3: Attempt reconnection

```bash
claude mcp remove pal -s user && claude mcp add pal -s user -- pal-mcp
```

Wait 5s, re-check with `claude mcp list`.
**CRITICAL**: Mid-session reconnected tools are invisible to ToolSearch.
Tell user: "PAL reconnected but requires session restart to load tools."

## NEVER-Do List

- NEVER skip `clink`/`consensus` based on ToolSearch alone
- NEVER declare either unavailable without completing all 3 steps
- NEVER silently omit a multi-model phase because PAL looked absent
- NEVER substitute Bifrost for `clink`/`consensus` — Bifrost cannot fan out
  to multiple models in one request
- NEVER suggest manual workarounds (e.g., sequential `chat` calls imitating
  `consensus`) without first attempting the protocol above

## Diagnostics

If PAL fails after the protocol:

1. `check-pal-mcp` — full health check (Doppler auth, secrets, MCP status)
2. `cat ~/.local/state/doppler-mcp.log` — recent invocation log
3. `doppler me` — verify Doppler authentication

## See also

- **Bifrost health**: `curl http://localhost:30080/health`
- **Bifrost model catalog**: `curl http://localhost:30080/v1/models`
- **Bifrost MCP registration**: `bifrost` block in `modules/mcp/catalog.nix`
- **Phase 3 audit matrix** (full PAL → native mapping):
  [JacobPEvans/nix-ai#450](https://github.com/JacobPEvans/nix-ai/issues/450)
