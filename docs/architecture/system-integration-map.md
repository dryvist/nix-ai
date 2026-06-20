# System Integration Map

How all AI products in nix-ai connect to each other and to external services.

## Documents in This Directory

_This document is part of [`docs/architecture/`](README.md)._

## Full Integration Diagram

```mermaid
graph TD
    subgraph Clients["AI CLI Clients"]
        CC["Claude Code"]
        GEM["Antigravity CLI"]
        CDX["Codex CLI"]
        COP["Copilot"]
    end

    subgraph Orchestration["Orchestration Layer"]
        MAE["Maestro\n(scheduled sessions)"]
    end

    subgraph Gateway["AI Gateway — K8s :30080"]
        BIF["Bifrost\n(multi-provider router)"]
    end

    subgraph LocalInference["Local Inference — Apple Silicon"]
        LS["llama-swap proxy\n:11434"]
        VLLM["vllm-mlx backends\n:11436+"]
    end

    subgraph WebTools["Web & Pattern Tools"]
        OWU["Open WebUI\n:8080"]
        FAB["Fabric\nCLI + REST :8180"]
    end

    subgraph Cloud["Cloud Providers (via Bifrost)"]
        OR["OpenRouter"]
        OAI["OpenAI"]
        ANT["Anthropic"]
        GGL["Google AI"]
    end

    CC -->|stdio MCP| FAB_MCP["fabric-mcp"]
    CC -->|HTTP MCP| BIF
    CC -->|HTTP MCP| CRIBL["Cribl MCP\n:30030"]
    MAE -->|claude subprocess| CC

    FAB_MCP -->|reads patterns| FAB

    BIF -->|HTTP /v1| LS
    BIF -->|HTTPS| OR
    BIF -->|HTTPS| OAI
    BIF -->|HTTPS| ANT
    BIF -->|HTTPS| GGL

    OR -->|unified API| OAI
    OR -->|unified API| ANT

    OWU -->|HTTP /v1| LS
    FAB -->|HTTP /v1| LS

    LS -->|manages processes| VLLM
```

## Product Responsibility Table

| Product | Module Path | Transport | Purpose | Key Config Files |
|---------|------------|-----------|---------|-----------------|
| Claude Code | `modules/claude-config.nix` | Desktop app | Primary AI coding assistant | `~/.claude/settings.json`, `~/.claude.json` |
| Antigravity CLI | `modules/antigravity-cli/` | CLI | Google Antigravity assistant | `~/.gemini/antigravity-cli/settings.json` |
| Codex CLI | `modules/codex/` | CLI | OpenAI coding assistant | `~/.codex/config.toml` |
| GitHub Copilot CLI | `modules/copilot.nix` | CLI | Trusted folder configuration | `~/.copilot/config.json` |
| Bifrost | `orbstack-kubernetes` repo | HTTP :30080 | Multi-provider AI gateway | K8s secrets (Doppler Operator) |
| MLX / llama-swap | `modules/mlx/` | HTTP :11434 | Local Apple Silicon inference | `~/.config/mlx/llama-swap.json` |
| Fabric | `modules/fabric/` | CLI + HTTP :8180 | AI prompt pattern library | `~/.config/fabric/` |
| Open WebUI | `modules/open-webui.nix` | HTTP :8080 | Browser UI for MLX | None (queries MLX at runtime) |
| Maestro | `modules/maestro/` | Cron → subprocess | Scheduled Claude sessions | `~/Maestro/Auto Run Docs/` |

## MCP Server Connectivity

The MCP server catalog (`modules/mcp/catalog.nix`) is exposed by the dedicated
MCP module as `programs.aiMcp.servers`. Claude, Antigravity, and Codex each
normalize that shared option differently via their own settings modules.

```mermaid
graph LR
    MCPCAT["modules/mcp/catalog.nix\nprograms.aiMcp.servers"]

    MCPCAT -->|normalized for Claude| CSETTINGS["modules/claude-config.nix\n→ ~/.claude.json"]
    MCPCAT -->|normalized for Antigravity| GSETTINGS["modules/antigravity-cli/settings.nix\n→ ~/.gemini/antigravity-cli/settings.json"]
    MCPCAT -->|normalized for Codex| DSETTINGS["modules/codex/settings.nix\n→ ~/.codex/config.toml"]
```

### Shared MCP Servers (all three CLI tools)

