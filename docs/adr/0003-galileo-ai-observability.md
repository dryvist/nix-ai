# ADR 0003: Galileo AI Observability — Fail-Closed Homelab Integration

**Status**: Accepted
**Date**: 2026-05-22

## Documents in This Directory

_This ADR is part of [`docs/adr/`](README.md)._

## Context

Galileo (galileo.ai) is an AI observability platform with hallucination detection,
Signals-based failure analysis, and chain-of-thought evals. The goal is to collect
LLM inference traces from the local homelab stack (MLX inference + Bifrost gateway)
in Galileo alongside the existing Cribl/Splunk pipeline.

**Hard constraints:**

1. The operator works at Cisco/Splunk. Daily prompts include Splunk product content,
   internal engineering material, and client data. None of this may leave the local
   network in trace payloads.
2. Claude Code, Codex CLI, and Gemini CLI are not instrumented — only surfaces that
   are already isolated from work content (local MLX inference and Bifrost's
   cloud-model paths when explicitly opted in).
3. The Splunk/Cribl pipeline must not regress. The Galileo branch is additive.

## Decision

**Scope:** MLX inference stack + Bifrost gateway only. All AI CLI tools excluded.

**Default posture:** Fail-closed. No traces reach Galileo unless the operator:

1. Runs `galileo-on` from an explicitly allowlisted working directory (shell function
   in `nix-home`, not in this repo — see cross-repo dependencies below).
2. The outbound request carries the `X-Trace-Sink: galileo` HTTP header (set by the
   wrapper function).
3. The OTEL Collector's routing connector passes it (drops anything without the header).
4. The content denylist processor in the Galileo-bound pipeline finds no match.

**Dual gate:** header-based routing gate AND content-based denylist. Both must pass.

**Galileo tier:** SaaS Free ($0/mo, 5K traces/mo). Revisit if the trace count
exceeds the cap after 48h of normal use — add tail-sampling before upgrading.

**Secret injection:** `GALILEO_API_KEY` follows Pattern 3 (Kubernetes Doppler Operator)
in `docs/architecture/secrets-and-injection.md` — the same pattern as Bifrost and
Cribl. The key is injected into the OTEL Collector pod by the Doppler Operator in
the OrbStack cluster. It never appears in this repo, the Nix store, or `~/.claude.json`.

**No Galileo SDK:** Galileo accepts OTLP/HTTP at `https://api.galileo.ai/otel/traces`
with API key + project + logstream in request headers. A dedicated OTLP exporter in
the existing OTEL Collector is sufficient. No Python SDK, no agent-side library.

## Consequences

**Easier:**

- Galileo evals (hallucination detection, Signals) work on real homelab inference traces
  once the collector and Bifrost changes land in `orbstack-kubernetes`.
- The `programs.mlx.telemetry.enable` option in this repo is the correct long-term hook
  even before vllm-mlx 0.2.9 natively emits OTLP spans; future versions of the
  MLX stack that add OTel support will inherit the LaunchAgent env vars automatically.
- Kill switch is cheap: set `programs.mlx.telemetry.enable = false` (removes the
  LaunchAgent env vars) or remove the `otlphttp/galileo` exporter from the collector
  pipeline in `orbstack-kubernetes`. Either stops all Galileo traffic within seconds.

**Harder:**

- `galileo-on` requires a deliberate opt-in per shell session. Passive tracing of
  ad-hoc inference is not supported by design.
- VisiCore instrumentation (company) is deferred. When it lands, use a separate
  Galileo log stream (`visicore-prod`) and apply stricter redaction there.

## Cross-Repo Dependencies

This ADR spans three repos. The nix-ai changes (this file, telemetry option) are
self-contained. The remaining work:

| Repo | Change | Status |
|------|--------|--------|
| `nix-ai` | `programs.mlx.telemetry.enable` option + LaunchAgent env | Done (this PR) |
| `orbstack-kubernetes` | OTEL Collector: `otlphttp/galileo` exporter, routing connector, content denylist processor | Pending |
| `orbstack-kubernetes` | Bifrost: OTel exporter + header→span-attr mapping for `X-Trace-Sink` | Pending |
| `nix-home` | `galileo-on` zsh function + `gcurl` wrapper + `~/.config/galileo/allowlist.toml` | Pending |
| `orbstack-kubernetes` | Doppler Operator: `GALILEO_API_KEY` in `ai-ci-automation/prd` | Pending (manual Doppler config) |

No Galileo traffic flows to the SaaS until all five rows are complete.
