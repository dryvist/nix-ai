# One rung of a local fallback ladder: a model this host serves itself (`id`)
# or a GROUP the shared router serves (`router`). Shared by `localModels` (the
# subagent tier) and `isolatedChains` (self-contained ladders), so both
# declare rungs the same way and fallback-tier.nix renders them the same way.
{ lib }:
lib.types.submodule {
  options = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Group name clients address.";
    };
    id = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Model id as this host's own server serves it. Exactly one of `id` and `router` is set.";
    };
    router = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "fast-gpu";
      description = ''
        A GROUP the shared router serves, used as this rung instead of a
        model this host serves itself. This is how a router tier sits
        AHEAD of this host's own model (the single-GPU fast-subagent
        group first, the laptop second). A group name only — never a
        provider, model id, or price; what the group resolves to is
        edited in the router's admin UI, not here.
      '';
    };
    contextWindow = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Real serving window in tokens -- what lets LiteLLM detect an
        overflow and escape to the next rung instead of letting the
        model truncate silently.

        Null (the default) DERIVES it from `programs.mlx.modelContextWindows`,
        which the mlx catalog already computes for the model this host
        serves. Leave it null: the catalog is the single source, and a
        number written here is free to drift above the real window,
        which silently disables the escape.

        Set it only for a model served by something other than the mlx
        catalog. An id the catalog does not serve and that carries no
        explicit value fails the build.
      '';
    };
  };
}
