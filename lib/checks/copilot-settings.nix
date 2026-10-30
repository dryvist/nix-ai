# Copilot CLI settings owner regression checks.
{ pkgs, mkHmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  emptyConfig = mkHmConfig [
    {
      programs = {
        ai.untrustedClis.enable = true;
        herdr.integrations.copilot.enable = false;
      };
    }
  ];
  nativeOnlyConfig = mkHmConfig [
    {
      programs = {
        ai.untrustedClis.enable = true;
        herdr.integrations.copilot.enable = true;
      };
    }
  ];
  composedConfig = mkHmConfig [
    {
      programs = {
        ai.untrustedClis.enable = true;
        copilot-cli.settings = {
          theme = "dim";
          hooks.SessionStart = [
            {
              type = "command";
              bash = "fixture-caller-hook";
              timeoutSec = 5;
            }
          ];
        };
        herdr.integrations.copilot.enable = true;
      };
    }
  ];
  settingsFile = composedConfig.config.home.file.".copilot/settings.json".source;
  nativeHooksFile = composedConfig.config.home.file.".copilot/hooks/nix-ai.json".source;
  nativeOnlyHooksFile = nativeOnlyConfig.config.home.file.".copilot/hooks/nix-ai.json".source;
in
{
  copilot-settings-empty-does-not-claim-file =
    assert !(emptyConfig.config.home.file ? ".copilot/settings.json");
    assert !(emptyConfig.config.home.file ? ".copilot/hooks/nix-ai.json");
    helpers.mkMarker "check-copilot-settings-empty-does-not-claim-file" "Empty Copilot settings do not claim settings or hook files.";

  copilot-native-hooks-do-not-claim-settings =
    assert !(nativeOnlyConfig.config.home.file ? ".copilot/settings.json");
    assert nativeOnlyConfig.config.home.file ? ".copilot/hooks/nix-ai.json";
    pkgs.runCommand "check-copilot-native-hooks-do-not-claim-settings"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e '
          .version == 1 and
          (.hooks.SessionStart | length) == 1 and
          any(.hooks.SessionStart[]; ((.bash // "") + " " + (.command // "")) | contains("herdr-agent-state.sh"))
        ' ${nativeOnlyHooksFile} >/dev/null
        touch "$out"
      '';

  copilot-settings-and-native-hooks-remain-separate =
    pkgs.runCommand "check-copilot-settings-and-native-hooks-remain-separate"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e '
          .theme == "dim" and
          .hooks.SessionStart == [{
            type: "command",
            bash: "fixture-caller-hook",
            timeoutSec: 5
          }]
        ' ${settingsFile} >/dev/null
        jq -e '
          .version == 1 and
          (.hooks.SessionStart | length) == 1 and
          any(.hooks.SessionStart[]; ((.bash // "") + " " + (.command // "")) | contains("herdr-agent-state.sh"))
        ' ${nativeHooksFile} >/dev/null
        touch "$out"
      '';
}
