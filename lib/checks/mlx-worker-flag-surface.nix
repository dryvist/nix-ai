# Worker flag surface: every flag in a rendered worker command must be one the
# model's OWN backend accepts.
#
# The gap this closes: the other MLX checks compare config to config, so nothing
# asserted that an emitted flag belongs to the selected backend's CLI. Catalog
# `args` are backend-neutral, but the backends spell chat-template kwargs
# differently and an unknown flag is fatal -- a vllm-mlx worker handed mlx_lm's
# spelling exits at startup with "unrecognized arguments", so every worker
# llama-swap starts dies immediately and the tier answers 500.
{ pkgs, hmConfigCatalog }:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
in
{
  mlx-worker-flag-surface =
    let
      c = hmConfigCatalog.config.programs.mlx;
      # Two catalog entries carrying chat-template kwargs, one per emission
      # path: model-instances.nix appends extraArgs in two separate places
      # (registry tier and swap tier), and covering only one ships half a fix.
      optiq = "mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit"; # resident, enable_thinking
      gptOss = "mlx-community/gpt-oss-120b-MXFP4-Q8"; # swap, reasoning_effort

      # modelBackends is cleared in both: it would otherwise pin catalog entries
      # to the backend the fixture host selected, defeating the override.
      mkInstances =
        backend:
        import ../../modules/mlx/model-instances.nix {
          inherit lib;
          cfg = c // {
            modelServerBackend = backend;
            modelBackends = { };
          };
          inherit (builder backend) mkModelCmd backendFor effectiveConcurrency;
          workerEnv = _: { };
          defaultFilters = { };
          rolesByPhysical.${optiq} = [ "flag-surface-probe" ];
        };
      builder =
        backend:
        import ../../modules/mlx/model-server-cmd.nix {
          inherit lib;
          cfg = c // {
            modelServerBackend = backend;
            modelBackends = { };
          };
          mlxModelServerPkg = pkgs.writeShellScriptBin "mlx-model-server" "";
        };

      flagsOf = cmd: lib.filter (lib.hasPrefix "--") (lib.splitString " " cmd);

      # Full commands as deployed: base flags plus extraArgs, one per emission
      # path. Rendered through model-instances.nix, not mkModelCmd alone --
      # extraArgs are appended there, the only place the bad flag can enter.
      fullFlags =
        backend:
        let
          m = mkInstances backend;
        in
        flagsOf m.residentModels.${optiq}.cmd ++ flagsOf m.swapModels.${gptOss}.cmd;
      # Base commands WITHOUT extraArgs. This is the allowlist source -- derived
      # from the builder's own vllm-mlx branch, never a hand-typed flag list, so
      # retuning that branch cannot silently invalidate the check.
      baseFlags =
        backend:
        lib.concatMap (m: flagsOf ((builder backend).mkModelCmd m)) [
          optiq
          gptOss
        ];

      # unique: per-path lists are concatenated, so a shared flag would
      # otherwise be named twice in a failure message.
      mlxLmFull = lib.unique (fullFlags "mlx-lm");
      vllmBase = lib.unique (baseFlags "vllm-mlx");
      vllmFull = lib.unique (fullFlags "vllm-mlx");

      # Flags the mlx-lm command carries that the vllm-mlx builder never emits.
      # Derived by set difference, so it tracks both branches automatically.
      mlxLmOnly = lib.subtractLists vllmBase mlxLmFull;
      # vllm-mlx spells the same JSON object under a different flag name.
      renameTargets = [ "--default-chat-template-kwargs" ];
      allowed = vllmBase ++ renameTargets;
      leaked = lib.subtractLists allowed vllmFull;
      banned = lib.intersectLists vllmFull mlxLmOnly;
    in
    # Liveness guard first: assertions only fire when forced, and a derived set
    # that silently came back empty would make every assertion below vacuously
    # true -- the failure mode CLAUDE.md warns about.
    assert
      lib.elem "--chat-template-args" mlxLmOnly
      || throw "mlx-worker-flag-surface: the derived mlx-lm-only flag set has no --chat-template-args, so this check is not exercising the case it exists for -- the fixture models no longer carry chat-template args, or the render stopped including extraArgs.";
    # Second guard: the comparison must also reach the BASE commands, not only
    # extraArgs -- a broken base render would leave the two flag builders
    # effectively uncompared while the check still passed.
    assert
      lib.subtractLists vllmBase (baseFlags "mlx-lm") != [ ]
      || throw "mlx-worker-flag-surface: the mlx-lm base command shares every flag with the vllm-mlx base command, so the two backends' flag builders are no longer being compared.";
    # (a) mlx-lm keeps its own spelling.
    assert
      lib.elem "--chat-template-args" mlxLmFull
      || throw "mlx-worker-flag-surface: the mlx-lm worker command lost --chat-template-args, so the catalog's chat-template kwargs are no longer reaching mlx_lm.server.";
    # (b) no mlx-lm-only flag reaches a vllm-mlx worker.
    assert
      banned == [ ]
      || throw "mlx-worker-flag-surface: the vllm-mlx worker command carries mlx-lm-only flag(s) ${lib.concatStringsSep ", " banned}. vllm-mlx does not ignore an unknown flag -- it exits at startup with 'unrecognized arguments', so every worker llama-swap starts dies immediately and the tier answers 500.";
    assert
      leaked == [ ]
      || throw "mlx-worker-flag-surface: the vllm-mlx worker command carries flag(s) ${lib.concatStringsSep ", " leaked} that the vllm-mlx flag builder does not emit and that are not a known rename target.";
    # (c) the semantic survived the rename instead of being silently dropped.
    assert
      lib.elem "--default-chat-template-kwargs" vllmFull
      || throw "mlx-worker-flag-surface: the vllm-mlx worker command has no --default-chat-template-kwargs, so the catalog's chat-template kwargs were dropped rather than translated.";
    helpers.mkMarker "check-mlx-worker-flag-surface" "MLX worker flag surface: every emitted flag belongs to the model's own backend; chat-template kwargs are translated for vllm-mlx, never dropped and never passed through under the mlx-lm name";
}
