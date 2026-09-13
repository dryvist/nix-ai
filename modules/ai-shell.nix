# AI shell aliases wiring
#
# Appends AI-tool aliases to programs.zsh.initContent after nix-home's base
# init block. lib.mkAfter ensures these entries load last so any collisions
# with nix-home's aliases.nix win in our favor. The companion nix-home PR
# removes d-claude from that file, but mkAfter keeps us safe
# during the transitional window.

{ config, lib, ... }:

let
  inherit (import ../vars/ai-stack.nix) doppler;
  cfg = config.programs.aiRouterKeys;
in
{
  options.programs.aiRouterKeys = {
    openbaoPathPrefix = lib.mkOption {
      type = lib.types.str;
      default = "secret/apps";
      description = ''
        OpenBao KV path prefix `aikey <harness>` (modules/ai-aliases.zsh)
        reads a harness's router key from: `<openbaoPathPrefix>/<harness>`.
        Same per-consumer layout as `programs.raycastAi.openbaoKeyPath` in
        nix-home (`secret/apps/raycast`) — `aikey opencode` reads
        `secret/apps/opencode` by default.
      '';
    };

    openbaoFieldSuffix = lib.mkOption {
      type = lib.types.str;
      default = "_llm_router_key";
      description = ''
        Field-name suffix `aikey <harness>` reads within its OpenBao secret:
        `<harness><openbaoFieldSuffix>`. Defaults to `_llm_router_key`, the
        name settled by the apps-side grant PR and the router A4 PR — e.g.
        `aikey opencode` reads field `opencode_llm_router_key`.
      '';
    };
  };

  config = {
    # Non-secret Doppler selectors, exported so the d-* aliases and any
    # hand-run `doppler run` share the single source in vars/ai-stack.nix.
    # Secret values are never exported here — see with-ai-readonly.
    programs.zsh.initContent = lib.mkAfter ''
      export AI_DOPPLER_PROJECT=${lib.escapeShellArg doppler.project}
      export AI_DOPPLER_CONFIG=${lib.escapeShellArg doppler.config}
      export AI_ROUTER_KEY_OPENBAO_PATH_PREFIX=${lib.escapeShellArg cfg.openbaoPathPrefix}
      export AI_ROUTER_KEY_OPENBAO_FIELD_SUFFIX=${lib.escapeShellArg cfg.openbaoFieldSuffix}
      source ${./ai-aliases.zsh}
    '';
  };
}
