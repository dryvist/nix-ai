# Unified AI CLI Permission Definitions
#
# Single source of truth for command permissions across all AI tools.
# Each tool uses formatters to convert these to their specific format.
#
# STRUCTURE:
# - allow: Auto-approved commands (from nix-claude-code data/permissions)
# - deny: Permanently blocked, catastrophic operations
# - directories: Shared directory trust configuration
# - toolSpecific: Non-shell tool identifiers
#
# TOOL FORMATS (applied by formatters.nix):
# - Claude: Bash(cmd *), Read(**), etc.
# - Gemini: ShellTool(cmd), ReadFileTool, etc.
# - Copilot: shell(cmd) patterns (runtime flags)
# - Crush: shell_allowlist patterns

{
  lib,
  config,
  nix-claude-code,
  excludeDenyCategories ? [ ],
  excludeDenyCommands ? [ ],
  ...
}:

let
  homeDir = config.home.homeDirectory;

  # Permission data vendored in nix-claude-code (data/permissions/*.nix,
  # exposed as lib.permissions). Verified meaning-equivalent to the legacy
  # ai-assistant-instructions/agentsmd/permissions JSON in
  # dryvist/nix-claude-code#50 (Checkpoint 3, step 1).
  sourcePermissions = nix-claude-code.lib.permissions;

  # Deny categories that callers may exclude from the static deny list
  # (excluded categories are handled by auto mode's AI classifier instead).
  #
  # The vendored deny list in nix-claude-code is flat, so the per-category
  # split lives here. Keys are the legacy deny/*.json category names; values
  # are snapshots of those files' command lists (derived once from
  # ai-assistant-instructions deny/{shell,network}.json, which match the
  # correspondingly commented blocks in nix-claude-code's
  # data/permissions/deny.nix). Exclusion is by membership, so ordering here
  # is irrelevant; entries are sorted for stable diffs.
  denyCategoryCommands = {
    # network: mutating HTTP verbs and inbound listeners
    network = [
      "curl --data"
      "curl --request DELETE"
      "curl --request PATCH"
      "curl --request POST"
      "curl --request PUT"
      "curl -X DELETE"
      "curl -X PATCH"
      "curl -X POST"
      "curl -X PUT"
      "curl -d"
      "nc -l"
      "ncat -l"
      "socat"
    ];

    # shell: inline interpreter execution and temp-file writes
    shell = [
      "bash -c"
      "cat > /tmp/"
      "cat >> /tmp/"
      "dash -c"
      "fish -c"
      "ksh -c"
      "node --eval"
      "node -e"
      "perl -c"
      "perl -e"
      "python -"
      "python -c"
      "python /dev/"
      "python /tmp/"
      "python <<"
      "python3 -"
      "python3 -c"
      "python3 /dev/"
      "python3 /tmp/"
      "python3 <<"
      "ruby --eval"
      "ruby -e"
      "sh -c"
      "tee /tmp/"
      "zsh -c"
    ];
  };

  # Full set of deny commands to drop: whole excluded categories plus any
  # individually excluded commands.
  excludedDenyCommands =
    excludeDenyCommands
    ++ lib.concatMap (
      category:
      denyCategoryCommands.${category}
        or (throw "Unknown deny category to exclude: ${category} (known: ${lib.concatStringsSep ", " (builtins.attrNames denyCategoryCommands)})")
    ) excludeDenyCategories;

in
{
  # Auto-approved commands from nix-claude-code
  allow = sourcePermissions.allow.commands;

  # Denied commands with exclusions applied
  deny = lib.filter (cmd: !(builtins.elem cmd excludedDenyCommands)) sourcePermissions.deny.commands;

  # Commands that require explicit user confirmation
  ask = sourcePermissions.ask.commands;

  # MCP tool permissions (non-shell, bare identifiers like mcp__plugin_*)
  mcpAllow = sourcePermissions.allow.mcp or [ ];
  mcpDeny = sourcePermissions.deny.mcp or [ ];
  mcpAsk = sourcePermissions.ask.mcp or [ ];

  # WebFetch domains
  webfetchDomains = sourcePermissions.domains.webfetch;

  # File patterns to deny (for Claude Read tool)
  # These come from the deny data's "patterns" field (legacy dangerous.json)
  denyPatterns = sourcePermissions.deny.patterns or [ ];

  # Trusted directories (local config)
  directories = {
    development = [
      "${homeDir}/projects"
      "${homeDir}/repos"
      "${homeDir}/workspace"
      "${homeDir}/src"
      "${homeDir}/dev"
      "${homeDir}/git"
    ];

    config = [
      "${homeDir}/.config/nix"
      "${homeDir}/.dotfiles"
      "${homeDir}/.config"
      "${homeDir}/.claude"
      "${homeDir}/.gemini"
      "${homeDir}/.antigravity"
    ];

    home = [ homeDir ];
  };

  # Tool-specific identifiers (non-shell, built-in tools)
  # NOTE: These are BUILT-IN tools (like ReadFileTool), not shell commands.
  # The attribute names here (builtin) refer to the tool's built-in capabilities,
  # not to be confused with the JSON key "tools.core" which restricts tool usage.
  toolSpecific = {
    # Gemini built-in tools (non-shell) - maps to tools.allowed, NOT tools.core
    gemini.builtin = [
      "ReadFileTool"
      "GlobTool"
      "GrepTool"
      "WebFetchTool"
    ];

    # Claude built-in tools (non-shell)
    # NOTE: Deny rules (denyRead) take precedence over allow rules (builtin)
    # as enforced by Claude Code at runtime when it evaluates these patterns,
    # not by this Nix configuration itself. Even though Read allows reading
    # any file, the denyRead patterns will block sensitive files (.env, SSH keys,
    # etc.) when Claude Code processes the permission lists.
    claude = {
      # Core built-in tools (unconditional approval)
      # Pattern format per Claude Code schema: Tool names without wildcards
      # Use bare tool name for unconditional approval: Read, Glob, etc.
      # Use tool with path for specific patterns: Read(/path/to/file)
      builtin = [
        "Read"
        "Edit" # Handles all editing including multi-file refactoring
        "Write"
        "NotebookEdit" # Jupyter notebook editing
        "Glob"
        "Grep"
        "WebSearch"
        "TodoWrite"
      ];

      # WebFetch with allowed domains (dynamically generated from nix-claude-code)
      # This will be populated by formatters.nix using webfetchDomains

      # Special read patterns
      read = [
        "Read(/nix/store/**)"
      ];

      # Deny patterns for sensitive files (Claude-specific Read tool)
      # Populated from nix-claude-code deny data's patterns field
      # This will be transformed by formatters.nix to Read(...) format
    };
  };
}
