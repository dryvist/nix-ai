# Cost-ordered fallback tier for the local proxy, built from generated data.
#
# WHY A CHAIN: a single hardcoded subagent model dies silently. On 2026-08-28
# the router's `subagent` alias still resolved to `openrouter/stealth/ox-alpha`
# whose testing period had ended — every call returned 404, and the router
# reported `Available Model Group Fallbacks=None`. Nothing noticed until a call
# was made by hand. One name in one place is a single point of failure.
#
# WHY GENERATED: the first hand-written version of this file recorded
# deepseek-v4-flash at $0.030/$0.100 with a 1,310,720-token window. One day
# later the catalog said $0.087/$0.173 and 1,048,576. A price table maintained
# by hand is wrong almost immediately, and a chain ordered by wrong prices is
# not cost-ordered. `litellm-tier-refresh` regenerates ./tier-candidates.json
# from the live OpenRouter catalog intersected with what the upstream router
# will actually serve; this file only assembles what that produced.
#
# THE HEAD IS ALWAYS NAMED `subagent`. Consumers name that one string forever
# and a refresh reorders what sits behind it without touching them. It also
# shadows the upstream router's own `subagent` alias — an explicit model_list
# group beats the `*` wildcard — so the retired alias cannot reach this host.
#
# WHAT THIS FILE CANNOT PROVE: that a member still answers. Catalog metadata is
# a claim, not behaviour — ox-alpha resolved cleanly in /v1/model/info for days
# after it stopped serving. `litellm-fallback-probe` sends a real completion to
# every member and is the only check that settles it.
{ lib }:
let
  data = builtins.fromJSON (builtins.readFile ./tier-candidates.json);

  inherit (data) policy members;
  requiredInputTokens = policy.requiredInputTokens;

  routerParams = member: {
    model = "openai/${member.upstream}";
    api_base = "os.environ/LLM_ROUTER_URL";
    api_key = "os.environ/OPENAI_API_KEY";
  };

  isFree = m: m.promptCostPerMtok == 0 && m.completionCostPerMtok == 0;
in
rec {
  inherit members requiredInputTokens policy;

  modelList = map (m: {
    model_name = m.name;
    litellm_params = routerParams m;
  }) members;

  names = map (m: m.name) members;

  # The entry point clients name. Everything after it is the fallback chain.
  entryPoint = builtins.head names;
  chain = builtins.tail names;

  # `[{group: [fb, ...]}]` — the shape LiteLLM's own proxy_server_config.yaml
  # uses and the shape the upstream router reports in its error payloads. Each
  # rung falls through to every rung below it, so the chain still completes
  # when the failure starts partway down.
  fallbacks = lib.imap0 (i: name: { ${name} = lib.drop (i + 1) names; }) (lib.init names);

  assertions = [
    {
      assertion = lib.all (m: m.contextLength >= requiredInputTokens) members;
      message =
        "litellm-local: every fallback-tier member must advertise at least "
        + "${toString requiredInputTokens} input tokens (measured p90 subagent "
        + "context is ~284k; a smaller window truncates work instead of "
        + "failing loudly). Re-run litellm-tier-refresh.";
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
    {
      assertion = entryPoint == "subagent";
      message =
        "litellm-local: the head of the fallback chain must be named "
        + "`subagent` so consumers never change when the ranking does, and so "
        + "it shadows the upstream router's retired alias of the same name.";
    }
    {
      # Free models share ONE upstream quota pool. A chain made only of them
      # has a single point of failure wearing several names: exhaust the daily
      # free cap and every rung dies in the same instant.
      assertion = policy.paidTail == 0 || lib.any (m: !isFree m) members;
      message =
        "litellm-local: policy.paidTail requires at least one billing model in "
        + "the chain — an all-free chain dies all at once when the shared "
        + "OpenRouter free quota is spent, which is the failure this tier "
        + "exists to prevent.";
    }
    {
      # Ordering is the entire value of the tier; an unsorted list still works
      # and silently spends money it did not need to.
      assertion =
        let
          costs = map (m: m.promptCostPerMtok + m.completionCostPerMtok) members;
        in
        costs == lib.sort (a: b: a < b) costs;
      message =
        "litellm-local: fallback-tier members must be ordered cheapest-first; "
        + "LiteLLM walks the list in order, so an unsorted chain reaches for an "
        + "expensive model before a cheaper one that would have served. "
        + "Re-run litellm-tier-refresh rather than reordering by hand.";
    }
  ];
}
