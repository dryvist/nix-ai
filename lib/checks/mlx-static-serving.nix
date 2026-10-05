# Static resident mode: direct per-model launch agents, catalog-derived
# aliases/timeouts, and bounded-queue behavior.
{
  pkgs,
  src,
  hmConfigStaticServing,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };
  proxyConsumerHm =
    localProxyConsumers:
    mkHmConfig [
      {
        programs.mlx = {
          enable = true;
          catalog.qwen38-27b = {
            class = "resident";
            roles = [ "default" ];
          };
          staticResidentLocalProxyConsumers = localProxyConsumers;
        };
        services.aiStack.models.default = (import ../../modules/mlx/catalog-data.nix).qwen38-27b.model;
        programs.litellmLocal.enable = false;
      }
    ];
  noProxyNoConsumersHm = proxyConsumerHm false;
  noProxyConsumersHm = proxyConsumerHm true;
  noProxyNoConsumersEval = builtins.tryEval (
    builtins.deepSeq noProxyNoConsumersHm.config.assertions noProxyNoConsumersHm.config.assertions
  );
  noProxyConsumersEval = builtins.tryEval (
    builtins.deepSeq noProxyConsumersHm.config.assertions noProxyConsumersHm.config.assertions
  );
  proxyConsumersWithProxyEval = builtins.tryEval (
    builtins.deepSeq hmConfigStaticServing.config.assertions hmConfigStaticServing.config.assertions
  );
  noProxyResidentAgents = builtins.filter (
    agent: lib.hasPrefix "dev.mlx-model-server" agent.config.Label
  ) (builtins.attrValues noProxyNoConsumersHm.config.launchd.agents);
  cfg = hmConfigStaticServing.config.programs.mlx;
  agents = hmConfigStaticServing.config.launchd.agents;
  residentAgents = builtins.filter (
    agent:
    agent.config.Label == "dev.mlx-model-server"
    || lib.hasPrefix "dev.mlx-model-server." agent.config.Label
  ) (builtins.attrValues agents);
  labels = map (agent: agent.config.Label) residentAgents;
  contracts = cfg.staticResidentContracts;
  mlxLmServer = import ../../modules/mlx/mlx-lm-server.nix {
    inherit pkgs cfg;
    versions = import ../../lib/versions.nix;
  };
  qwen = contracts."mlx-community/Qwen3.8-27B-4bit";
  mimo = contracts."mlx-community/MiMo-V2.6-Distill-Qwen-9B-OptiQ-4bit";
  session = hmConfigStaticServing.config.home.sessionVariables;
  limits =
    builtins.fromJSON
      hmConfigStaticServing.config.home.file.".config/mlx/resident-model-limits.json".text;
  renderedConfig = hmConfigStaticServing.config.programs.litellmLocal.renderedConfig;
  routes = renderedConfig.model_list;
  routeFor = name: builtins.head (builtins.filter (route: route.model_name == name) routes);
  residentGroups = lib.unique (
    lib.concatMap (contract: builtins.attrNames contract.roles) (builtins.attrValues contracts)
  );
  fallbackSources = map (
    entry: builtins.head (builtins.attrNames entry)
  ) renderedConfig.litellm_settings.fallbacks;
  singleDeploymentResidentGroups = builtins.filter (
    group:
    builtins.length (builtins.filter (route: route.model_name == group) routes) == 1
    && !(builtins.elem group fallbackSources)
  ) residentGroups;
  judge = routeFor "judge";
  fast = routeFor "fast";
  default = routeFor "default";
  mimoAgent = builtins.head (
    builtins.filter (agent: lib.hasSuffix ".mimo-9b" agent.config.Label) residentAgents
  );
  preflightServer = builtins.head mimoAgent.config.ProgramArguments;
  hasPair =
    args: first: second:
    if args == [ ] then
      false
    else
      (builtins.head args == first && builtins.length args > 1 && builtins.elemAt args 1 == second)
      || hasPair (builtins.tail args) first second;
  queueTest = pkgs.runCommand "check-mlx-bounded-queue" { } ''
    server=${mlxLmServer.pkg}/bin/mlx-lm-server
    python="$(${pkgs.gnused}/bin/sed -n 's|^exec "\([^"]*/bin/python\)".*|\1|p' "$server")"
    unset PYTHONPATH
    ${pkgs.gnused}/bin/sed '/^exec /,$d' "$server" > mlx-lm-server-env.sh
    source mlx-lm-server-env.sh
    "$python" -c 'import mlx_bounded_queue'
    "$python" ${src}/tests/test_mlx_bounded_queue.py
    touch "$out"
  '';
  cachePreflightTest = pkgs.runCommand "check-mlx-resident-model-cache" { } ''
    cat > model-server-stub <<'EOF'
    #!/bin/sh
    : > "$MODEL_CACHE_TEST_LISTENER"
    EOF
    chmod +x model-server-stub
    export MODEL_CACHE_TEST_LISTENER="$PWD/listener-opened"
    export HF_HUB_OFFLINE=1
    export HF_HOME="$TMPDIR/hf-home"
    unset HF_HUB_CACHE
    model="modelcache-fixture/missing-model"
    snapshot_dir="$HF_HOME/hub/models--modelcache-fixture--missing-model/snapshots"
    if ${preflightServer} "$PWD/model-server-stub" --model "$model" 2>missing.log; then
      echo "old behavior: resident server reached its listener with an absent cache" >&2
      exit 1
    fi
    [ ! -e "$MODEL_CACHE_TEST_LISTENER" ] || {
      echo "resident server reached its listener with an absent cache" >&2
      exit 1
    }
    printf 'mlx-model-server-preflight: model %s is missing from HF cache; expected a snapshot at %s/*\n' "$model" "$snapshot_dir" > expected.log
    diff -u expected.log missing.log
    mkdir -p "$snapshot_dir/revision-fixture"
    ${preflightServer} "$PWD/model-server-stub" --model "$model"
    [ -e "$MODEL_CACHE_TEST_LISTENER" ]
    touch "$out"
  '';
in
{
  mlx-static-resident-agents =
    if
      builtins.length residentAgents == 2
      &&
        builtins.sort builtins.lessThan labels == [
          "dev.mlx-model-server"
          "dev.mlx-model-server.mimo-9b"
        ]
      && lib.all (agent: agent.config.KeepAlive && agent.config.RunAtLoad) residentAgents
      && lib.all (
        agent: !(lib.any (arg: lib.hasInfix "llama-swap" arg) agent.config.ProgramArguments)
      ) residentAgents
      && lib.all (
        agent:
        let
          args = agent.config.ProgramArguments;
        in
        builtins.length args >= 3
        && builtins.head args == preflightServer
        && builtins.elemAt args 2 == "--model"
        && agent.config.EnvironmentVariables.HF_HUB_OFFLINE == "1"
        && agent.config.EnvironmentVariables.HF_HOME != ""
      ) residentAgents
    then
      helpers.mkMarker "check-mlx-static-resident-agents" "two always-loaded resident LaunchAgents share the cache preflight before starting model servers"
    else
      throw "static resident mode must render exactly the two KeepAlive model agents without llama-swap";

  mlx-static-resident-routing =
    if
      judge.litellm_params.model == "openai/${mimo.model}"
      && judge.litellm_params.api_base == "http://127.0.0.1:${toString mimo.servicePort}/v1"
      && judge.litellm_params.timeout == mimo.timeoutSeconds
      && judge.litellm_params.stream_timeout == mimo.timeoutSeconds
      && judge.model_info.max_input_tokens == mimo.maxInputTokens
      && judge.model_info.max_output_tokens == mimo.maxOutputTokens
      && fast.litellm_params.model == judge.litellm_params.model
      && default.litellm_params.model == "openai/${qwen.model}"
      && default.litellm_params.api_base == "http://127.0.0.1:${toString qwen.servicePort}/v1"
      && !(builtins.any (
        entry: entry ? judge
      ) hmConfigStaticServing.config.programs.litellmLocal.renderedConfig.litellm_settings.fallbacks)
    then
      helpers.mkMarker "check-mlx-static-resident-routing" "LiteLLM judge and fast aliases resolve directly to the on-machine resident with catalog-derived limits"
    else
      throw "static resident LiteLLM aliases must route directly with catalog-derived context, output, and timeout values";

  mlx-static-resident-cooldowns =
    if
      singleDeploymentResidentGroups != [ ] && renderedConfig.router_settings.disable_cooldowns == true
    then
      helpers.mkMarker "check-mlx-static-resident-cooldowns" "catalog-derived single-deployment resident groups render LiteLLM cooldown suppression"
    else
      throw "single-deployment static resident groups without fallbacks must render LiteLLM router cooldown suppression";

  mlx-static-resident-limits =
    if
      mimo.concurrency == 4
      && hasPair mimoAgent.config.ProgramArguments "--decode-concurrency" "4"
      && hasPair mimoAgent.config.ProgramArguments "--prompt-concurrency" "4"
      && mimoAgent.config.EnvironmentVariables.MLX_MAX_PENDING_REQUESTS == toString mimo.queueSize
      && limits.aliases.judge == mimo.model
      && limits.aliases.recorder == mimo.model
      &&
        limits.routerUrl
        == "http://127.0.0.1:${toString hmConfigStaticServing.config.programs.litellmLocal.port}/v1"
      && limits.clients.ghGuard.url == "${limits.routerUrl}/chat/completions"
      && limits.clients.ghGuard.timeoutSeconds == mimo.timeoutSeconds
      && limits.models.${mimo.model}.timeoutSeconds == mimo.timeoutSeconds
      && limits.models.${mimo.model}.queueSize == mimo.queueSize
      && limits.models.${qwen.model}.timeoutSeconds == qwen.timeoutSeconds
      &&
        session.MLX_RESIDENT_MODEL_LIMITS_FILE
        == "${hmConfigStaticServing.config.home.homeDirectory}/.config/mlx/resident-model-limits.json"
      && cfg.modelTtls == { }
      && cfg.models == { }
      && !(builtins.any (
        agent: builtins.elem "--auto-unload-idle-seconds" agent.config.ProgramArguments
      ) residentAgents)
    then
      helpers.mkMarker "check-mlx-static-resident-limits" "resident limits file, LiteLLM, judge timeout, and server flags agree with the two catalog contracts; no swap or TTL is rendered"
    else
      throw "static resident mode must derive MiMo concurrency and client limits from the resident catalog with no swap or TTL";

  mlx-static-resident-proxy-requirement =
    if
      noProxyNoConsumersEval.success
      && !(noProxyNoConsumersHm.config.home.file ? ".config/mlx/resident-model-limits.json")
      && builtins.length noProxyResidentAgents == 1
      && !noProxyConsumersEval.success
      && proxyConsumersWithProxyEval.success
    then
      helpers.mkMarker "check-mlx-static-resident-proxy-requirement" "resident servers render without local proxy clients when none are declared, while declared local clients fail evaluation without LiteLLM"
    else
      throw "static resident proxy requirement: server-only config must render its model agent without client routes, and declared local consumers must require LiteLLM";

  mlx-static-resident-queue = queueTest;
  mlx-static-resident-cache = cachePreflightTest;
}
