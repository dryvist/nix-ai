# The `claude-zai` derivation, factored out of ai-shell.nix so both the
# home-manager module and lib/checks/scripts/zai-launchers-test.sh can
# build the exact same package — one source per fact, not a duplicated
# shell fragment kept in sync by hand.
{ pkgs, zai }:
let
  # Literal shell parameter-expansion text, built by plain Nix string
  # concatenation so it interpolates into the shell script below at one
  # unambiguous level (no nested `${}` between Nix and shell syntax).
  zaiKeyRef = "\${" + zai.doppler.keyEnv + ":-}";
in
pkgs.writeShellApplication {
  name = "claude-zai";
  text = ''
    key_value="${zaiKeyRef}"
    if [ -z "$key_value" ]; then
      exec doppler run -p ${pkgs.lib.escapeShellArg zai.doppler.project} \
        -c ${pkgs.lib.escapeShellArg zai.doppler.config} --no-fallback \
        --only-secrets ${pkgs.lib.escapeShellArg zai.doppler.keyEnv} -- "$0" "$@"
    fi
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
      claude "$@"
  '';
}
