# programs.mlx.defaultModelKey + the no-rebuild runtime override.
#
# Two halves, because the feature has two: the Nix half (the key compiles to a
# "default" roleOverride and a key->physical keymap) and the runtime half
# (default-model.py moves the alias, is loud when an override is in effect, and
# falls back loudly on an unusable key instead of serving nothing). The runtime
# half lives in ../../tests/mlx-default-model-test.sh — no inline shell here.
{ pkgs, hmConfigDefaultModel }:
let
  cfg = hmConfigDefaultModel.config.programs.mlx;
  qwen36-35b = "mlx-community/Qwen3.6-35B-A3B-4bit";
  qwen38-27b = "mlx-community/Qwen3.8-27B-4bit";
  inherit (cfg) defaultModelKeymap;

  # Minimal llama-swap config in the emitted shape: the declared default owns
  # the "default" alias, the override target owns another role.
  fixture = pkgs.writeText "llama-swap-fixture.json" (
    builtins.toJSON {
      models = {
        ${qwen38-27b}.aliases = [
          "default"
          "coding"
        ];
        ${qwen36-35b}.aliases = [ "goal-judge" ];
      };
    }
  );
in
{
  mlx-default-model =
    assert
      hmConfigDefaultModel.config.services.aiStack.models.default == qwen38-27b
      || throw "defaultModelKey must resolve the logical default role to the catalog entry's physical id";
    assert
      defaultModelKeymap.declared == "qwen38-27b"
      || throw "keymap must carry the declared key so a cleared/invalid override still has a fallback";
    assert
      defaultModelKeymap.keys.qwen36-35b == qwen36-35b && !(defaultModelKeymap.keys ? gemma4-31b-optiq)
      || throw "keymap must map every ENABLED catalog key (and only those) to its physical id";
    pkgs.runCommand "check-mlx-default-model"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.jq
          pkgs.python3
        ];
        SCRIPT = ../../modules/mlx/default-model.py;
        FIXTURE = fixture;
        MLX_DEFAULT_MODEL_KEYMAP = cfg.defaultModelKeymapFile;
        DECLARED = qwen38-27b;
        OVERRIDE = qwen36-35b;
      }
      ''
        bash ${../../tests/mlx-default-model-test.sh}
        touch $out
      '';
}
