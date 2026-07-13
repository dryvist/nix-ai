# Claude Code — environment variables for the deployed `programs.claude.settings.env`.
#
# A function of { lib, userConfig }: the static key/value pairs below, plus the
# opt-in OpenTelemetry block merged in when userConfig.telemetry.enable is set.
# Keeping the env build here lets claude-config.nix stay a high-level overview.
#
# See: https://code.claude.com/docs/en/settings
# See: https://code.claude.com/docs/en/model-config
{ lib, userConfig }:
{
  # Model is intentionally left unset (see claude-config.nix), so Claude Code
  # uses the account-tier default. Override per-session via /model, or here
  # using a stable capability alias:
  # ANTHROPIC_MODEL = "sonnet"; # aliases: opus / sonnet / haiku
  # CLAUDE_CODE_SUBAGENT_MODEL = "haiku"; # cost control for subagents

  # To pin an exact model id instead of an alias, set the *_MODEL env vars below
  # to full ids from the model-config docs. Exact ids are omitted here on purpose
  # because they churn frequently: https://code.claude.com/docs/en/model-config
  #   ANTHROPIC_DEFAULT_OPUS_MODEL / ANTHROPIC_DEFAULT_SONNET_MODEL / ANTHROPIC_DEFAULT_HAIKU_MODEL

  # MCP timeout settings (5 minutes) - required for slow MCP servers
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

  # Disable the autoresearch plugin's PreToolUse block hooks (dangerous-cmd-block,
  # scout-block, privacy-block). Those hooks raw-substring-match the command/path
  # string on every Bash/Read/Edit/Write/Glob/Grep call and hard-deny false
  # positives (e.g. "git checkout .github/..." contains "git checkout ."; any
  # path containing "build/" or "env/" is blocked outright). The autoresearch:*
  # skills keep working — only these three guard hooks are neutered. Read by
  # node-hook-runner.sh, which forwards them into the hooks' clean `env -i`.
  AR_DISABLE_DANGEROUS_CMD_BLOCK = "1";
  AR_DISABLE_SCOUT_BLOCK = "1";
  AR_DISABLE_PRIVACY_BLOCK = "1";

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

}
# OpenTelemetry — opt-in via userConfig.telemetry (maintainer profile). Off by
# default so a fresh consumer emits no telemetry. Endpoint falls back to the
# registry port so flipping telemetry.enable alone reaches the local collector.
// lib.optionalAttrs (userConfig.telemetry.enable or false) {
  CLAUDE_CODE_ENABLE_TELEMETRY = "1";
  OTEL_EXPORTER_OTLP_ENDPOINT =
    userConfig.telemetry.otlpEndpoint
      or "http://localhost:${toString (import ../../vars/ai-stack.nix).nodeports.otel_grpc}";
  OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
  OTEL_METRICS_EXPORTER = "otlp";
  OTEL_LOGS_EXPORTER = "otlp";
  OTEL_TRACES_EXPORTER = "otlp";
}
