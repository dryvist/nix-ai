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
  # The proxy hop itself. Omitted entirely when `claudeDirect` is set, which
  # is the "no routing at all" switch: with no base URL and no marker header,
  # Claude Code resolves Anthropic directly and nothing here can reroute it.
  lib.optionalAttrs (!litellmLocal.claudeDirect) {
    ANTHROPIC_BASE_URL = litellmLocal.rootUrl;
    ANTHROPIC_CUSTOM_HEADERS = "x-litellm-api-key: Bearer ${litellmLocal.clientToken}";
  }
  // {
    # Which tier subagents run on. Default `anthropic` — a NATIVE Claude
    # subagent, pinned to an explicit `claude-*[1m]` id so it matches the
    # `claude-*` group and reaches Anthropic on the caller's own forwarded
    # credential. It never touches the router leg, so there is no third-party
    # egress and no retention question.
    #
    # `router` names `subagent`, the head of the generated chain in
    # ./fallback-tier.nix. That is a LOCAL model_list group which deliberately
    # shadows the upstream router's same-named alias — the upstream one still
    # points at a model whose preview period ended and 404s every call. Naming
    # the role without that local group is what breaks every subagent spawn,
    # and `claudeShapedNamesCannotReachWildcard` is what keeps a Claude-shaped
    # name from silently taking that path instead.
    CLAUDE_CODE_SUBAGENT_MODEL =
      if litellmLocal.subagentTier == "anthropic" then
        litellmLocal.subagentAnthropicModel
      else
        "subagent";

    # The haiku tier deliberately stays on Anthropic. Claude Code's background
    # requests carry its full system prompt (measured ~36k tokens), and the
    # `cheap` role targets the always-on small local model, whose 32k window
    # the router's pre-call check honestly refuses — so an override here fails
    # every background call rather than saving money.

    # For the private-workspace agent guard (nix-claude-code): it asks the
    # UPSTREAM router what a role resolves to, because the local `*` wildcard
    # hides that. Address and path only — the bearer file's contents are read
    # by the hook at the moment it needs them, never exported. Kept even under
    # `claudeDirect`: the guard still needs to resolve roles.
    LLM_ROUTER_URL = aiStack.llmRouterEndpoint;
    LLM_ROUTER_TOKEN_FILE = toString aiStack.llmEndpointTokenFile;
  }
  // lib.optionalAttrs (aiStack.internalDomains != [ ]) {
    CLAUDE_SUBAGENT_INTERNAL_DOMAINS = lib.concatStringsSep " " aiStack.internalDomains;
  }
)

# OpenTelemetry — opt-in via userConfig.telemetry. Split into its own file to
# keep this one inside the repo's file-size gate.
// import ./settings-env-telemetry.nix { inherit lib userConfig; }
