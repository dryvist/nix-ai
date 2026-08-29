# litellm-local — cost-ordered fallback-tier assertions.
#
# Split out of lib/checks/litellm-local.nix for the per-file 12KB gate (the
# same split-rather-than-exempt pattern used across lib/checks). Pure
# assertions over the already-rendered config: no new evaluation, no I/O.
# Returns the first failing check (or null), which the parent asserts.
{ lib, rendered }:
let
  # ---- cost-ordered fallback tier ------------------------------------------
  # The property: no tier Claude Code uses may depend on a single model. A
  # model can die with no config change at all (the router's `subagent` alias
  # kept resolving in /v1/model/info for days after the model behind it stopped
  # answering), so "one name, one model" is the failure mode, not an
  # implementation detail.
  settings = rendered.litellm_settings;
  renderedGroups = map (d: d.model_name) rendered.model_list;

  fallbackEntries = settings.fallbacks or [ ];
  fallbackGroups = lib.concatMap builtins.attrNames fallbackEntries;
  # Each entry is `{ group = [ target, ... ]; }`, so attrValues yields a list
  # OF LISTS — flatten before membership-testing, or every target reads as
  # unknown.
  fallbackTargets = lib.unique (
    lib.concatMap (e: lib.concatLists (builtins.attrValues e)) fallbackEntries
  );

  chainHasDepth = lib.all (e: lib.all (t: t != [ ]) (builtins.attrValues e)) fallbackEntries;

  # Every fallback target must itself be a real model_list group. A target that
  # only resolves through `*` reintroduces exactly the failure the chain exists
  # to remove — the request leaves this host and 404s upstream.
  targetsAreExplicitGroups = lib.all (t: lib.elem t renderedGroups) fallbackTargets;

  # A blanket default_fallbacks would also catch `claude-*`, quietly answering
  # a main session from a cheap model when Anthropic rate-limits. Losing the
  # request is recoverable; not noticing the model changed under a long session
  # is not.
  noBlanketDefault = !(settings ? default_fallbacks);

  # A context-window overflow cannot succeed as sent, so routing it to a bigger
  # window is a repair rather than a downgrade — the one case where moving the
  # main tier off Anthropic is safe.
  contextFallbackTargets = lib.unique (
    lib.concatMap (e: lib.concatLists (builtins.attrValues e)) (
      settings.context_window_fallbacks or [ ]
    )
  );
  contextFallbacksAreExplicit = lib.all (t: lib.elem t renderedGroups) contextFallbackTargets;

  retriesConfigured = (settings.num_retries or 0) > 0;

  # The main tier gets retries and a context-window repair, never a silent
  # quality swap, so it must not appear as a fallback source group.
  mainTierNotInFallbacks = !(lib.elem "claude-*" fallbackGroups);

  # Declared as data and folded once below, rather than a run of
  # `assert x || throw ...` lines. One list is easier to extend, and the
  # failure message comes from the same place the condition does.
  fallbackTierChecks = [
    {
      ok = fallbackEntries != [ ];
      msg = "the proxy must configure litellm_settings.fallbacks: without a chain, one dead upstream model takes every subagent with it (see modules/litellm-local/fallback-tier.nix)";
    }
    {
      ok = chainHasDepth;
      msg = "every fallback entry must name at least one target; an empty list is a chain that cannot fall anywhere";
    }
    {
      ok = targetsAreExplicitGroups;
      msg = "every fallback target must be an explicit model_list group, never resolved through the wildcard — a wildcard target leaves this host and 404s upstream the moment the router alias goes stale; got: ${builtins.toJSON fallbackTargets}";
    }
    {
      ok = noBlanketDefault;
      msg = "litellm_settings.default_fallbacks must stay unset: it would also catch the main tier, silently answering a main session from a cheaper model instead of surfacing the failure";
    }
    {
      ok = contextFallbacksAreExplicit;
      msg = "every context_window_fallbacks target must be an explicit model_list group; got: ${builtins.toJSON contextFallbackTargets}";
    }
    {
      ok = retriesConfigured;
      msg = "litellm_settings.num_retries must be greater than zero so a transient upstream failure is retried before it spends a fallback";
    }
    {
      ok = mainTierNotInFallbacks;
      msg = "the main Anthropic tier must not appear as a fallback source group: it gets retries and a context-window repair, never a silent quality swap";
    }
  ];

  firstFallbackFailure = lib.findFirst (c: !c.ok) null fallbackTierChecks;
in
{
  inherit firstFallbackFailure;
}
