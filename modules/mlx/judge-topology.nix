# The judge model's llama-swap entries: its own model definition and its own
# group.
#
# Split out of ./default.nix at the per-file byte cap (.file-size.yml), the same
# split-rather-than-exempt move ./cluster-script-layers.nix and the
# options-cluster-* family already made. Pure function of its inputs; the
# caller merges the two attrsets into the llama-swap config.
#
# These are merged in DIRECTLY rather than compiled by llamaSwapTopology, which
# only knows a two-bucket resident/swap shape. See options-judge.nix for why the
# judge stays outside that compiler.
{
  lib,
  cfg,
  mkModelCmd,
  workerEnv,
  effectiveConcurrency,
  defaultFilters,
}:
{
  models = lib.optionalAttrs cfg.judge.enable {
    ${cfg.judge.model} = {
      cmd =
        mkModelCmd cfg.judge.model
        + lib.optionalString (cfg.judge.extraArgs != [ ]) (" " + lib.escapeShellArgs cfg.judge.extraArgs);
      ttl = 0; # persistent group already keeps it resident; no idle unload
      env = workerEnv cfg.judge.model;
      checkEndpoint = "/v1/models";
      aliases = cfg.judge.aliases;
      useModelName = cfg.judge.model;
      concurrencyLimit = effectiveConcurrency cfg.judge.model;
    }
    // lib.optionalAttrs (defaultFilters != { }) { filters = defaultFilters; };
  };

  # persistent = true: protected from unload when the main mlx-models group's
  # exclusive=true evicts every OTHER group on load. exclusive = false: this
  # group never evicts anything itself. Net effect: never evicted, never
  # evicts — a real third bucket the topology compiler doesn't have.
  groups = lib.optionalAttrs cfg.judge.enable {
    mlx-judge-model = {
      swap = false;
      exclusive = false;
      persistent = true;
      members = [ cfg.judge.model ];
    };
  };
}
