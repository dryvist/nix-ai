# Qwen Code Formatter
#
# Maps the shared permission engine onto qwen-code's `permissions` schema:
# allow/ask/deny arrays of Claude-compatible rules. We emit one Bash(<cmd> *)
# rule per shared command; qwen enforces deny > ask > allow precedence itself.
# Only Bash command rules are mapped — qwen's builtin tool names and its
# prefix-less WebFetch(host) syntax differ from Claude, so those are skipped.
{ lib, flattenCommands }:
{
  formatPermissions =
    permissions:
    let
      rules = cmds: map (cmd: "Bash(${cmd} *)") (flattenCommands cmds);
    in
    {
      allow = rules permissions.allow;
      ask = rules permissions.ask;
      deny = rules permissions.deny;
    };
}
