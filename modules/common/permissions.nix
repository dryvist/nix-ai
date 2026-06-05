# Unified AI CLI Permission Definitions
#
# Single source of truth for command permissions across all AI tools.
# Each tool uses formatters to convert these to their specific format.
#
# STRUCTURE:
# - allow: Auto-approved commands (from ai-assistant-instructions)
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
  ai-assistant-instructions,
  excludeDenyFiles ? [ ],
  excludeDenyCommands ? [ ],
  ...
}:

let
  homeDir = config.home.homeDirectory;

  # Read all JSON files from a directory into an attribute set
  # Returns {filename = parsed-json-content} for efficient reuse
  readJsonsFromDir =
    dir:
    if builtins.pathExists dir then
      let
        files = builtins.readDir dir;
        jsonFiles = lib.filterAttrs (n: v: v == "regular" && lib.hasSuffix ".json" n) files;
      in
      lib.mapAttrs' (
        name: _:
        let
          filePath = "${dir}/${name}";
          fileContents = builtins.readFile filePath;
          parsed = builtins.tryEval (builtins.fromJSON fileContents);
        in
        if parsed.success then
          lib.nameValuePair name parsed.value
        else
          throw "Invalid JSON in AI permission file: ${filePath}"
      ) jsonFiles
    else
      { };

  # Paths to permission directories in ai-assistant-instructions
  allowDir = "${ai-assistant-instructions}/agentsmd/permissions/allow";
  denyDir = "${ai-assistant-instructions}/agentsmd/permissions/deny";
  askDir = "${ai-assistant-instructions}/agentsmd/permissions/ask";
  domainsFile = "${ai-assistant-instructions}/agentsmd/permissions/domains/webfetch.json";

  # Read all permission files once to avoid redundant I/O
  allowJsons = readJsonsFromDir allowDir;
  denyJsons = readJsonsFromDir denyDir;
  askJsons = readJsonsFromDir askDir;

  # Apply deny exclusions: drop entire files, then filter specific commands.
  # Excluded categories are handled by auto mode's AI classifier instead.
  filteredDenyJsons = lib.filterAttrs (name: _: !(builtins.elem name excludeDenyFiles)) denyJsons;

in
{
  # Auto-approved commands from ai-assistant-instructions
  allow = lib.flatten (lib.mapAttrsToList (_: v: v.commands or [ ]) allowJsons);

  # Denied commands with exclusions applied
  deny = lib.filter (cmd: !(builtins.elem cmd excludeDenyCommands)) (
    lib.flatten (lib.mapAttrsToList (_: v: v.commands or [ ]) filteredDenyJsons)
  );

  # Commands that require explicit user confirmation
  ask = lib.flatten (lib.mapAttrsToList (_: v: v.commands or [ ]) askJsons);

  # MCP tool permissions (non-shell, bare identifiers like mcp__plugin_*)
  mcpAllow = lib.flatten (lib.mapAttrsToList (_: v: v.mcp or [ ]) allowJsons);
  mcpDeny = lib.flatten (lib.mapAttrsToList (_: v: v.mcp or [ ]) filteredDenyJsons);
  mcpAsk = lib.flatten (lib.mapAttrsToList (_: v: v.mcp or [ ]) askJsons);

  # WebFetch domains
  webfetchDomains =
    if builtins.pathExists domainsFile then
      (builtins.fromJSON (builtins.readFile domainsFile)).domains
    else
      [ ];

  # File patterns to deny (for Claude Read tool)
  # These come from dangerous.json's "patterns" field
  denyPatterns = denyJsons."dangerous.json".patterns or [ ];

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

      # WebFetch with allowed domains (dynamically generated from ai-assistant-instructions)
      # This will be populated by formatters.nix using webfetchDomains

      # Special read patterns
      read = [
        "Read(/nix/store/**)"
      ];

      # Deny patterns for sensitive files (Claude-specific Read tool)
      # Populated from ai-assistant-instructions deny/dangerous.json patterns field
      # This will be transformed by formatters.nix to Read(...) format
    };
  };
}
