# Fallback tier for the local proxy: this host's own models first, the shared
# homelab router as the single terminal rung.
#
# WHY A CHAIN AT ALL: a single hardcoded subagent model dies silently. On
# 2026-08-28 the router's `subagent` alias still resolved to
# `openrouter/stealth/ox-alpha` whose testing period had ended — every call
# returned 404, and the router reported `Available Model Group Fallbacks=None`.
# Nothing noticed until a call was made by hand. One name in one place is a
# single point of failure. That lesson stands; what changed is WHERE the
# redundancy lives.
#
# WHY NOT AN ENUMERATED CLOUD TIER (the design this replaces): the previous
# version generated a cost-ordered list of OpenRouter models into
# ./tier-candidates.json and served each one THROUGH the shared router. That
# encoded "which cloud model, in what order, at what price" in two places — here
# and in the router's own registry, which already owns a cloud fallback chain.
# A limit that exists twice will disagree, and this one did: ox-alpha above was
# exactly that disagreement. The router owns cloud policy now. This file names
# no provider, no price, and no cloud model.
#
# WHY LOCAL FIRST: every rung of the old chain traversed the shared router, so
# an unreachable router took this host's subagent traffic down with it even
# though this machine serves capable models itself. Putting the local endpoint
# first means the workstation degrades independently — it keeps working through
# a router outage, a VLAN change, or a wedged upstream model. Verified
# 2026-09-01: with the shared tier's models refusing every request, this host's
# own copies of the same model IDs answered normally.
#
# THE HEAD IS ALWAYS NAMED `subagent`. Consumers name that one string forever
# and the ranking behind it can change without touching them. It also shadows
# the upstream router's own `subagent` alias — an explicit model_list group
# beats the `*` wildcard — so a retired upstream alias cannot reach this host.
#
# CONTEXT IS WHY THE TERMINAL RUNG IS NOT OPTIONAL. Local models carry far
# smaller windows than the measured p90 subagent context. A local-only chain
# would truncate large work instead of failing loudly, which is the failure the
# old `requiredInputTokens` assertion existed to prevent. The property is
# preserved differently: each local rung declares its real window, and
# context_window_fallbacks (wired in ./proxy-config.nix) sends anything that
# overflows to the terminal rung, whose window is the router's to advertise.
# Overflow escapes to a bigger window rather than being silently cut.
#
# WHAT THIS FILE CANNOT PROVE: that a rung still answers. Catalog metadata is a
# claim, not behaviour — ox-alpha resolved cleanly in /v1/model/info for days
# after it stopped serving. `litellm-fallback-probe` sends a real completion to
# every rung and is the only check that settles it.
{
  lib,
  localModels ? [ ],
  localEndpointEnvVar ? "LOCAL_LLM_URL",
  terminalName ? "subagent-homelab",
}:
let
  # Every rung this host serves itself, in declared order. `contextWindow` is
  # required per model: it is what lets LiteLLM detect an overflow and escape to
  # the terminal rung instead of truncating.
  localList = map (m: {
    model_name = m.name;
    litellm_params = {
      model = "openai/${m.id}";
      api_base = "os.environ/${localEndpointEnvVar}";
      # The loopback server takes no credential. LiteLLM still wants the key
      # present, so name the same variable every other leg uses rather than
      # inventing a second one.
      api_key = "os.environ/OPENAI_API_KEY";
    };
    model_info.max_input_tokens = m.contextWindow;
  }) localModels;

  # With no local models declared, the terminal rung IS the whole chain, so it
  # must carry the name consumers use. That makes the empty default exactly the
  # previous behaviour — one `subagent` group pointing at the shared router —
  # and keeps this change inert for any host that has not opted in.
  effectiveTerminalName = if localModels == [ ] then "subagent" else terminalName;

  # The single terminal rung. It names the shared router and nothing else: no
  # provider, no model id, no price. Whatever the router decides to do behind
  # this — its own local legs, then its cloud rungs — is the router's business
  # and is configured exactly once, over there.
  terminal = {
    model_name = effectiveTerminalName;
    litellm_params = {
      model = "openai/*";
      api_base = "os.environ/LLM_ROUTER_URL";
      api_key = "os.environ/OPENAI_API_KEY";
    };
  };

  names = (map (m: m.name) localModels) ++ [ effectiveTerminalName ];

  # Providers that must never be named on this host, because the shared router
  # already owns the decision. Matched against the rendered params below.
  forbiddenProviderMarkers = [
    "openrouter"
    "anthropic/"
    "deepseek"
    "gemini"
    "openai/gpt-"
  ];

  renderedLocalParams = lib.concatMapStringsSep " " (d: d.litellm_params.model) localList;
in
rec {
  inherit localModels effectiveTerminalName;

  modelList = localList ++ [ terminal ];

  inherit names;

  # The entry point clients name. Everything after it is the fallback chain.
  entryPoint = builtins.head names;
  chain = builtins.tail names;

  # `[{group: [fb, ...]}]` — LiteLLM's own shape, and the shape the upstream
  # router reports back in its error payloads. Each rung falls through to every
  # rung below it, so the chain still completes when failure starts partway down.
  fallbacks = lib.imap0 (i: name: { ${name} = lib.drop (i + 1) names; }) (lib.init names);

  # Overflow on any local rung escapes to the terminal rung, never to another
  # local rung — a second small window is not an escape. This is what replaces
  # the old per-member `requiredInputTokens` assertion.
  contextWindowFallbacks = map (m: { ${m.name} = [ effectiveTerminalName ]; }) localModels;

  assertions = [
    {
      assertion = entryPoint == "subagent";
      message =
        "litellm-local: the head of the fallback chain must be named "
        + "`subagent` so consumers never change when the ranking does, and so "
        + "it shadows the upstream router's alias of the same name. Name the "
        + "FIRST entry of localModels `subagent`; with localModels empty the "
        + "terminal rung takes that name automatically.";
    }
    {
      # The terminal rung is the whole point: it is what makes the shared
      # router — and therefore its cloud chain — reachable without naming any
      # of it here.
      assertion = lib.last names == effectiveTerminalName;
      message =
        "litellm-local: the shared homelab router must be the LAST rung. A "
        + "chain that ends on a local model cannot reach the router's own "
        + "fallbacks, which is where all cloud policy lives.";
    }
    {
      assertion = lib.length (lib.unique names) == lib.length names;
      message = "litellm-local: fallback-tier rung names must be unique.";
    }
    {
      assertion = lib.all (m: m ? contextWindow && m.contextWindow > 0) localModels;
      message =
        "litellm-local: every local rung must declare contextWindow. Without "
        + "it LiteLLM cannot detect an overflow, and an oversized request is "
        + "truncated by the model instead of escaping to the terminal rung.";
    }
    {
      # THE DRY GUARD. This is the assertion that keeps the duplication from
      # growing back: naming a cloud provider here re-creates the two-places
      # problem that produced the ox-alpha outage.
      assertion =
        !(lib.any (marker: lib.hasInfix marker (lib.toLower renderedLocalParams)) forbiddenProviderMarkers);
      message =
        "litellm-local: a local rung names a cloud provider. Cloud fallback "
        + "policy belongs to the shared router ALONE — it already has a "
        + "credentialed, budgeted, ordered cloud chain. Naming one here means "
        + "the choice exists in two places, which is exactly how this host "
        + "ended up pointing at a retired model that had stopped serving. Add "
        + "the model to the router instead; this host reaches it through the "
        + "terminal rung.";
    }
  ];
}
