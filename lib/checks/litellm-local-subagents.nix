# Subagent routing checks for the local LiteLLM proxy. Codex, OpenCode and
# Antigravity subagents must run on the group the proxy option derives
# (subagentModel). The fixture declares a host rung, so that group exists, and
# enables OpenCode.
# Kept out of ./litellm-local.nix and ./opencode.nix for the 12KB gate.
{
  pkgs,
  hmConfigLitellmSubagents,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  cfg = hmConfigLitellmSubagents.config;
  group =
    assert
      cfg.programs.litellmLocal.subagentModel != null
      || throw "the litellm fixture must declare a host rung, so the subagent group exists";
    cfg.programs.litellmLocal.subagentModel;
  opencodeSettings = cfg.home.file."${cfg.programs.opencode.configDir}/opencode.json".source;
  codexProfile = cfg.home.file.".codex/medium.config.toml".source;
  # Antigravity merges settings.json at activation, so the check reads the
  # generated settings the module exposes rather than a home.file source.
  agySettings = pkgs.writeText "antigravity-settings.json" (
    builtins.toJSON cfg.programs.antigravity-cli.generatedSettings
  );
in
{
  # The default is the ladder head, not the host-only group: a host-only
  # default would queue behind a busy worker instead of handing off.
  litellm-local-subagent-default-head =
    if group == "medium" then
      helpers.mkMarker "check-litellm-local-subagent-default-head" "native, OpenCode, Codex and Antigravity subagents default to the medium ladder head"
    else
      throw "subagentModel must default to the medium ladder head, got ${group}";

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

  litellm-local-antigravity-subagents =
    pkgs.runCommand "check-litellm-local-antigravity-subagents"
      {
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        jq -e --arg g "${group}" '
          . as $c
          | ["codebase_investigator", "cli_help", "generalist"] | all(. as $n |
              $c.agents.overrides[$n].modelConfig.model == $g)
        ' ${agySettings} >/dev/null || {
          echo "antigravity built-in subagents must use ${group}:"
          cat ${agySettings}
          exit 1
        }
        touch $out
      '';
}
