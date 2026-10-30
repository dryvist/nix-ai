{ pkgs, hmConfig }:
let
  inherit (pkgs) lib;
in
{
  # Inspect the owner-generated JSON at build time, avoiding import-from-derivation.
  herdr-claude-rendered-hooks =
    let
      composed = hmConfig.extendModules {
        modules = [
          {
            programs.claude.hooks = {
              sessionStart = lib.mkForce "printf typed-start";
              refreshMarketplaces = lib.mkForce true;
            };
          }
          {
            programs.claude.hooks.events.SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "fixture-caller-one";
                  }
                ];
              }
            ];
          }
          {
            programs.claude.hooks.events.SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "fixture-caller-two";
                  }
                ];
              }
            ];
          }
        ];
      };
      legacy = composed.extendModules {
        modules = [
          {
            programs.claude.settings.hooks.SessionStart = [
              {
                hooks = [
                  {
                    type = "command";
                    command = "fixture-legacy";
                  }
                ];
              }
            ];
          }
        ];
      };
      composedActivation = pkgs.writeText "claude-composed-activation" composed.config.home.activation.claudeSettingsMerge.data;
      legacyActivation = pkgs.writeText "claude-legacy-activation" legacy.config.home.activation.claudeSettingsMerge.data;
    in
    pkgs.runCommand "check-herdr-claude-rendered-hooks" { nativeBuildInputs = [ pkgs.jq ]; } ''
      set -euo pipefail
      settings_json=$(grep -o '/nix/store/[a-z0-9]*-claude-settings\.json' ${composedActivation} | head -1)
      jq -e '
        [.hooks.SessionStart[]?.hooks[]?.command | select(type == "string")] as $commands |
        ($commands | map(select(contains("herdr-agent-state.sh"))) | length) == 1 and
        ($commands | map(select(contains("session-start.sh"))) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-one")) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-two")) | length) == 1 and
        any(.hooks.SessionStart[]?.hooks[]?; (.command // "" | contains("session-start.sh")) and .async == true and .timeout == 300)
      ' "$settings_json" >/dev/null
      legacy_json=$(grep -o '/nix/store/[a-z0-9]*-claude-settings\.json' ${legacyActivation} | head -1)
      jq -e '
        [.hooks.SessionStart[]?.hooks[]?.command | select(type == "string")] as $commands |
        ($commands | map(select(. == "fixture-legacy")) | length) == 1 and
        ($commands | map(select(contains("session-start.sh"))) | length) == 0 and
        ($commands | map(select(contains("herdr-agent-state.sh"))) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-one")) | length) == 1 and
        ($commands | map(select(. == "fixture-caller-two")) | length) == 1
      ' "$legacy_json" >/dev/null
      touch "$out"
    '';
}
