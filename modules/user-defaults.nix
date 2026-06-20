# Default user identity, so `homeManagerModules.default` evaluates with zero
# consumer config. Several modules read `userConfig` via `_module.args`; this
# guarantees it always resolves. Consumers (e.g. nix-darwin) override by setting
# `_module.args.userConfig` at a higher priority — `mkDefault` yields to them.
#
# This module intentionally does NOT consume `userConfig` itself, to avoid a
# `_module.args` self-reference cycle.
{ lib, ... }:
{
  _module.args.userConfig = lib.mkDefault {
    user.fullName = "JacobPEvans";
  };
}
