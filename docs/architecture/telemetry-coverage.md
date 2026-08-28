# AI CLI Telemetry Coverage

Which AI CLIs in this stack can emit OpenTelemetry, which are wired, and — for
the ones that cannot — the vendor source that says so. A tool absent from this
page has not been assessed; "no telemetry configured" is not evidence that the
tool lacks support.

Endpoint values are site-specific and live in the consumer's own configuration,
never here. See [system-integration-map](system-integration-map.md#telemetry-pipeline)
for the signal/endpoint shape.

## Supported and wired here

| Tool | Configured via | Signals |
|---|---|---|
| Claude Code | `userConfig.telemetry.{enable,otlpEndpoint,tracesEndpoint}` → `modules/claude/settings-env.nix` | metrics, logs, spans |
| MLX model server | `programs.mlx.telemetry.{enable,otlpEndpoint}` → `modules/mlx/launchd.nix` | inherited by llama-swap and worker children |

## Supported upstream, not wired here

Each of these has first-party OTLP support. None is wired in this repo yet;
wiring one means adding its own config surface, not reusing Claude Code's.

| Tool | Configuration surface | Protocol notes | Source |
|---|---|---|---|
| OpenAI Codex CLI | `[otel]` in `~/.codex/config.toml` (`exporter`, `metrics_exporter`, `trace_exporter`, each with an `otlp-http`/`otlp-grpc` sub-table); also honors `OTEL_EXPORTER_OTLP_ENDPOINT` | `otlp-http` supported. Opt-in, off by default. `codex mcp-server` emits nothing; `codex exec` emits traces and logs but no metrics | [openai/codex observability](https://deepwiki.com/openai/codex/9.4-observability-and-telemetry) |
| Gemini CLI | `telemetry` object in `.gemini/settings.json` (`enabled`, `target`, `otlpEndpoint`, `otlpProtocol`); env vars override settings, CLI flags override both | OTLP is the wire protocol for both the local-collector and hosted targets | [gemini-cli docs/cli/telemetry.md](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/telemetry.md) |
| GitHub Copilot CLI | `COPILOT_OTEL_ENABLED` + `OTEL_EXPORTER_OTLP_ENDPOINT`, forwarded from the editor extension to the agent-host process; enterprise-managed settings can mandate an endpoint centrally | HTTP only — a gRPC config is silently downgraded | [Copilot SDK observability](https://docs.github.com/en/copilot/how-tos/copilot-sdk/observability/opentelemetry) |
| qwen-code | `telemetry.otlpEndpoint`/`otlpProtocol` in `.qwen/settings.json`; `QWEN_TELEMETRY_OTLP_*` env vars take precedence over generic `OTEL_*`; `--telemetry-otlp-endpoint` flag | `otlpProtocol: "http"` auto-appends the signal path; gRPC also supported | [qwen-code telemetry docs](https://github.com/QwenLM/qwen-code/blob/main/docs/developers/development/telemetry.md) |
| Cursor | **Org-level only** — configured in Cursor's web admin (Team Settings → OpenTelemetry Export), not per-process env vars. There is no documented client-side `OTEL_*` support | OTLP/HTTP binary protobuf only; gRPC and JSON are explicitly unsupported | [Cursor OpenTelemetry export](https://cursor.com/docs/enterprise/opentelemetry-export) |

## Degraded

| Tool | State | Source |
|---|---|---|
| OpenCode | Advertises `experimental_opentelemetry` in `opencode.json`, but no span collector is wired behind it — effectively non-functional as documented. The working path is a third-party plugin (`OPENCODE_ENABLE_TELEMETRY`, `OPENCODE_OTLP_ENDPOINT`, `OPENCODE_OTLP_PROTOCOL`), not first-party | [opencode-plugin-otel](https://github.com/DEVtheOPS/opencode-plugin-otel) |

## No OTLP support

| Tool | Finding | Source |
|---|---|---|
| Antigravity CLI (`agy`) | Distinct from Gemini CLI despite the shared settings-directory lineage. Standard `OTEL_EXPORTER_OTLP_*` env vars produce no output — reproduced by a user in an open feature request. Only a non-OTLP product-analytics toggle exists | [antigravity-cli#366](https://github.com/google-antigravity/antigravity-cli/issues/366) |
| fabric | No telemetry, OTLP, or tracing surface. `--debug` is local verbosity and `--show-metadata` writes token counts to stderr; neither is exported | [fabric README](https://github.com/danielmiessler/fabric) |
| cecli | No telemetry surface found across the documented configuration sections. Not exhaustive — the per-format config subpages were not individually checked, so treat this as "none found", not "proven absent" | [cecli docs](https://cecli.dev/docs/) |

## Not OTLP: the transcript-file path

Several tools that emit no OTLP still produce observable data, because their
session transcripts are tailed off disk by a separate log-shipping agent and
forwarded to the log platform. That path is owned by the host configuration,
not by this repo, and it covers tools regardless of their OTLP support. It
carries per-message token counts but no latency, tool duration, or subagent
structure — which is what spans add and files cannot.
