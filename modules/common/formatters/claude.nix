# Claude Code Formatter
# Format: Bash(cmd *) for shell commands
{ lib, flattenCommands }:

let
  # Claude-specific helper: Get all tool-specific permissions (non-shell)
  getClaudeToolPermissions =
    permissions:
    let
      claudePerms = permissions.toolSpecific.claude or { };
      # WebFetch domains from ai-assistant-instructions
      webfetchDomains = permissions.webfetchDomains or [ ];
      webfetchPerms = map (d: "WebFetch(domain:${d})") webfetchDomains;
    in
    (claudePerms.builtin or [ ]) ++ webfetchPerms ++ (claudePerms.read or [ ]);

  # Claude-specific helper: Get tool-specific deny permissions
  # Patterns are used as provided; tilde (~) expansion must be done upstream.
  getClaudeDenyPermissions =
    permissions: map (p: "Read(${p})") (permissions.denyPatterns or [ ]);

in
rec {
  # Format a single shell command for Claude
  formatShellCommand = cmd: "Bash(${cmd} *)";

  # Format all allowed commands from permissions (shell + tool-specific + MCP)
  # Note: Tool-specific permissions are placed before shell permissions.
  # This ordering matches formatDenied and ensures consistent evaluation by Claude Code.
  formatAllowed =
    permissions:
    let
      allCommands = flattenCommands permissions.allow;
      shellPermissions = map formatShellCommand allCommands;
      mcpPermissions = permissions.mcpAllow or [ ];
    in
    (getClaudeToolPermissions permissions) ++ mcpPermissions ++ shellPermissions;

  # Format all denied commands (shell + tool-specific + MCP)
  # Note: Tool-specific permissions are placed before shell permissions.
  # This ordering matches formatAllowed and ensures consistent evaluation by Claude Code.
  formatDenied =
    permissions:
    let
      allCommands = flattenCommands permissions.deny;
      shellDenied = map formatShellCommand allCommands;
      mcpPermissions = permissions.mcpDeny or [ ];
    in
    (getClaudeDenyPermissions permissions) ++ mcpPermissions ++ shellDenied;

  # Format all ask commands (require user confirmation)
  # These commands will prompt the user for approval before execution
  formatAsk =
    permissions:
    let
      allCommands = flattenCommands permissions.ask;
      shellPermissions = map formatShellCommand allCommands;
      mcpPermissions = permissions.mcpAsk or [ ];
    in
    mcpPermissions ++ shellPermissions;

  # Export helpers for external use
  getToolPermissions = getClaudeToolPermissions;
  getDenyPermissions = getClaudeDenyPermissions;
}
