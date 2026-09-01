# llama-swap model-instance builder — split from default.nix for the 12KB
# file-size gate (same pattern as llama-swap-topology.nix, model-server-cmd.nix).
#
# Builds the two model-instance maps llama-swap's config actually serves:
#   registryModels    -- one entry per physical model in the role registry
#                        (services.aiStack.models), grouped by physical id so
#                        every role alias sharing a model gets one instance.
#   additionalModels  -- the non-resident swap tier from cfg.models, loaded
#                        on demand without evicting the resident registry.
# residentModels/swapModels/allModels are the split default.nix and
# llama-swap-topology.nix both consume.
{
  lib,
  cfg,
  mkModelCmd,
  backendFor,
  effectiveConcurrency,
  workerEnv,
  defaultFilters,
  rolesByPhysical,
}:
let
  proxyUrl = "http://127.0.0.1:\${PORT}";

  # Catalog `args` (options-catalog.nix -> modelExtraArgs / models.*.extraArgs)
  # are backend-neutral: one entry declares chat-template kwargs once and is
  # served by whichever backend the host selected. The backends do not spell
  # those flags the same way, and an unknown flag is not ignored -- the worker
  # exits at startup with
  #   vllm-mlx: error: unrecognized arguments: --chat-template-args {...}
  # so every worker llama-swap starts dies immediately and the tier answers
  # 500. Rename here, the one place the resolved backend and the raw arg list
  # are both in hand.
  #
  # --chat-template-args (mlx_lm.server) and --default-chat-template-kwargs
  # (vllm-mlx >= 0.4.1) take the identical JSON object, so this is a pure
  # rename with no semantic loss; only the flag token differs.
  #
  # Matching on the bare token is correct for both call sites below: the swap
  # path's args arrive already run through lib.escapeShellArg, which returns
  # shell-safe tokens like this one unquoted.
  extraArgRenames = {
    vllm-mlx = {
      "--chat-template-args" = "--default-chat-template-kwargs";
    };
  };
  adaptExtraArgs =
    modelId: args:
    let
      renames = extraArgRenames.${backendFor modelId} or { };
    in
    if renames == { } then args else map (tok: renames.${tok} or tok) args;

  # useModelName makes llama-swap rewrite the OpenAI-compatible request body's
  # `model` field to the physical model id before forwarding to the MLX server.
  # MLX servers validate the model field against the loaded model name and
  # return 404 for unknown names — without this rewrite, callers
  # using a capability-class alias (e.g. `model: "default"`) hit
  #   "The model `default` does not exist."
  # even though llama-swap routed the request correctly. With it, the alias
  # works end-to-end through the local proxy.
  # Preloading is done by the warmup LaunchAgent (mlx-warmup.py reading
  # MLX_PRELOAD_MODELS_JSON), NOT llama-swap's hooks.on_startup.preload:
  # that hook's request shape is not portable across MLX backends, so llama-swap
  # would start the worker, fail the preload, and stop it — residents cold.
  # After proxy.idleTtl of idle a model unloads and the next request reloads
  # it (~15-30 s).
  registryModels = lib.mapAttrs (
    physical: roles:
    let
      extraArgs = adaptExtraArgs physical (cfg.modelExtraArgs.${physical} or [ ]);
    in
    {
      cmd =
        mkModelCmd physical + lib.optionalString (extraArgs != [ ]) (" " + lib.escapeShellArgs extraArgs);
      ttl = cfg.modelTtls.${physical} or cfg.proxy.idleTtl;
      env = workerEnv physical;
      checkEndpoint = "/v1/models";
      proxy = proxyUrl;
      aliases = roles;
      useModelName = physical;
      concurrencyLimit = effectiveConcurrency physical;
    }
    // lib.optionalAttrs (defaultFilters != { }) {
      filters = defaultFilters;
    }
  ) rolesByPhysical;

  # Additional ad-hoc models from cfg.models (existing extension point).
  # These form the non-resident swap tier. They can be loaded on demand
  # without evicting the resident registry models, and they can carry their
  # own TTLs/aliases/filters.
  additionalModels = lib.mapAttrs (
    name: modelCfg:
    let
      mergedFilters = lib.recursiveUpdate defaultFilters (modelCfg.filters or { });
    in
    {
      cmd =
        mkModelCmd name
        + lib.optionalString (modelCfg.extraArgs != [ ]) (
          " " + lib.concatStringsSep " " (adaptExtraArgs name modelCfg.extraArgs)
        );
      ttl = if modelCfg.ttl > 0 then modelCfg.ttl else cfg.proxy.idleTtl;
      env = workerEnv name;
      checkEndpoint = "/v1/models";
      proxy = proxyUrl;
      concurrencyLimit = effectiveConcurrency name;
    }
    // lib.optionalAttrs (modelCfg.aliases != [ ]) {
      inherit (modelCfg) aliases;
    }
    // lib.optionalAttrs (mergedFilters != { }) {
      filters = mergedFilters;
    }
  ) cfg.models;

  residentModels = registryModels;
  swapModels = additionalModels;
in
{
  inherit residentModels swapModels;
  allModels = residentModels // swapModels;
}
