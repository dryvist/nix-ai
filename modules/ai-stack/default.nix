# AI Stack — Role Registry
#
# Single source of truth mapping role names → physical mlx-community/* model
# IDs. Role names are stable and consumer-facing; physical model IDs change
# whenever we re-benchmark or upstream ships a better quant.
#
# All consumers (llama-swap, fabric, zsh aliases) reference roles, not physical
# names. Swapping a role's model is then one Nix attr edit + a darwin-rebuild
# switch — no consumer-side change is required.
#
# The role names (default, quickest, tool-calling, coding, large-context,
# most-capable) plus oss for explicit Apache-2/MIT model preference are stable
# and consumer-facing. Add new roles here; do not embed physical names in
# consumer modules.
#
# vars/ai-stack.nix is the data file (models + endpoints + nodeports). The
# home-manager activation below serializes it to ~/.config/ai-stack/registry.json
# on every rebuild so non-Nix consumers (orbstack-kubernetes, ansible, shell
# scripts) can read the same values via plain `jq`.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.aiStack;
  registryAttrs = import ../../vars/ai-stack.nix;

  # Effective endpoint map = the committed loopback entries plus the
  # consumer-injected `router` (kept out of the public data file because it
  # carries the internal serving FQDN — the consumer composes it from its own
  # domain var and passes it in via `llmRouterEndpoint`).
  effectiveEndpoints =
    registryAttrs.endpoints
    // lib.optionalAttrs (cfg.llmRouterEndpoint != "") { router = cfg.llmRouterEndpoint; };

  # The populated registry replaces the var file's null-sentinel `models`
  # block with the actual role → id map computed from
  # services.aiStack.defaultLocalModelId, and swaps in the effective endpoint
  # map (with the injected router). The JSON written to
  # ~/.config/ai-stack/registry.json contains the materialized values so
  # non-Nix consumers (orbstack-kubernetes, ansible, shell scripts) read a
  # complete registry.
  populatedRegistry = registryAttrs // {
    inherit (cfg) models;
    endpoints = effectiveEndpoints;
  };
  registryJson = pkgs.writeText "ai-stack-registry.json" (builtins.toJSON populatedRegistry);
in
{
  imports = [ ./endpoint.nix ];

  options.services.aiStack = {
    defaultLocalModelId = lib.mkOption {
      type = lib.types.str;
      # Empty default so `homeManagerModules.default` evaluates with zero consumer
      # config — local MLX inference is simply inert until a real id is set. The
      # maintainer's nix-darwin sets it from AI_MODEL_LOCAL_LLM. Never hardcode a
      # physical model id in this repo.
      default = "";
      example = "mlx-community/<provider-tag>-<model-name>-<quant>";
      description = ''
        Local MLX physical model id used as the single resident model for
        every role in `services.aiStack.models`. Supplied by the consuming
        configuration (typically `nix-darwin`) — e.g. committed in the
        consumer's user config, or injected via env/secret for CI.
        **Never hardcoded in this repo.**

        The deliberate posture: one model resident, every alias pointing
        at it, swap-thrash impossible. To introduce per-role
        differentiation later, set `services.aiStack.roleOverrides` (per-role
        pins) or override `services.aiStack.models` wholesale.
      '';
    };

    roleOverrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        coding = "mlx-community/<provider-tag>-<coder-model>-<quant>";
      };
      description = ''
        Per-role physical model ID overrides merged on top of the
        `defaultLocalModelId`-populated role map. Lets a host pin selected
        roles (e.g. `coding`) to a different resident model while every
        other role keeps following `defaultLocalModelId`. Unlike overriding
        `services.aiStack.models` wholesale, the untouched roles keep their
        default and the merged map still propagates to
        `~/.config/ai-stack/registry.json`.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default =
        (import ../../lib/ai-stack-models.nix {
          inherit (config.services.aiStack) defaultLocalModelId;
        })
        // config.services.aiStack.roleOverrides;
      defaultText = lib.literalExpression ''
        (import ../../lib/ai-stack-models.nix {
          inherit (config.services.aiStack) defaultLocalModelId;
        })
        // config.services.aiStack.roleOverrides
      '';
      description = ''
        Role-name → physical model ID map. Each role becomes a first-class
        llama-swap entry whose cmd runs `vllm-mlx serve <physical>`.

        Default: every role resolves to `services.aiStack.defaultLocalModelId`
        (read via `lib/ai-stack-models.nix`), then
        `services.aiStack.roleOverrides` is merged on top for per-role pins.
        Override this option directly only when a consumer needs a private
        mapping that should not propagate to `~/.config/ai-stack/registry.json`.
      '';
    };
  };

  config.home.activation.writeAiStackRegistry = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/ai-stack/registry.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$target")"
    $DRY_RUN_CMD install -m 0644 ${registryJson} "$target"
  '';
}
