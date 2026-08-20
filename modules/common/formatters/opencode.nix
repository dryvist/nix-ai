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
      # Always-trusted workspace root (permissions.directories.public). opencode
      # expands an absolute /** glob identically to ~/git/public/**; without this
      # rule, cross-repo access under the public root trips external_directory's
      # default "ask".
      external_directory = lib.genAttrs (map (d: "${d}/**") (permissions.directories.public or [ ])) (
        _: "allow"
      );
      bash = {
        "*" = "ask";
      }
      // decide "allow" permissions.allow
      // decide "ask" permissions.ask
      // decide "deny" permissions.deny;
    };
}
