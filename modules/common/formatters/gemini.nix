# Gemini CLI / Antigravity CLI Formatter
# Policy Engine TOML rules (Gemini CLI v0.36+)
{ lib, flattenCommands }:

let
  # Gemini Policy Engine: deny message for blocked commands
  geminiDenyMsg = "Command permanently blocked by security policy.";

in
rec {
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
}
