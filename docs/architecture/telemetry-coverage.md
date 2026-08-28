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
| Codex CLI | the same `userConfig.telemetry` surface → `[otel]` in `modules/codex/settings.nix` | spans |

**Codex takes the endpoint verbatim.** Pointed at `http://host:port` it POSTs to
`/`, appending no signal path — so it is given the full `/v1/traces` URL, the
opposite of the generic endpoint Claude Code treats as a base. Measured on the
wire against a local sink, not inferred. Its `protocol = "binary"` is OTLP/HTTP
protobuf; the encoding is load-bearing, not cosmetic.

## Wired, but emits nothing

| Tool | State |
|---|---|
| MLX model server | `programs.mlx.telemetry` sets the standard `OTEL_*` variables on the llama-swap LaunchAgent, inherited by the `mlx_lm.server` children. **No component in that chain is OpenTelemetry-instrumented**, so setting an endpoint produces no telemetry — verified by scanning the installed `mlx_lm` package and the `llama-swap` binary for any OpenTelemetry reference (none in either). The option is retained because the env is the right shape the moment either gains instrumentation, but do not read its presence as evidence that MLX is observable. |

## Supported upstream, but not reachable here

| Tool | Finding | Evidence |
|---|---|---|
| qwen-code | Supports OTLP, but **cannot talk to this collector**. It accepts only two protocol values — the CLI rejects anything else with `Invalid telemetry OTLP protocol: http/protobuf. Valid values are: grpc, http` — and its `http` mode sends `Content-Type: application/json` (observed on the wire). Every OTLP ingest point in this estate answers **501 to JSON and 200 to protobuf**, and no gRPC listener is open. So it is wired-capable in principle and unreachable in practice. | Measured both ends: qwen's own error text and request content-type; collector response codes per encoding. |

Closing this needs a JSON-accepting or gRPC OTLP route on the collector side —
an infrastructure change, not a client one. Until that exists, configuring qwen
telemetry would send spans that are rejected on arrival, which is exactly the
silently-broken state the rest of this page exists to prevent.

## Not installed on this machine

Assessed and found absent, so there is nothing to wire. Listed because "no
telemetry configured" would otherwise read as an unclosed gap:

| Tool | Upstream OTLP support | Config surface, if it is ever installed |
|---|---|---|
| Gemini CLI | yes | `telemetry` object in `.gemini/settings.json` ([docs](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/telemetry.md)) |
| GitHub Copilot CLI | yes, HTTP only — a gRPC config is silently downgraded | `COPILOT_OTEL_ENABLED` + `OTEL_EXPORTER_OTLP_ENDPOINT` ([docs](https://docs.github.com/en/copilot/how-tos/copilot-sdk/observability/opentelemetry)) |
| cecli | none found | [docs](https://cecli.dev/docs/) — not exhaustive, treat as "none found" |

## Installed, org-level telemetry only

| Tool | Finding | Source |
|---|---|---|
| Cursor / cursor-agent | Configured entirely in Cursor's web admin (Team Settings → OpenTelemetry Export). No documented client-side env var or config file, so there is nothing for this repo to set. OTLP/HTTP binary protobuf only; gRPC and JSON unsupported. | [Cursor OpenTelemetry export](https://cursor.com/docs/enterprise/opentelemetry-export) |

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

## Why the unwired tools are not wired yet

Wiring a tool here means shipping a config that a vendor binary parses at
startup. Codex refuses to start on a config it cannot parse — that is how the
legacy `[profiles.*]` table broke `--profile` — so a guessed schema is not a
cheap mistake. More to the point, this repo's whole position on telemetry is
that configuration which *looks* right proves nothing: a signal counts as
wired when an event from it has been seen in the backend.

Each tool above therefore stays documented rather than configured until its
wiring can be verified against a real event. The schema notes are recorded so
that work starts from evidence rather than from a search result.

## Not OTLP: the transcript-file path

Several tools that emit no OTLP still produce observable data, because their
session transcripts are tailed off disk by a separate log-shipping agent and
forwarded to the log platform. That path is owned by the host configuration,
not by this repo, and it covers tools regardless of their OTLP support. It
carries per-message token counts but no latency, tool duration, or subagent
structure — which is what spans add and files cannot.
