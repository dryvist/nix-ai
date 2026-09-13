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
      default = "secret/data/apps";
      description = ''
        OpenBao KV v2 path prefix `aikey <harness>` (modules/ai-aliases.zsh)
        reads a harness's router key from: `<openbaoPathPrefix>/<harness>`.
        The `data` segment is KV v2's explicit path element (matching
        `modules/scripts/session-archive.sh`'s `secret/data/apps/...` read),
        distinct from the `.data.data` field nesting inside the JSON
        response body. `aikey opencode` reads `secret/data/apps/opencode`
        by default — reading it requires the `ai-public` AppRole policy to
        grant `secret/data/apps/<harness>` for that harness (see the
        `openbaoFieldSuffix` note below on the apps-side grant rollout).
      '';
    };

    openbaoFieldSuffix = lib.mkOption {
      type = lib.types.str;
      default = "_llm_router_key";
      description = ''
        Field-name suffix `aikey <harness>` reads within its OpenBao secret.
        The harness name has every hyphen turned into an underscore before
        the suffix is appended (`hermes-splunk-admin` -> field
        `hermes_splunk_admin_llm_router_key`), matching the field-naming
        scheme ansible-proxmox-ai's `roles/llm_router/defaults/main/56-virtual-keys.yml`
        defines for `bao_apps_secrets`. Defaults to
        `_llm_router_key`, the name settled by the apps-side grant PR and
        the router A4 PR — e.g. `aikey opencode` reads field
        `opencode_llm_router_key`. Reading any of these fields requires the
        `ai-public` AppRole policy to grant read on `secret/data/apps/*`
        for the harnesses in use; today it grants only
        `secret/data/ai/public/*`, and the apps-side grant PR that adds
        `opencode`/`raycast`/`codex`/`cursor` has not converged yet — until
        it does, `aikey` fails closed with a permission-denied reason.
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
