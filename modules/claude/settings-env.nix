# Claude Code — environment variables for the deployed `programs.claude.settings.env`.
#
# A function of { lib, userConfig }: the static key/value pairs below, plus the
# opt-in OpenTelemetry block merged in when userConfig.telemetry.enable is set.
# Keeping the env build here lets claude-config.nix stay a high-level overview.
#
# See: https://code.claude.com/docs/en/settings
# See: https://code.claude.com/docs/en/model-config
{
  lib,
  userConfig,
  litellmLocal,
  aiStack,
}:
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

  # Auto-compact threshold.
  #
  # NOT the upstream default, despite what this comment used to claim:
  # nix-claude-code's `autoCompactThresholdPercent` defaults to 60, and that
  # default reaches every session whether or not anything is set here. The
  # stale comment mattered — it told a reader the value was upstream's ~95%
  # when the effective value was 60.
  #
  # 60 is the right number for a 1M-token window, which is the case its author
  # reasoned about: 60% of 1M still leaves ~600k of working space. It is the
  # wrong number for a 200k window, where it compacts at 120k and spends the
  # session summarizing. Set explicitly to the value that suits the window this
  # host's default model actually has.
  #
  # Raise toward upstream's ~95 only with the summarization pass in mind: the
  # compaction itself needs headroom, so a threshold close to the ceiling can
  # leave too little room to summarize.
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80";

}
# Local LiteLLM proxy — route Claude Code through it so subagent-tier work
# resolves to a role alias upstream instead of a physical model id.
#
# The main model is deliberately untouched: `claude-*` requests reach Anthropic
# through the proxy with this client's own credentials forwarded, so the
# session model is unchanged. Only the subagent and background tiers are
# repointed at roles.
#
# Everything the proxy needs from Claude Code lives HERE, and nowhere else.
# settings.json is the one channel that reaches every session — a login shell,
# the desktop app, an IDE extension, and a session already running when the
# rebuild lands. Splitting the wiring across settings.json and shell init is
# what caused the 2026-08-24 outage: the base URL reached every session while
# the header reached only new login shells, so every other session failed.
# Nothing here is secret (the header is a constant marker; see the litellm-local
# module header for why the proxy takes no credential), so nothing here needs
# to stay out of the Nix store.
#
# No CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY: the proxy serves two wildcard
# groups, so `/v1/models` would list `claude-*` and `*` — not models — and the
# picker would show those as rows. The role names are declared below instead.
// lib.optionalAttrs litellmLocal.enable (
  {
    ANTHROPIC_BASE_URL = litellmLocal.rootUrl;
    ANTHROPIC_CUSTOM_HEADERS = "x-litellm-api-key: Bearer ${litellmLocal.clientToken}";
    # The entry point of the cost-ordered chain in
    # modules/litellm-local/fallback-tier.nix, not a single model: cheapest
    # capable tier first, falling through to progressively more expensive ones
    # only when a tier is actually down.
    #
    # An explicit model_list group, never an upstream role name. A role falls
    # through the `*` wildcard to the router, and if the router's own alias is
    # stale the request 404s on every subagent spawn — which is exactly what
    # happened when this was `subagent` and the router still pointed that alias
    # at a model whose preview period had ended. The flake check
    # `claudeTierNamesResolveLocally` enforces the explicit-group rule.
    #
    # A cheaper tier than the caller is the point — the parent corrects its
    # subagents. Every member of the chain clears the ~284k p90 subagent
    # context measured on this host; that window is a selection criterion for
    # membership, so it does not need restating per tier here.
    CLAUDE_CODE_SUBAGENT_MODEL = "subagent";
    # The haiku tier deliberately stays on Anthropic. Claude Code's background
    # requests carry its full system prompt (measured ~36k tokens), and the
    # `cheap` role targets the always-on small local model, whose 32k window
    # the router's pre-call check honestly refuses — so an override here fails
    # every background call rather than saving money. The subscription covers
    # the haiku tier; `cheap` stays the role for bounded CLI work (fabric,
    # summaries), whose prompts fit.
    # For the private-workspace agent guard (nix-claude-code): it asks the
    # UPSTREAM router what a role resolves to, because the local `*` wildcard
    # hides that. Address and path only — the bearer file's contents are read
    # by the hook at the moment it needs them, never exported.
    LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
    LLM_ROUTER_TOKEN_FILE = toString aiStack.llmEndpointTokenFile;
  }
  // lib.optionalAttrs (aiStack.internalDomains != [ ]) {
    CLAUDE_SUBAGENT_INTERNAL_DOMAINS = lib.concatStringsSep " " aiStack.internalDomains;
  }
)
# OpenTelemetry — opt-in via userConfig.telemetry (maintainer profile). Off by
# default so a fresh consumer emits no telemetry.
#
# The two endpoints are INDEPENDENT, and each signal is exported only when its
# own endpoint is set. Neither carries a default. That is the whole point: an
# OTel SDK given no endpoint falls back to a conventional loopback address, so
# "leave it unset" is not the same as "do not export" — it silently exports to
# somewhere nothing is listening. Every exporter is therefore pinned to an
# explicit `otlp` or `none` below, never left to the SDK's default. A collector
# address is site-specific; a wrong-but-plausible one is indistinguishable from
# working telemetry at every layer, which is why no default is offered here.
#
# Splitting metrics/logs from traces also matters downstream: a collector may
# accept and acknowledge all three signals while its pipeline only extracts
# one, so pointing a signal at a collector that discards it reproduces the same
# silent loss one layer further away.

