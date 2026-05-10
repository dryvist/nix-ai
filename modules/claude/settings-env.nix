# Claude Code — environment variables for the deployed `programs.claude.settings.env`.
#
# Imported as a plain attrset by claude-config.nix. Anything that needs to
# reach into config or pkgs stays in claude-config.nix; pure key/value pairs
# live here so the parent module reads as a high-level overview.
#
# See: https://code.claude.com/docs/en/settings
# See: https://code.claude.com/docs/en/model-config
{
  # Model: opusplan set above. Env var overrides available if needed.
  # ANTHROPIC_MODEL = "sonnet"; # Uncomment to override default model via env var
  # CLAUDE_CODE_SUBAGENT_MODEL = "claude-haiku-4-5-20251001"; # Cost control for subagents

  # Explicit model versions (May 2026) - pin to known working versions if customization needed
  # Note: Opus/Sonnet 4.x use dateless IDs; Haiku 4.5 retains a date suffix per the API versioning scheme.
  # ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-7";
  # ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-6";
  # ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-haiku-4-5-20251001";

  # MCP timeout settings (5 minutes) - required for PAL MCP
  MCP_TIMEOUT = "300000";
  MCP_TOOL_TIMEOUT = "300000";

  # MCP Tool Search - defer schemas until needed (~10% context budget cap)
  # Anthropic enables this by default, but pinning explicitly so future
  # default changes don't silently re-eager-load every MCP tool's schema.
  # See: https://code.claude.com/docs/en/mcp (Scale with MCP Tool Search)
  ENABLE_TOOL_SEARCH = "auto:10";

  # Experimental: Agent teams - coordinate multiple Claude Code instances
  # See: https://code.claude.com/docs/en/agent-teams
  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";

  # Adaptive thinking for Opus/Sonnet (explicitly enabled)
  CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "0";

  # DEFAULT VALUES (upstream) - reference only, do not uncomment unless tuning
  # MAX_THINKING_TOKENS = "31999";
  # CLAUDE_CODE_MAX_OUTPUT_TOKENS = "32000";
  # BASH_MAX_OUTPUT_LENGTH = "30000";
  # MAX_MCP_OUTPUT_TOKENS = "25000";
  # SLASH_COMMAND_TOOL_CHAR_BUDGET = "16000";
  # BASH_DEFAULT_TIMEOUT_MS = "120000";  # 2 minutes
  # BASH_MAX_TIMEOUT_MS = "600000";      # 10 minutes

  # Claude.ai MCP servers (enabled by default for logged-in users)
  # ENABLE_CLAUDEAI_MCP_SERVERS = "true";

  # Plugin git operations timeout (default: 120000ms / 2 minutes)
  # CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS = "120000";

  # Effort level via env var (alternative to settings.json key)
  # CLAUDE_CODE_EFFORT_LEVEL = "medium";

  # Auto-compact threshold — using upstream default (~95% of context window)
  # CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "95";

  # ===== OpenTelemetry — OrbStack k8s OTEL Collector =====
  # Pipeline: Claude Code → OTEL Collector (:30317) → Cribl Stream (:4317) → Splunk HEC
  # Requires: OrbStack k8s running with OTEL collector deployed.
  # Source: orbstack-kubernetes/k8s/monitoring/otel-collector/service-external.yaml
  CLAUDE_CODE_ENABLE_TELEMETRY = "1";
  OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:30317";
  OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
  OTEL_METRICS_EXPORTER = "otlp";
  OTEL_LOGS_EXPORTER = "otlp";
  OTEL_TRACES_EXPORTER = "none"; # Only metrics + logs; no trace overhead
}