| Server | Transport | Auth | Notes |
|--------|-----------|------|-------|
| `everything`, `fetch`, `filesystem`, `git`, `memory` | stdio (bunx) | None | Official Anthropic servers |
| `sequentialthinking`, `docker` | stdio (bunx) | None | Official Anthropic servers |
| `time` | stdio (uvx) | None | Official maintained Python server |
| `aws` | stdio (bunx) | IAM/STS env vars | AWS KB retrieval |
| `terraform` | stdio (binary) | None | nixpkgs binary |
| `bifrost` | HTTP :30080 | None (K8s internal) | AI gateway |
| `cribl` | HTTP :30030 | None (K8s internal) | Log pipeline |

### Claude-Only MCP Servers

| Server | Transport | Notes |
|--------|-----------|-------|
| `huggingface` | stdio (uvx) | `HF_TOKEN` from Keychain |
| `fabric` | stdio (uvx) | Pattern execution |
| `google-workspace` | stdio (doppler-mcp + uvx) | Gmail/Drive/Calendar; requires OAuth |
| `codex` | stdio (binary) | OpenAI Codex CLI server |
| `splunk` | stdio (doppler-mcp + mcp-remote) | Defined in `nix-darwin` repo |
| `context7` | plugin-managed | Lifecycle owned by `context7` plugin |

### Disabled Servers (configured but off)

`brave-search`, `cloudflare`, `exa`, `firecrawl`, `github`, `google-maps`, `postgresql`,
`puppeteer`, `sentry`, `slack`, `sqlite` — all require API keys not currently configured.
Enable by overriding `programs.aiMcp.servers.<name>.disabled` and adding the key to Doppler.

## Port Allocation

| Port | Service | Protocol | Module |
|------|---------|----------|--------|
| 11434 | llama-swap proxy | HTTP (OpenAI-compatible) | `modules/mlx/` |
| 11436+ | vllm-mlx backends | HTTP (managed by llama-swap) | `modules/mlx/` |
| 8080 | Open WebUI | HTTP | `modules/open-webui.nix` |
| 8180 | Fabric REST API (opt-in) | HTTP + Swagger UI | `modules/fabric/` |
| 9379 | LiteRT-LM classifier (Antigravity CLI gemma router, opt-in) | HTTP | `modules/antigravity-cli/` |
| 30080 | Bifrost AI gateway | HTTP | `orbstack-kubernetes` repo |
| 30030 | Cribl MCP | HTTP | `orbstack-kubernetes` repo |
| 30317 | OTEL Collector (gRPC receiver) | gRPC | `orbstack-kubernetes` repo |
| 4317 | Cribl OTEL ingest | gRPC | `orbstack-kubernetes` repo |

Reserved but avoid: **11435** (macOS app conflict, see PR #230).

## Telemetry Pipeline

```mermaid
graph LR
    CC["Claude Code\n(metrics + logs)"]
    MLX["vllm-mlx\n(traces, when telemetry.enable=true)"]
    OTEL["OTEL Collector\n:30317"]
    CRIBL["Cribl Stream\n:4317"]
    SPLUNK["Splunk HEC"]
    GAL["Galileo SaaS\napi.galileo.ai/otel/traces"]

    CC -->|grpc OTLP| OTEL
    MLX -->|grpc OTLP| OTEL
    OTEL -->|grpc OTLP| CRIBL
    CRIBL --> SPLUNK
    OTEL -->|"otlphttp (gated: X-Trace-Sink header\n+ content denylist)"| GAL
```

**Galileo gate:** only spans carrying `X-Trace-Sink: galileo` AND passing the
content denylist (no Splunk/Cisco/client keywords) are forwarded to Galileo.
All other spans flow only to Cribl/Splunk. See [ADR 0003](../adr/0003-galileo-ai-observability.md).

## Fabric's Four Integration Channels

Fabric connects to Claude Code through four independent paths:

```mermaid
graph LR
    FAB["Fabric"]
    CC["Claude Code"]
    MLX["MLX :11434"]

    CC -->|"1. stdio MCP\n(fabric-mcp server)"| FAB
    CC -->|"2. Skills marketplace\n(curated patterns as SKILL.md)"| FAB
    FAB -->|"3. CLI pipeline\n(fabric | claude)"| CC
    FAB -->|"4. REST API :8180\n(programmatic access)"| EXTERNAL["External tools"]
    FAB -->|routes to| MLX
```

| Channel | How | Use Case |
|---------|-----|---------|
| stdio MCP | `fabric-mcp` uvx server | Direct pattern execution from Claude |
| Skills marketplace | `fabric-patterns` plugin, curated SKILL.md files | Auto-discovery by description match |
| CLI pipeline | Shell: `fabric -p pattern \| claude` | Ad-hoc pipeline composition |
| REST API | `fabric --serve` LaunchAgent on :8180 | Programmatic external access |
