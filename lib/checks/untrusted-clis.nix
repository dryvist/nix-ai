# Untrusted agent CLI gate (programs.ai.untrustedClis.enable).
#
# Default: none of the untrusted CLIs is installed or configured on the host.
# Enabled: every one of them is. The enabled half keeps the default-off
# assertions from passing vacuously on a renamed or dropped package.
{
  pkgs,
  hmConfig,
  hmConfigUntrusted,
  homebrewFor,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  inherit (pkgs) lib;

  untrustedPackages = [
    "cecli"
    "claude-flow"
    "claude-zai"
    "copilot-cli"
    "cursor-cli"
    "gh-copilot"
    "omo-senpi"
    "opencode"
    "qwen-code"
  ];
  untrustedPrograms = [
    "cecli"
    "cursor"
    "opencode"
    "qwen-code"
  ];

  installed = hm: map lib.getName hm.config.home.packages;
  present = hm: lib.filter (n: lib.elem n (installed hm)) untrustedPackages;
  enabledPrograms = hm: lib.filter (n: hm.config.programs.${n}.enable) untrustedPrograms;
  hasFile = hm: name: hm.config.home.file ? ${name};
  hasIntegration = hm: lib.elem "opencode" hm.config.programs.herdr.integrations;
  brews = capabilities: (homebrewFor capabilities).brews;
in
{
  untrusted-clis-gate = helpers.mkDefaultsRegression {
    label = "Untrusted CLI gate";
    checkName = "check-untrusted-clis-gate";
    checks = [
      {
        name = "default: programs.ai.untrustedClis.enable";
        actual = hmConfig.config.programs.ai.untrustedClis.enable;
        expected = false;
      }
      {
        name = "default: untrusted packages installed";
        actual = present hmConfig;
        expected = [ ];
      }
      {
        name = "default: untrusted programs enabled";
        actual = enabledPrograms hmConfig;
        expected = [ ];
      }
      {
        name = "default: copilot config rendered";
        actual = hasFile hmConfig ".copilot/config.json";
        expected = false;
      }
      {
        name = "default: herdr opencode integration";
        actual = hasIntegration hmConfig;
        expected = false;
      }
      {
        name = "default: goose cask granted but not emitted";
        actual = brews {
          goose = true;
          langgraphCli = true;
        };
        expected = [ "langgraph-cli" ];
      }
      {
        # The negative case: switching the option on brings every one back.
        name = "enabled: untrusted packages installed";
        actual = present hmConfigUntrusted;
        expected = untrustedPackages;
      }
      {
        name = "enabled: untrusted programs enabled";
        actual = enabledPrograms hmConfigUntrusted;
        expected = untrustedPrograms;
      }
      {
        name = "enabled: copilot config rendered";
        actual = hasFile hmConfigUntrusted ".copilot/config.json";
        expected = true;
      }
      {
        name = "enabled: herdr opencode integration";
        actual = hasIntegration hmConfigUntrusted;
        expected = true;
      }
      {
        name = "enabled: goose emitted";
        actual = brews {
          goose = true;
          untrustedClis = true;
        };
        expected = [ "block-goose-cli" ];
      }
      {
        name = "trusted CLIs stay configured by default";
        actual = {
          claude = hmConfig.config.programs.claude.enable;
          codex = hmConfig.config.programs.codex.enable;
          agy = hmConfig.config.programs.antigravity-cli.enable;
        };
        expected = {
          claude = true;
          codex = true;
          agy = true;
        };
      }
    ];
  };
}
