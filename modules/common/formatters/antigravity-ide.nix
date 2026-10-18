# Antigravity IDE Formatter
{ flattenCommands }:

{
  formatAllowed =
    permissions:
    let
      allCommands = flattenCommands permissions.allow;
    in
    map (cmd: "command(${cmd})") allCommands;
}
