# Isolated fallback chains (programs.litellmLocal.isolatedChains).
#
# Each chain is a self-contained ladder: a rung falls through to the rungs below
# it in the SAME chain and to nothing else. A chain never gains the shared
# router's terminal rung, which is the one point where a request leaves a tier
# for the cloud chain behind the router. So a chain's traffic either answers from
# its own rungs or fails.
#
# Rung rendering and the provider guard are fallback-tier.nix's own (renderRung,
# forbiddenProviderMarkers), passed in, so a chain rung is built exactly as a
# tier rung is. Pure over rungs that default.nix has already resolved: the
# contextWindow derivation happens there, before this file sees a rung.
{
  lib,
  renderRung,
  forbiddenProviderMarkers,
  # Names already taken: localModels, the terminal rung and the head aliases.
  reservedNames,
  # `{ label = [ rung ... ]; }`.
  chains,
}:
let
  chainList = lib.attrValues chains;
  rungs = lib.concatLists chainList;
  isRouterRung = r: (r.router or null) != null;
  hostRungs = builtins.filter (r: !(isRouterRung r)) rungs;

  # The group or model id a rung names, for the provider guard. Never null.
  targetOf =
    r:
    if isRouterRung r then
      r.router
    else if (r.id or null) == null then
      ""
    else
      r.id;

  # `{ rung = [ every rung below it ]; }`, the shape litellm_settings.fallbacks takes.
  fallbackLadder =
    chain:
    lib.optionals (chain != [ ]) (
      lib.imap0 (i: r: { ${r.name} = map (below: below.name) (lib.drop (i + 1) chain); }) (lib.init chain)
    );

  # Overflow escapes to the NEXT rung of the same chain only. A rung further down
  # is never named here, and the shared router is never named at all.
  contextLadder =
    chain:
    lib.optionals (chain != [ ]) (
      lib.imap0 (i: r: { ${r.name} = [ (lib.elemAt chain (i + 1)).name ]; }) (lib.init chain)
    );

  names = reservedNames ++ map (r: r.name) rungs;
in
{
  modelList = map renderRung rungs;
  fallbacks = lib.concatMap fallbackLadder chainList;
  contextWindowFallbacks = lib.concatMap contextLadder chainList;

  assertions = [
    {
      assertion = lib.length (lib.unique names) == lib.length names;
      message = "litellm-local: isolatedChains rung names must be unique across localModels, every chain, the terminal rung and the head aliases. A repeated name silently overwrites one ladder with another.";
    }
    {
      assertion = lib.all (r: ((r.id or null) != null) != isRouterRung r) rungs;
      message = "litellm-local: each isolatedChains rung sets exactly one of `id` (served by this host) or `router` (a group on the shared router).";
    }
    {
      assertion = lib.all (
        r: !(isRouterRung r) || (r.router != "" && !(lib.hasInfix "/" r.router))
      ) rungs;
      message = "litellm-local: an isolatedChains rung's `router` must be a plain GROUP name the shared router serves (no `/`, not empty), for the same reason as routerEntryModel: it renders as `openai/<value>` and forwards upstream.";
    }
    {
      assertion = lib.all (r: (r.contextWindow or null) != null && r.contextWindow > 0) hostRungs;
      message = "litellm-local: every isolatedChains rung this host serves needs a contextWindow, and one has none. It is normally derived from programs.mlx.modelContextWindows, so the usual cause is an `id` the mlx catalog does not serve. Without it an overflow cannot escape to the next rung of its chain.";
    }
    {
      # THE DRY GUARD, applied to chains: a chain that names a cloud provider
      # re-creates the two-places policy problem the tier guard exists for.
      assertion =
        !(lib.any (
          marker: lib.any (r: lib.hasInfix marker (lib.toLower "${r.name} ${targetOf r}")) rungs
        ) forbiddenProviderMarkers);
      message = "litellm-local: an isolatedChains rung names a cloud provider. Cloud fallback policy belongs to the shared router ALONE. Add the model to the router instead, and reach it through a `router` rung.";
    }
  ];
}
