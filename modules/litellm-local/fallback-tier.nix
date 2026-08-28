# Cost-ordered fallback tier for the local proxy.
#
# Split out of ./default.nix to stay under the 12KB ceiling in .file-size.yml
# (split rather than exempt, the same pattern the mlx checks use).
#
# WHY THIS EXISTS, in one sentence: a single hardcoded subagent model dies
# silently. On 2026-08-28 the router's `subagent` alias still resolved to
# `openrouter/stealth/ox-alpha`, whose testing period had ended — every call
# returned 404 with "Thank you for participating in the Stealth Ox Alpha
# testing period", and the upstream router reported
# `Available Model Group Fallbacks=None` for that group. Nothing noticed until
# a call was made by hand. One name in one place is a single point of failure;
# an ordered chain plus a liveness check is not.
#
# ORDERING IS BY COST, cheapest first. LiteLLM walks the list in order and
# stops at the first member that answers, so the cheapest capable tier wins
# and the expensive one is only ever reached when everything above it is down.
#
# The window matters as much as the price. Measured subagent context runs to
# ~284k tokens at p90, so a 200k-window model truncates real work. Every
# member below therefore advertises >= 262k input tokens; that is a hard
# selection criterion, not a preference.
#
# Prices are per Mtok (input/output) as published by the OpenRouter catalog on
# 2026-08-28, recorded so a future reader can tell whether the ordering still
# reflects reality. They are a snapshot, NOT a contract — the
# `litellm-fallback-probe` command verifies that a member still ANSWERS, never
# what it costs. Re-rank when the catalog moves; it is keyless at
# https://openrouter.ai/api/v1/models, so re-ranking needs no credential.
{ lib }:
let
  # Each member: the model_name this proxy exposes, the upstream id the router
  # resolves, and the evidence that earned it a place in the chain.
  members = [
    {
      name = "subagent-free";
      upstream = "nvidia/nemotron-3-ultra-550b-a55b:free";
      # $0/$0 per Mtok, 1,000,000-token window.
      # Verified live through this proxy 2026-08-28: finish_reason=stop.
      costPerMtok = "0/0";
      minInputTokens = 1000000;
    }
    {
      name = "subagent-cheap";
      upstream = "deepseek/deepseek-v4-flash";
      # $0.030/$0.100 per Mtok, 1,310,720-token window — the cheapest paid
      # model in the catalog that clears the window requirement by a wide
      # margin. Verified live through this proxy 2026-08-28.
      costPerMtok = "0.030/0.100";
      minInputTokens = 1310720;
    }
    {
      name = "subagent-capable";
      upstream = "minimax/minimax-m3";
      # Last non-Anthropic rung: a stronger model for when the two cheaper
      # tiers are both refusing. Verified live through this proxy 2026-08-28.
      costPerMtok = "see-catalog";
      minInputTokens = 262144;
    }
  ];

  # The window every member must clear, from measured p90 subagent context.
  # An entry that does not clear it truncates real work rather than failing
  # loudly, which is the worse failure — so this is asserted, not documented.
  requiredInputTokens = 262144;

  routerParams = member: {
    model = "openai/${member.upstream}";
    api_base = "os.environ/LLM_ROUTER_URL";
    api_key = "os.environ/OPENAI_API_KEY";
  };
in
rec {
  inherit members requiredInputTokens;

  # model_list entries this tier contributes, in cost order.
  modelList = map (m: {
    model_name = m.name;
    litellm_params = routerParams m;
  }) members;

  names = map (m: m.name) members;

  # The entry point clients name. Everything after it is the fallback chain.
  entryPoint = builtins.head names;
  chain = builtins.tail names;

  # `fallbacks` is a list of single-key attrsets, `[{group: [fb, ...]}]` —
  # the shape LiteLLM's own proxy_server_config.yaml uses and the shape the
  # upstream router already reports in its error payloads. Each rung falls
  # through to every cheaper-than-nothing rung below it, so the chain still
  # completes when the failure starts partway down.
  fallbacks = lib.imap0 (i: name: { ${name} = lib.drop (i + 1) names; }) (lib.init names);

  assertions = [
    {
      assertion = lib.all (m: m.minInputTokens >= requiredInputTokens) members;
      message =
        "litellm-local: every fallback-tier member must advertise at least "
        + "${toString requiredInputTokens} input tokens (measured p90 subagent "
        + "context is ~284k; a smaller window truncates work instead of "
        + "failing loudly).";
    }
    {
      assertion = lib.length members >= 2;
      message =
        "litellm-local: the fallback tier needs at least two members — a "
        + "single model is the single point of failure this tier exists to "
        + "remove (see the ox-alpha note in fallback-tier.nix).";
    }
    {
      assertion = lib.length (lib.unique names) == lib.length names;
      message = "litellm-local: fallback-tier member names must be unique.";
    }
  ];
}
