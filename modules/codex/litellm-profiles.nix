# One codex profile TOML per litellm alias (`codex --profile <alias>`).
# Codex sets subagent routing per provider only, so it is written into each profile.
{
  pkgs,
  lib,
  litellmLocal,
}:
let
  profileAttrs =
    role:
    {
      model = role;
      model_provider = "litellm";
    }
    // lib.optionalAttrs (litellmLocal.subagentModel != null) {
      agents.default_subagent_model = litellmLocal.subagentModel;
    };
in
lib.genAttrs litellmLocal.aliases (
  role:
  let
    json = pkgs.writeText "codex-${role}-profile.json" (builtins.toJSON (profileAttrs role));
  in
  pkgs.runCommand "codex-${role}.config.toml" { nativeBuildInputs = [ pkgs.yj ]; } ''
    yj -jt < ${json} > $out
  ''
)
