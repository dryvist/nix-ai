# Cross-Repo Runtime Registry — Pure Data
#
# This is the source of truth for cross-repo shared values: capability-class
# model IDs, well-known endpoints, NodePort allocations. No module-system
# dependencies, no functions, no logic — just an attrset of plain values so
# any consumer (Nix, jq, ansible) can read it without ceremony.
#
# How values reach non-Nix consumers:
#   modules/ai-stack/default.nix activation writes
#   ~/.config/ai-stack/registry.json from `builtins.toJSON (import ./vars/ai-stack.nix)`
#   on every darwin-rebuild. Real file (mode 0644), so users can `vim`/`jq` it
#   for ad-hoc testing — edits revert on next rebuild. For permanent changes,
#   edit this file.
#
# Naming:
#   - role names come from lib/role-map.nix (see lib/ai-stack-models.nix)
#   - endpoints / nodeports: snake_case for jq-friendliness in shell consumers
#
# Adding new fields:
#   - Pure data only. If you reach for `lib.mkOption` or `let ... in`, you're
#     in the wrong file.
#   - Update the README at the consumer of this file (e.g.,
#     docs/architecture/per-agent-flakes.md) when the schema changes,
#     so the JSON shape stays self-explanatory.
{
  # Well-known LLM endpoints. Each value is a complete OpenAI-compatible
  # `/v1` base URL, read verbatim (no path munging) by whichever entry
  # `services.aiStack.llmEndpoint` selects — see modules/ai-stack/default.nix.
  #
  # Only the loopback default lives here. The cluster-hosted `router` entry
  # (the LiteLLM proxy fronting the whole fabric) is injected at evaluation
  # time by the module from `services.aiStack.llmRouterEndpoint`, so this
  # public data file never commits the internal serving FQDN — the consumer
  # composes it from its own domain var (e.g. nix-darwin's baseDomain).
  endpoints = {
    mlx_local = "http://127.0.0.1:11434/v1";
  };

  # OrbStack NodePort allocations. Authoritative source for any consumer
  # that needs to know where a service listens.
  #
  # otel_grpc/otel_http were removed: they named loopback ports that no
  # collector has ever served, and the telemetry options that defaulted to
  # them exported into a black hole for as long as telemetry was enabled. A
  # port entry here is a claim that something listens — do not add one for a
  # service that is only planned. OTLP endpoints are site-specific and now
  # come from userConfig.telemetry.otlpEndpoint / programs.mlx.telemetry.
  nodeports = {
    cribl_mcp = 30030;
    cribl_hec = 30088;
    cribl_stream_ui = 30900;
    cribl_edge_ui = 30910;
  };

  # Z.ai subscription launchers. Everything here is non-secret configuration;
  # the API key reaches only the selected child process.
  zai = {
    # The env var that carries the subscription key. When it is unset, the
    # launchers run the command in ZAI_KEY_COMMAND (set by the host) with
    # themselves as its argument.
    keyEnv = "ZAI_SUBSCRIPTION_KEY";
    claude = {
      baseUrl = "https://api.z.ai/api/anthropic";
      primaryModel = "glm-5.3[1m]";
      fastModel = "glm-5.3-flash[1m]";
      autoCompactWindow = "500000";
    };
    opencode = {
      provider = "zai-coding-plan";
      model = "glm-5.3-flash";
    };
    zcode.model = "GLM-5.3-Flash";
    codex = {
      baseUrl = "https://api.z.ai/api/v1";
      model = "glm-5.3";
      effectiveContextWindowPercent = 50;
    };
  };

  # CLI tool version pins. Renovate updates each entry via the comment
  # hint immediately above it. Used as Renovate-tracked sources of truth
  # for non-nix-managed tools (currently: brew formulae) and as
  # informational pins for tools managed by this flake's own derivations
  # (currently: cecli, where modules/cecli/package.nix has its own
  # renovate-managed version constant).
  cliVersions = {
    # cecli — actively maintained Aider fork. PyPI distribution name is
    # `cecli-dev`; entry-point binary is `cecli`. Built locally via
    # modules/cecli/package.nix (buildPythonApplication). This pin is
    # informational only — package.nix has its own renovate-managed
    # version constant.
    # renovate: datasource=pypi depName=cecli-dev
    cecli = "1.4.0";

    # Qwen Code — Alibaba's terminal coding agent. Brew-installed via
    # nix-darwin's homebrew.brews; this pin documents the expected
    # version so consumers can sanity-check what brew has.
    # renovate: datasource=github-releases depName=QwenLM/qwen-code
    qwen-code = "0.19.6";

    # LangGraph platform CLI — brew-installed via nix-darwin homebrew.brews;
    # this pin documents the expected version so consumers can sanity-check
    # what brew has.
    # renovate: datasource=homebrew formula=langgraph-cli
    langgraph-cli = "0.4.31";
  };
}
