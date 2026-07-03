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
#   - models / capability classes: lowercase, hyphenated (`tool-calling`)
#   - endpoints / nodeports: snake_case for jq-friendliness in shell consumers
#
# Adding new fields:
#   - Pure data only. If you reach for `lib.mkOption` or `let ... in`, you're
#     in the wrong file.
#   - Update the README at the consumer of this file (e.g.,
#     docs/architecture/per-agent-flakes.md) when the schema changes,
#     so the JSON shape stays self-explanatory.
{
  # Capability-class registry. The role NAMES are the stable taxonomy
  # consumers depend on. The role VALUES are populated at evaluation time
  # by modules/ai-stack/default.nix from `services.aiStack.defaultLocalModelId`
  # (sourced by the consuming configuration from the dryvist
  # `AI_MODEL_LOCAL_LLM` org variable / Doppler secret / macOS no-password
  # automation keychain — never hardcoded in this repo).
  #
  # Every role currently resolves to the same physical model id: the
  # locally-installed default. That is the deliberate posture — one model
  # resident, every alias pointing at it, swap-thrash impossible. To
  # introduce per-role differentiation later, change the population logic
  # in modules/ai-stack/default.nix.
  #
  # Reading these `null` values directly (without going through the
  # services.aiStack.models option) will surface as obvious nulls in
  # downstream config — the option layer is the only correct read path.
  models = {
    default = null;
    quickest = null;
    tool-calling = null;
    coding = null;
    large-context = null;
    most-capable = null;
    oss = null;
  };

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
  nodeports = {
    cribl_mcp = 30030;
    otel_grpc = 30317;
    otel_http = 30318;
    cribl_hec = 30088;
    cribl_stream_ui = 30900;
    cribl_edge_ui = 30910;
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
    cecli = "0.99.12";

    # Qwen Code — Alibaba's terminal coding agent. Brew-installed via
    # nix-darwin's homebrew.brews; this pin documents the expected
    # version so consumers can sanity-check what brew has.
    # renovate: datasource=github-releases depName=QwenLM/qwen-code
    qwen-code = "0.15.11";
  };
}
