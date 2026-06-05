# AI CLI Permission Formatters
#
# Transforms tool-agnostic command definitions into tool-specific formats.
# Each tool has different permission syntax requirements.
#
# FORMATS:
# - Claude Code: Bash(cmd *) for shell, Read(**) for file tools
# - Gemini CLI: Policy Engine TOML rules (v0.36+), legacy ShellTool(cmd) kept for CI
# - Copilot CLI: shell(cmd) patterns for runtime flags
# - Codex: execpolicy prefix_rule patterns

{ lib }:

let
  # Flatten nested attribute sets into a list of commands
  # Handles both lists and nested attrsets
  flattenCommands =
    attrs:
    if builtins.isList attrs then
      attrs
    else if builtins.isAttrs attrs then
      lib.flatten (
        lib.mapAttrsToList (
          _name: value:
          if builtins.isList value then
            value
          else if builtins.isAttrs value then
            flattenCommands value
          else
            [ ]
        ) attrs
      )
    else
      [ ];

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
  getClaudeDenyPermissions =
    permissions:
    let
      # Deny patterns from ai-assistant-instructions (file patterns for the Read tool)
      denyPatterns = permissions.denyPatterns or [ ];
      # Convert patterns to Read(...) format for Claude's deny list.
      # Note: patterns are used as provided; any tilde (~) expansion must be done upstream.
      denyReadPatterns = map (p: "Read(${p})") denyPatterns;
    in
    denyReadPatterns;

  # Gemini Policy Engine: deny message for blocked commands
  geminiDenyMsg = "Command permanently blocked by security policy.";

