# Rendered fast-subagent access for Codex and Antigravity CLI.
{ pkgs, mkHmConfig }:
let
  hmConfig = mkHmConfig [
    {
      programs.agentSkills.root = "agents";
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "http://127.0.0.1/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
  skillRoot =
    if hmConfig.config.programs.agentSkills.root == "agents" then ".agents/skills" else ".codex/skills";
  skillDir = hmConfig.config.programs.agentSkills.deployedSkillPaths."${skillRoot}/fast-subagent";
  helperPath = "${hmConfig.config.home.homeDirectory}/${skillRoot}/fast-subagent/scripts/fast-subagent.sh";
  proxyAuthority = builtins.head (
    pkgs.lib.strings.splitString "/" (
      pkgs.lib.strings.removePrefix "http://" hmConfig.config.programs.litellmLocal.baseUrl
    )
  );
  proxyHost = builtins.head (pkgs.lib.strings.splitString ":" proxyAuthority);
in
{
  codex-fast-subagent-network =
    pkgs.runCommand "check-codex-fast-subagent-network"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.jq
          pkgs.yj
        ];
        activation = hmConfig.config.home.activation.codexConfigMerge.data;
        inherit proxyHost;
        passAsFile = [ "activation" ];
      }
      ''
        toml=$(grep -m1 -oE '/nix/store/[^"[:space:]]*codex-config\.toml' "$activationPath")
        yj -tj < "$toml" > config.json
        jq -e --arg host "$proxyHost" '
          .sandbox_workspace_write.network_access == true
          and .features.network_proxy.enabled == true
          and .features.network_proxy.domains == {($host): "allow"}
        ' config.json >/dev/null
        touch $out
      '';

  antigravity-cli-fast-subagent-permissions =
    pkgs.runCommand "check-antigravity-cli-fast-subagent-permissions"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.jq
        ];
        activation = hmConfig.config.home.activation.mergeAntigravitySettings.data;
        skillDir = toString skillDir;
        inherit helperPath;
        passAsFile = [ "activation" ];
      }
      ''
        settings=$(grep -m1 -oE '/nix/store/[^"[:space:]]*antigravity-settings\.json' "$activationPath")
        jq -e --arg skill "$skillDir" --arg helper "$helperPath" '
          .permissions.allow == [
            "command(doppler)",
            "read_file(\($skill)/SKILL.md)",
            "read_file(\($skill)/scripts/fast-subagent.sh)",
            "command(\($helper))"
          ]
        ' "$settings" >/dev/null
        touch $out
      '';
}
