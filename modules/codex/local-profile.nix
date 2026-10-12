{
  config,
  configDir,
  lib,
  pkgs,
}:
let
  routerAliases = import ../litellm-local/aliases.nix;
  inherit (config.programs) litellmLocal;
  localRouterAlias = "small";
  routerBaseUrl = config.services.aiStack.llmRouterEndpoint;

  localProfileAttrs =
    assert builtins.elem localRouterAlias routerAliases;
    {
      model = localRouterAlias;
      model_provider = "router";
      model_reasoning_effort = "low";
      model_providers.router = {
        name = "router";
        base_url = routerBaseUrl;
        env_key = "AGENT_ROUTER_KEY";
        wire_api = "responses";
      };
    };
  localProfileJson = pkgs.writeText "codex-local-profile.json" (builtins.toJSON localProfileAttrs);
  localProfileToml = pkgs.runCommand "codex-local.config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
    yj -jt < ${localProfileJson} > $out
  '';

  # A Codex profile is a FILE, not a table in the config above. Codex dropped
  # the legacy `[profiles.<name>]` table (and the top-level `profile =`
  # selector) in 0.134.0: a config still carrying one is refused outright, so
  # `--profile <name>` failed to start rather than falling back. Each profile
  # now lives in its own `~/.codex/<name>.config.toml` with its keys at the
  # TOP level, selected the same way on the command line: `codex --profile
  # small`. One profile per router capability alias from
  # modules/litellm-local/aliases.nix.
  litellmProfileAttrs = lib.genAttrs routerAliases (role: {
    model = role;
    model_provider = "litellm";
  });

  litellmProfileTomls = lib.mapAttrs (
    role: attrs:
    let
      json = pkgs.writeText "codex-${role}-profile.json" (builtins.toJSON attrs);
    in
    pkgs.runCommand "codex-${role}.config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
      yj -jt < ${json} > $out
    ''
  ) litellmProfileAttrs;
in
{
  inherit localProfileAttrs;
  profileNames = lib.attrNames litellmProfileTomls;
  files =
    lib.optionalAttrs litellmLocal.enable (
      lib.mapAttrs' (
        role: toml: lib.nameValuePair "${configDir}/${role}.config.toml" { source = toml; }
      ) litellmProfileTomls
    )
    // lib.optionalAttrs (routerBaseUrl != "") {
      "${configDir}/local.config.toml".source = localProfileToml;
    };
}
