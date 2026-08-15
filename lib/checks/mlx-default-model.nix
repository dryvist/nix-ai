# programs.mlx.defaultModelKey + the no-rebuild runtime override.
#
# Two halves, because the feature has two: the Nix half (the key compiles to a
# "default" roleOverride and a key->physical keymap) and the runtime half
# (default-model.py moves the alias, is loud when an override is in effect, and
# falls back loudly on an unusable key instead of serving nothing).
{ pkgs, hmConfigDefaultModel }:
let
  cfg = hmConfigDefaultModel.config.programs.mlx;
  qwen36-35b = "mlx-community/Qwen3.6-35B-A3B-4bit";
  qwen38-27b = "mlx-community/Qwen3.8-27B-4bit";
  inherit (cfg) defaultModelKeymap;

  # Minimal llama-swap config in the emitted shape: the declared default owns
  # the "default" alias, the override target owns another role.
  fixture = builtins.toJSON {
    models = {
      ${qwen38-27b}.aliases = [
        "default"
        "coding"
      ];
      ${qwen36-35b}.aliases = [ "goal-judge" ];
    };
  };
  aliasesOf = ''jq -c --arg m "$1" '.models[$m].aliases' "$CONFIG"'';
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
          pkgs.python3
          pkgs.jq
        ];
      }
      ''
        set -euo pipefail
        export MLX_LLAMA_SWAP_CONFIG=$PWD/llama-swap.json
        export MLX_DEFAULT_MODEL_KEYMAP=${cfg.defaultModelKeymapFile}
        export MLX_DEFAULT_MODEL_OVERRIDE=$PWD/default-model.override
        CONFIG=$MLX_LLAMA_SWAP_CONFIG
        run() { python3 ${../../modules/mlx/default-model.py} "$@"; }
        aliases() { ${aliasesOf}; }

        cp ${pkgs.writeText "fixture.json" fixture} "$CONFIG"
        chmod u+w "$CONFIG"

        # No override: the declared default keeps the alias, and nothing shouts.
        run apply > no-override.log
        [ ! -s no-override.log ] || {
          echo "apply printed a banner with no override in effect:" >&2
          cat no-override.log >&2; exit 1
        }
        [ "$(aliases ${qwen38-27b})" = '["default","coding"]' ] || {
          echo "declared default lost its alias: $(aliases ${qwen38-27b})" >&2; exit 1
        }

        # set: alias moves, and the banner names BOTH declared and override.
        run set qwen36-35b > set.log
        [ "$(aliases ${qwen36-35b})" = '["goal-judge","default"]' ] || {
          echo "override target did not receive the default alias: $(aliases ${qwen36-35b})" >&2; exit 1
        }
        [ "$(aliases ${qwen38-27b})" = '["coding"]' ] || {
          echo "declared default kept the alias, so two models answer to it" >&2; exit 1
        }
        grep -q "MLX DEFAULT MODEL OVERRIDE ACTIVE" set.log || {
          echo "override took effect silently — the whole point is that it cannot" >&2; exit 1
        }
        grep -q "qwen38-27b" set.log && grep -q "qwen36-35b" set.log || {
          echo "banner must state the declared value AND the overridden value" >&2; exit 1
        }

        # apply is idempotent and re-announces on every activation.
        run apply | grep -q "MLX DEFAULT MODEL OVERRIDE ACTIVE"
        [ "$(aliases ${qwen36-35b})" = '["goal-judge","default"]' ]

        # Unusable key: loud on stderr, declared default served, exit 0 so a
        # stale override file cannot abort a rebuild.
        echo "not-a-catalog-key" > "$MLX_DEFAULT_MODEL_OVERRIDE"
        run apply 2> invalid.log
        grep -q "not a catalog key" invalid.log || {
          echo "an unusable override must say why:" >&2; cat invalid.log >&2; exit 1
        }
        [ "$(aliases ${qwen38-27b})" = '["coding","default"]' ] || {
          echo "invalid override must fall back to the declared default, never serve nothing" >&2; exit 1
        }
        run show | grep -q "UNUSABLE"

        # set rejects an unknown key outright rather than writing the file.
        cp "$MLX_DEFAULT_MODEL_OVERRIDE" before-set
        ! run set nope 2> rejected.log
        grep -q "cannot set default" rejected.log
        cmp -s before-set "$MLX_DEFAULT_MODEL_OVERRIDE"

        # clear: file gone, declared default keeps the alias, show says so.
        run clear > /dev/null
        [ ! -e "$MLX_DEFAULT_MODEL_OVERRIDE" ]
        [ "$(aliases ${qwen38-27b})" = '["coding","default"]' ]
        run show | grep -q "serving the declared default"

        touch $out
      '';
}