in
rec {
  # ============================================================================
  # CLAUDE CODE FORMATTER
  # ============================================================================
  # Format: Bash(cmd *) for shell commands
  # The "<cmd> *" suffix (space then asterisk) is Claude-specific wildcard syntax:
  # it matches "cmd" followed by any arguments.
  # The space enforces word boundaries (e.g., "nix *" matches "nix search" but not "nix-env")

  claude = rec {
    # Format a single shell command for Claude
    formatShellCommand = cmd: "Bash(${cmd} *)";

    # Format a list of shell commands
    formatShellCommands = cmds: map formatShellCommand cmds;

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
  };

  # ============================================================================
  # GEMINI CLI FORMATTER
  # ============================================================================
  # Policy Engine TOML rules (Gemini CLI v0.36+)
  #
  # Generates rule attrsets for the Policy Engine, replacing the deprecated
  # tools.allowed and tools.exclude settings.json keys.
  #
  # Rule format: { toolName, commandPrefix?, decision, priority, denyMessage? }
  # Docs: https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/policy-engine.md

  gemini = rec {
    # Map legacy builtin tool names to Policy Engine tool names
    toolNameMap = {
      "ReadFileTool" = "read_file";
      "GlobTool" = "glob";
      "GrepTool" = "grep_search";
      "WebFetchTool" = "web_fetch";
    };

    # Generate allow rules for the Policy Engine
    formatAllowRules =
      permissions:
      let
        allCommands = flattenCommands permissions.allow;
        builtinTools = permissions.toolSpecific.gemini.builtin or [ ];

        shellRules = map (cmd: {
          toolName = "run_shell_command";
          commandPrefix = cmd;
          decision = "allow";
          priority = 100;
        }) allCommands;

        builtinRules = map (tool: {
          toolName = toolNameMap.${tool} or tool;
          decision = "allow";
          priority = 100;
        }) builtinTools;
      in
      builtinRules ++ shellRules;

    # Generate deny rules for the Policy Engine
    formatDenyRules =
      permissions:
      let
        allCommands = flattenCommands permissions.deny;
      in
      map (cmd: {
        toolName = "run_shell_command";
        commandPrefix = cmd;
        decision = "deny";
        priority = 200;
        denyMessage = geminiDenyMsg;
      }) allCommands;

    # Generate ask_user rules for the Policy Engine
    formatAskRules =
      permissions:
      let
        allCommands = flattenCommands permissions.ask;
      in
      map (cmd: {
        toolName = "run_shell_command";
        commandPrefix = cmd;
        decision = "ask_user";
        priority = 50;
      }) allCommands;

    # Legacy formatters (kept for regression tests and CI lib output)
    formatShellCommand = cmd: "ShellTool(${cmd})";
    formatShellCommands = cmds: map (cmd: "ShellTool(${cmd})") cmds;
    formatAllowedTools =
      permissions:
      let
        allCommands = flattenCommands permissions.allow;
        shellTools = map (cmd: "ShellTool(${cmd})") allCommands;
        builtinTools = permissions.toolSpecific.gemini.builtin or [ ];
      in
      builtinTools ++ shellTools;
    formatExcludeTools =
      permissions:
      let
        allCommands = flattenCommands permissions.deny;
      in
      map (cmd: "ShellTool(${cmd})") allCommands;
    getToolPermissions = permissions: permissions.toolSpecific.gemini.builtin or [ ];
  };

  "antigravity-cli" = gemini;

  "antigravity-ide" = {
    formatAllowed =
      permissions:
      let
        allCommands = flattenCommands permissions.allow;
      in
      map (cmd: "command(${cmd})") allCommands;
  };

  # ============================================================================
  # COPILOT CLI FORMATTER
  # ============================================================================
  # Format: shell(cmd) patterns for --allow-tool and --deny-tool flags
  # Note: Copilot permissions are primarily directory-based in config

  copilot = {
    # Format a single shell command for Copilot
    formatShellCommand = cmd: "shell(${cmd})";

    # Format a list of shell commands
    formatShellCommands = cmds: map (cmd: "shell(${cmd})") cmds;

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
  };

  # ============================================================================
  # CODEX FORMATTER
  # ============================================================================
  # Codex uses native config.toml keys for sandbox/approval defaults and optional
  # execpolicy `.rules` files for command-prefix decisions outside the sandbox.
  #
  # We only translate shell command patterns that map cleanly to execpolicy
  # prefix rules. Shell-only constructs (redirections, globs, pipes, etc.) are
  # skipped because execpolicy prefix_rule has no equivalent for them — emitting
  # a partial rule would give Codex a false sense of coverage.

  codex =
    let
      tokenizeCommand = cmd: lib.filter (token: token != "") (lib.splitString " " cmd);

      tokenIsRepresentable =
        token:
        !(lib.any (char: lib.hasInfix char token) [
          "*"
          "?"
          "<"
          ">"
          "|"
          "&"
          ";"
          "$"
          "("
          ")"
          "{"
          "}"
          "\""
          "'"
          "\\"
          "`"
          "~"
        ]);

      commandIsRepresentable =
        cmd:
        let
          tokens = tokenizeCommand cmd;
        in
        tokens != [ ] && lib.all tokenIsRepresentable tokens;

      supportedCommands = cmds: lib.filter commandIsRepresentable cmds;

      skippedCommands =
        cmds:
        let
          supported = supportedCommands cmds;
        in
        builtins.length cmds - builtins.length supported;

      formatPrefixRule =
        decision: cmd: "prefix_rule(${builtins.toJSON (tokenizeCommand cmd)}, ${builtins.toJSON decision})";

      renderRules =
        decision: cmds:
        let
          supported = supportedCommands cmds;
        in
        lib.concatMapStringsSep "\n" (cmd: formatPrefixRule decision cmd) supported;
    in
    {
      inherit tokenizeCommand commandIsRepresentable supportedCommands;

      formatRulesFile =
        permissions:
        let
          allowCommands = flattenCommands permissions.allow;
          askCommands = flattenCommands permissions.ask;
          denyCommands = flattenCommands permissions.deny;
          skippedTotal =
            skippedCommands allowCommands + skippedCommands askCommands + skippedCommands denyCommands;

          allowRules = renderRules "allow" allowCommands;
          askRules = renderRules "prompt" askCommands;
          denyRules = renderRules "forbidden" denyCommands;
        in
        ''
          # Generated by nix-ai from ai-assistant-instructions/agentsmd/permissions/.
          # These rules apply to commands outside Codex's filesystem sandbox.
          # Unsupported shell-only patterns were skipped: ${toString skippedTotal}

          ${denyRules}

          ${askRules}

          ${allowRules}
        '';
    };

  # ============================================================================
  # UTILITY FUNCTIONS
  # ============================================================================

  utils = {
    # Flatten commands from nested permission structure
    inherit flattenCommands;

    # Count total commands in a permission set
    countCommands = permissions: builtins.length (flattenCommands permissions);

    # Get all categories from permissions
    getCategories = permissions: builtins.attrNames permissions;

    # Normalize MCP server definition to Antigravity format
    normalizeMcpServer =
      server:
      if server.url != null then
        # HTTP/SSE server
        { httpUrl = server.url; } // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
      else
        # stdio server
        lib.filterAttrs (_name: value: value != null && value != [ ] && value != { }) {
          inherit (server)
            command
            args
            env
            cwd
            timeout
            ;
        };
  };
}
