# OpenCode Formatter
# Maps the shared permission engine onto opencode.json's `permission` schema:
# bash is an attrset of command-pattern -> "allow"|"ask"|"deny" (glob matched
# against the full command), with "*" as the default decision.
{ lib, flattenCommands }:
{
  formatPermission =
    permissions:
    let
      decide = decision: cmds: lib.genAttrs (map (c: "${c}*") (flattenCommands cmds)) (_: decision);
    in
    {
      edit = "allow";
      webfetch = "allow";
      bash = {
        "*" = "ask";
      }
      // decide "allow" permissions.allow
      // decide "ask" permissions.ask
      // decide "deny" permissions.deny;
    };
}
