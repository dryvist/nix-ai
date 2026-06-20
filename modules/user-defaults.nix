# Default user identity, so `homeManagerModules.default` evaluates with zero
# consumer config. Several modules read `userConfig` via `_module.args`.
#
# Declaring it as a typed option lets consumers override individual fields
# (e.g. `userConfig.user.fullName = "Alice";`) with normal merge semantics;
# binding `_module.args.userConfig` to that option avoids a self-reference
# cycle. The binding is `mkDefault` so a consumer (or the regression harness)
# may also set `_module.args.userConfig` directly at higher priority.
{ lib, config, ... }:
{
  options.userConfig = lib.mkOption {
    type = lib.types.submodule {
      options.user.fullName = lib.mkOption {
        type = lib.types.str;
        default = "JacobPEvans";
        description = "Full name / GitHub handle used to derive the trusted org and docs host.";
      };
    };
    default = { };
    description = "Global user configuration shared across nix-ai modules.";
  };

  config._module.args.userConfig = lib.mkDefault config.userConfig;
}
