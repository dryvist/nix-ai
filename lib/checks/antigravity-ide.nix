# Antigravity IDE module regression tests
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfig.config.programs.antigravity-ide;
in
{
  # Verify all expected Antigravity IDE option paths exist.
  antigravity-ide-options-regression = helpers.mkOptionsRegression {
    label = "Antigravity IDE";
    checkName = "check-antigravity-ide-options-regression";
    inherit cfg;
    expectedOptions = [
      "artifactReviewMode"
      "autoExecutionPolicy"
      "enable"
      "excludedMcpServers"
      "fileAccessPolicy"
      "internetPolicy"
      "mcpServerNames"
    ];
  };

  # Verify evaluated config values match expected defaults.
  #
  # These four are enum-shaped strings that Antigravity matches exactly. A
  # typo does not error — the IDE falls back to its own stricter default and
  # starts prompting, which surfaces as "the config stopped applying" rather
  # than as a bad value. Pin them.
  antigravity-ide-defaults-regression = helpers.mkDefaultsRegression {
    label = "Antigravity IDE";
    checkName = "check-antigravity-ide-defaults-regression";
    checks = [
      {
        name = "antigravity-ide.enable";
        actual = cfg.enable;
        expected = true;
      }
      {
        name = "antigravity-ide.autoExecutionPolicy";
        actual = cfg.autoExecutionPolicy;
        expected = "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER";
      }
      {
        name = "antigravity-ide.fileAccessPolicy";
        actual = cfg.fileAccessPolicy;
        expected = "AGENT_SETTING_POLICY_ALLOW";
      }
      {
        name = "antigravity-ide.internetPolicy";
        actual = cfg.internetPolicy;
        expected = "AGENT_SETTING_POLICY_ALLOW";
      }
      {
        name = "antigravity-ide.artifactReviewMode";
        actual = cfg.artifactReviewMode;
        expected = "ARTIFACT_REVIEW_MODE_NEVER";
      }
    ];
  };

  # This module is the only one that mutates user files with raw inline `jq`
  # during activation, so its MCP output has no schema validation anywhere
  # else. Assert the shared profile actually reached it — a positive control,
  # not "nothing looked wrong": an empty render and a correct one are
  # indistinguishable downstream, since the merge is additive and simply
  # leaves whatever the previous generation wrote in place.
  antigravity-ide-mcp-rendered =
    assert
      cfg.mcpServerNames != [ ]
      || throw "Antigravity IDE rendered no MCP servers; the shared profile did not reach it";
    helpers.mkMarker "check-antigravity-ide-mcp-rendered" "Antigravity IDE renders ${toString (builtins.length cfg.mcpServerNames)} shared MCP servers";
}
