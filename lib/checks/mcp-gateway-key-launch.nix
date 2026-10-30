# MCP gateway key launch hook regression tests
{
  pkgs,
  hmConfigGatewayKeyLaunchPrefix,
  hmConfigGatewayKeyLaunchPrefixNull,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;
  hookCfg = hmConfigGatewayKeyLaunchPrefix.config;
  nullCfg = hmConfigGatewayKeyLaunchPrefixNull.config;
  # The home.packages entry with this derivation name, or null.
  packageNamed = name: cfg: lib.findFirst (p: (p.name or "") == name) null cfg.home.packages;
  launchers = packageNamed "agent-cli-launchers" hookCfg;
  launchersNull = packageNamed "agent-cli-launchers" nullCfg;
  wrappers = launchers.passthru.gatewayWrappers;
  wrapperNames = builtins.attrNames wrappers;
  zaiHook = packageNamed "claude-zai" hookCfg;
  zaiNull = packageNamed "claude-zai" nullCfg;
  opencodeHook = packageNamed "opencode" hookCfg;
in
{
  mcp-gateway-key-launch-hook =
    assert
      hookCfg.programs.aiMcp.gatewayKeyLaunchPrefixFor != null
      || throw "The hook fixture did not set programs.aiMcp.gatewayKeyLaunchPrefixFor";
    assert
      builtins.elem "claude" wrapperNames && builtins.elem "codex" wrapperNames
      || throw "Gateway launch wrappers missing for claude/codex: ${builtins.toJSON wrapperNames}";
    assert
      nullCfg.programs.aiMcp.gatewayKeyLaunchPrefixFor == null
      || throw "The null fixture did not leave the hook unset";
    assert
      launchersNull.passthru.gatewayWrappers == { }
      || throw "Gateway launch wrappers rendered with the hook null: ${builtins.toJSON (builtins.attrNames launchersNull.passthru.gatewayWrappers)}";
    helpers.mkMarker "check-mcp-gateway-key-launch-hook" "The key launch hook wraps claude and codex, and renders no wrapper when null";

  # Text-level checks: the wrappers, the zai package and the opencode launcher
  # are read, never executed, so no key or prefix binary is needed.
  mcp-gateway-key-launch-wiring =
    pkgs.runCommand "check-mcp-gateway-key-launch-wiring"
      {
        nativeBuildInputs = [ pkgs.gnugrep ];
      }
      ''
        set -euo pipefail
        fail() {
          printf '%s\n' "$1" >&2
          exit 1
        }
        claude=${wrappers.claude}
        codex=${wrappers.codex}
        zai=${zaiHook}/bin/claude-zai
        zaiNull=${zaiNull}/bin/claude-zai
        opencode=${opencodeHook}/bin/opencode

        grep -Eq 'echo-prefix.*--caller.*claude-code.*GATEWAY_KEY_CLAUDE_CODE.*/bin/claude' "$claude" \
          || fail "claude launcher does not run the gateway prefix before the real claude"
        grep -Eq 'echo-prefix.*--caller.*codex.*GATEWAY_KEY_CODEX.*/bin/codex' "$codex" \
          || fail "codex launcher does not run the gateway prefix before the real codex"
        grep -Eq 'echo-prefix.*--caller.*opencode-trusted.*GATEWAY_KEY_OPENCODE_TRUSTED.*/bin/opencode' "$opencode" \
          || fail "trusted opencode launcher does not run the gateway prefix before opencode"

        grep -Fq 'GATEWAY_KEY_CLAUDE_CODE:-}' "$claude" \
          || fail "claude launcher does not bypass the prefix when its key is already set"
        grep -Fq 'GATEWAY_KEY_CODEX:-}' "$codex" \
          || fail "codex launcher does not bypass the prefix when its key is already set"

        if grep -RqE 'GATEWAY_KEY_[A-Z0-9_]*=' ${launchers} "$zai" "$opencode"; then
          fail "a gateway launcher assigns a GATEWAY_KEY_* value in its text"
        fi

        grep -Fq 'AGENT_GATEWAY_CALLER=claude-zai' "$zai" \
          || fail "claude-zai does not export the claude-zai caller marker"
        grep -Fq 'GATEWAY_KEY_CLAUDE_ZAI:-}' "$zai" \
          || fail "claude-zai does not key its gateway prefix off GATEWAY_KEY_CLAUDE_ZAI"
        grep -Fq 'claude-zai' "$claude" && grep -Fq 'unset AGENT_GATEWAY_CALLER' "$claude" \
          || fail "claude launcher does not honor and consume the claude-zai marker"
        if grep -Fq 'AGENT_GATEWAY_CALLER' "$codex"; then
          fail "codex launcher reads the claude-zai marker"
        fi

        if grep -Fq 'AGENT_GATEWAY_CALLER' "$zaiNull"; then
          fail "claude-zai exports the marker with the hook null"
        fi
        if grep -RqF 'gateway-launcher' ${launchersNull}; then
          fail "launchers reference a gateway wrapper with the hook null"
        fi
        grep -RqF 'gateway-launcher' ${launchers} \
          || fail "launchers with the hook set do not reference the gateway wrappers"

        touch $out
      '';
}