# Master switch: on when telemetry is enabled AND at least one signal has
# somewhere to go. Without it Claude Code emits nothing, whatever the exporters
# and endpoints below say.
//
  lib.optionalAttrs
    (
      (userConfig.telemetry.enable or false)
      && (
        (userConfig.telemetry.otlpEndpoint or null) != null
        || (userConfig.telemetry.tracesEndpoint or null) != null
      )
    )
    (
      {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_SERVICE_NAME = userConfig.telemetry.serviceName or "claude-code";
      }
      // lib.optionalAttrs (userConfig.telemetry.logUserPrompts or false) {
        OTEL_LOG_USER_PROMPTS = "1";
      }
      // lib.optionalAttrs (userConfig.telemetry.logToolDetails or false) {
        OTEL_LOG_TOOL_DETAILS = "1";
      }
      // lib.optionalAttrs ((userConfig.telemetry.resourceAttributes or { }) != { }) {
        OTEL_RESOURCE_ATTRIBUTES = lib.concatStringsSep "," (
          lib.mapAttrsToList (k: v: "${k}=${v}") userConfig.telemetry.resourceAttributes
        );
      }
    )

# Metrics and logs. The generic endpoint is a BASE url — the exporter appends
# /v1/metrics and /v1/logs itself.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.otlpEndpoint or null) != null)
    {
      OTEL_EXPORTER_OTLP_ENDPOINT = userConfig.telemetry.otlpEndpoint;
      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_LOGS_EXPORTER = "otlp";
    }

# ...and explicitly off when it is not set, so the SDK cannot fall back to its
# conventional loopback default and export into nothing.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.otlpEndpoint or null) == null)
    {
      OTEL_METRICS_EXPORTER = "none";
      OTEL_LOGS_EXPORTER = "none";
    }

# Trace spans → a signal-specific endpoint carrying the full /v1/traces path;
# nothing is appended to it. Setting it also turns on the enhanced-telemetry
# beta, which is the flag that makes Claude Code emit the
# interaction/llm_request/tool/tool.execution/subagent span tree at all. With
# only the generic endpoint set, the CLI emits zero trace traffic.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) != null)
    {
      CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = "1";
      OTEL_TRACES_EXPORTER = "otlp";
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT = userConfig.telemetry.tracesEndpoint;
      OTEL_EXPORTER_OTLP_TRACES_PROTOCOL = "http/protobuf";
    }

# ...and explicitly off otherwise, for the same reason as metrics and logs.
//
  lib.optionalAttrs
    ((userConfig.telemetry.enable or false) && (userConfig.telemetry.tracesEndpoint or null) == null)
    {
      OTEL_TRACES_EXPORTER = "none";
    }
