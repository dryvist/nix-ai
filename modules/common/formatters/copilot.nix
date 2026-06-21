# Copilot CLI Formatter
# Format: shell(cmd) patterns for --allow-tool and --deny-tool flags
{ lib, flattenCommands }:

{
  # Format a single shell command for Copilot
  formatShellCommand = cmd: "shell(${cmd})";

  # Get trusted directories
  getTrustedFolders =
    permissions:
    let
      dirs = permissions.directories or { };
    in
    (dirs.home or [ ]) ++ (dirs.development or [ ]) ++ (dirs.config or [ ]);

  # Format denied commands for --deny-tool flags
  formatDenyFlags =
    permissions:
    let
      allCommands = flattenCommands permissions.deny;
    in
    map (cmd: "shell(${cmd})") allCommands;
}
