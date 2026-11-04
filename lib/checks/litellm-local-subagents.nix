# Subagent routing checks for the local LiteLLM proxy. Codex and OpenCode
# subagents must run on the group the proxy option derives (subagentModel).
# The fixture declares a host rung, so that group exists, and enables OpenCode.
# Kept out of ./litellm-local.nix and ./opencode.nix for the 12KB gate.
{
  pkgs,
  hmConfigLitellmSubagents,
}:
let
  cfg = hmConfigLitellmSubagents.config;
  group =
    assert
      cfg.programs.litellmLocal.subagentModel != null
      || throw "the litellm fixture must declare a host rung, so the subagent group exists";
    cfg.programs.litellmLocal.subagentModel;
  opencodeSettings = cfg.home.file."${cfg.programs.opencode.configDir}/opencode.json".source;
  codexProfile = cfg.home.file.".codex/medium.config.toml".source;
in
{
  litellm-local-opencode-subagents =
    pkgs.runCommand "check-litellm-local-opencode-subagents"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e --arg g "${group}" '
          . as $c
          | (["general", "explore"] | all(. as $n |
              $c.agent[$n].mode == "subagent" and $c.agent[$n].model == ("mlx/" + $g)))
            and ($c.provider.mlx.models | has($g))
        ' ${opencodeSettings} >/dev/null || {
          echo "opencode general and explore must use mlx/${group}:"
          cat ${opencodeSettings}
          exit 1
        }
        touch $out
      '';

  litellm-local-codex-subagents =
    pkgs.runCommand "check-litellm-local-codex-subagents"
      {
        profile = codexProfile;
      }
      ''
        grep -Fxq 'default_subagent_model = "${group}"' "$profile" || {
          echo "a litellm Codex profile must route subagents to ${group}:"
          cat "$profile"
          exit 1
        }
        touch $out
      '';
}
