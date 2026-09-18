# The fallback tier's build-time assertions, split out of ./fallback-tier.nix
# for the per-file size gate. Pure predicates over the values that file
# computes; it imports this and exposes the list as `assertions`.
{
  lib,
  localModels,
  names,
  headAliases,
  entryPoint,
  effectiveTerminalName,
  terminalName,
  routerEntryModel,
  isRouterRung,
  hostRungs,
  renderedLocalParams,
  forbiddenProviderMarkers,
}:
[
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
    assertion = lib.length (lib.unique (names ++ headAliases)) == lib.length (names ++ headAliases);
    message = "litellm-local: fallback-tier rung names and head aliases must be unique.";
  }
  {
    # Makes the broken shape impossible rather than merely fixable. Without
    # this the config renders cleanly, the proxy starts, and the failure only
    # appears when something actually falls back — which is the worst moment
    # to discover the last rung cannot answer.
    # Null is not the only broken value. The rung renders as
    # "openai/${routerEntryModel}", so "" yields a bare `openai/` and a value
    # that already carries a provider yields `openai/openai/...` — both
    # render cleanly and both 404 at runtime, which is the same
    # config-looks-right/rung-is-dead failure this option exists to end.
    # Requiring a plain group name also holds the rule that no provider is
    # named on this host.
    assertion =
      localModels == [ ]
      || (routerEntryModel != null && routerEntryModel != "" && !(lib.hasInfix "/" routerEntryModel));
    message =
      "litellm-local: programs.litellmLocal.routerEntryModel must be a "
      + "non-empty router GROUP name with no `/` once localModels is "
      + "non-empty (got ${builtins.toJSON routerEntryModel}). The terminal "
      + "rung renders as `openai/<value>` and forwards it upstream: null or "
      + "an empty value leaves the rung forwarding `${terminalName}`, which "
      + "the shared router does not serve, and a provider-prefixed value "
      + "renders `openai/openai/...`. All three render cleanly and 404 at "
      + "runtime. Name the router's own entry group — a group name, not a "
      + "provider or model id.";
  }
  {
    # `!= null` FIRST, and Nix's `&&` short-circuits: a null contextWindow
    # reaching `> 0` throws an opaque type error from deep in the module
    # system instead of this message, which is precisely the case an operator
    # is most likely to hit (a model id the mlx catalog does not serve).
    assertion = lib.all (m: (m.contextWindow or null) != null && m.contextWindow > 0) hostRungs;
    message =
      "litellm-local: every rung this host serves needs a contextWindow, and one "
      + "has none. It is normally DERIVED from programs.mlx.modelContextWindows, "
      + "so the usual cause is naming an `id` the mlx catalog does not serve "
      + "-- check the id, or set contextWindow explicitly for a model served "
      + "outside the catalog. Without it LiteLLM cannot detect an overflow, "
      + "and an oversized request is truncated by the model instead of "
      + "escaping to the terminal rung.";
  }
  {
    assertion = lib.all (m: ((m.id or null) != null) != isRouterRung m) localModels;
    message = "litellm-local: each rung sets exactly one of `id` (served by this host) or `router` (a group on the shared router).";
  }
  {
    assertion = lib.all (
      m: !(isRouterRung m) || (m.router != "" && !(lib.hasInfix "/" m.router))
    ) localModels;
    message =
      "litellm-local: a rung's `router` must be a plain GROUP name the shared "
      + "router serves (no `/`, not empty) — the same rule as routerEntryModel, "
      + "for the same reason: it renders as `openai/<value>` and forwards upstream.";
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
]
