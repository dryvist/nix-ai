# The `claude-zai` derivation, factored out of ai-shell.nix so both the
# home-manager module and lib/checks/scripts/zai-launchers-test.sh can
# build the exact same package — one source per fact, not a duplicated
# shell fragment kept in sync by hand.
{
  pkgs,
  zai,
  gatewayKeyLaunchPrefix ? null,
  gatewayKeyEnv ? null,
}:
let
  # Literal shell parameter-expansion text, built by plain Nix string
  # concatenation so it interpolates into the shell script below at one
  # unambiguous level (no nested `${}` between Nix and shell syntax).
  zaiKeyRef = "\${" + zai.keyEnv + ":-}";
  gatewayKeyRef = if gatewayKeyEnv == null then "" else "\${" + gatewayKeyEnv + ":-}";
  gatewayPrefixArgs =
    if gatewayKeyLaunchPrefix == null then "" else pkgs.lib.escapeShellArgs gatewayKeyLaunchPrefix;
  gatewayPrefixSetup =
    if gatewayKeyLaunchPrefix == null then
      ""
    else
      "\n      gateway_prefix=()\n"
      + "      if [ -z \"" + gatewayKeyRef + "\" ]; then\n"
      + "        gateway_prefix=( " + gatewayPrefixArgs + " )\n"
      + "      fi";
  gatewayCommand =
    if gatewayKeyLaunchPrefix == null then
      "claude"
    else
      ''AGENT_GATEWAY_CALLER=claude-zai "''${gateway_prefix[@]}" claude'';
in
pkgs.writeShellApplication {
  name = "claude-zai";
  text = ''
    key_value="${zaiKeyRef}"
    if [ -z "$key_value" ]; then
      : "''${ZAI_KEY_COMMAND:?set ${zai.keyEnv}, or ZAI_KEY_COMMAND to fetch it}"
      read -ra fetch <<<"$ZAI_KEY_COMMAND"
      exec "''${fetch[@]}" "$0" "$@"
    fi${gatewayPrefixSetup}
    exec env \
      ANTHROPIC_API_KEY= \
      ANTHROPIC_AUTH_TOKEN="$key_value" \
      ANTHROPIC_BASE_URL=${pkgs.lib.escapeShellArg zai.claude.baseUrl} \
      ANTHROPIC_CUSTOM_HEADERS= \
      CLAUDE_CODE_OAUTH_TOKEN= \
      CLAUDE_CODE_USE_BEDROCK= \
      CLAUDE_CODE_USE_VERTEX= \
      OPENAI_API_KEY= \
      ANTHROPIC_DEFAULT_FABLE_MODEL=${pkgs.lib.escapeShellArg zai.claude.primaryModel} \
      ANTHROPIC_DEFAULT_OPUS_MODEL=${pkgs.lib.escapeShellArg zai.claude.primaryModel} \
      ANTHROPIC_DEFAULT_SONNET_MODEL=${pkgs.lib.escapeShellArg zai.claude.fastModel} \
      ANTHROPIC_DEFAULT_HAIKU_MODEL=${pkgs.lib.escapeShellArg zai.claude.fastModel} \
      CLAUDE_CODE_SUBAGENT_MODEL=${pkgs.lib.escapeShellArg zai.claude.fastModel} \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW=${pkgs.lib.escapeShellArg zai.claude.autoCompactWindow} \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
      API_TIMEOUT_MS=3000000 \
      PATH="$HOME/.local/bin:$PATH" \
      ${gatewayCommand} --strict-mcp-config --mcp-config "$HOME/.claude/mcp-zai.json" "$@"
  '';
}
