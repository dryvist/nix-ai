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

  # Claude-specific helper: Get tool-specific deny permissions.
  #
  # Deliberately empty: the shared `denyPatterns` are NOT rendered as
  # `Read(<glob>)` rules for Claude Code. Once any `Read()` deny rule exists,
  # Claude Code must statically prove that every shell command cannot reach a
  # denied path before auto-approving it. A command whose working directory is
  # not resolvable at parse time (`cd DIR && grep -r x sub/`) cannot be proven
  # safe, so it falls through to an approval prompt. The leading-`**/` patterns
  # match at any depth from anywhere, which makes that unprovable for most
  # read-only exploration and turns plan mode into a prompt on nearly every
  # command. Measured on Claude Code 2.1.261: removing these rules eliminates
  # the prompt; re-adding a single leading-`**/` pattern restores it.
  #
  # Claude Code's own gate is `permissions.defaultMode = "auto"` plus the
  # auto-mode classifier, not this list. Every other harness formatter
  # (cursor, gemini, opencode, qwen) still consumes `denyPatterns` from the
  # shared data, so the patterns remain in force for those CLIs.
  getClaudeDenyPermissions = _permissions: [ ];

in
rec {
  # Format a single shell command for Claude
  formatShellCommand = cmd: "Bash(${cmd} *)";

  # Format all allowed permissions (tool-specific + MCP).
  #
  # Shell allow rules are deliberately NOT rendered for Claude Code. The
  # rendered settings set `autoMode.classifyAllShell = true` (the
  # nix-claude-code default), which "suspends every Bash and PowerShell
  # allow rule while auto mode is active, so the classifier evaluates every
  # shell command regardless of your allow list"
  # (https://code.claude.com/docs/en/auto-mode-config). A `Bash(...)` allow
  # entry therefore changes nothing at runtime and only adds bytes to every
  # session's settings.json — 324 entries, about 9 KB, before this change.
  # nix-claude-code documents `permissions.allow` as empty by design for the
  # same reason.
  #
  # Every other harness formatter (codex, gemini, cursor, opencode, qwen)
  # still renders the shared shell allow data; none of them has a classifier.
  formatAllowed =
    permissions:
    let
      mcpPermissions = permissions.mcpAllow or [ ];
    in
    (getClaudeToolPermissions permissions) ++ mcpPermissions;

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
