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
  agentsDeepSeq = builtins.deepSeq agents true;
  inherit (import ../../modules/mlx/serving-label.nix { inherit lib; }) isServingLabel;
  servingAgents = builtins.filter (agent: agent.enable && isServingLabel agent.config.Label) (
    builtins.attrValues agents
  );
  servingAgentLabels = map (agent: agent.config.Label) servingAgents;
  servingAgentActivation = hmConfigStaticServing.config.home.activation.enableMlxServingAgents.data;
  residentAgents = builtins.filter (agent: isServingLabel agent.config.Label) (
    builtins.attrValues agents
  );
  labels = map (agent: agent.config.Label) residentAgents;
  contracts = cfg.staticResidentContracts;
  mlxLmServer = import ../../modules/mlx/mlx-lm-server.nix {
    inherit pkgs cfg;
    versions = import ../../lib/versions.nix;
  };
  qwen = contracts."mlx-community/Qwen3.8-27B-4bit";
  small9b = contracts."mlx-community/Qwen3.5-9B-OptiQ-4bit";
  session = hmConfigStaticServing.config.home.sessionVariables;
  limits =
    builtins.fromJSON
      hmConfigStaticServing.config.home.file.".config/mlx/resident-model-limits.json".text;
  small9bAgent = builtins.head (
    builtins.filter (agent: lib.hasSuffix ".qwen35-9b" agent.config.Label) residentAgents
  );
  preflightServer = builtins.head small9bAgent.config.ProgramArguments;
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
          "dev.mlx-model-server.qwen35-9b"
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

  mlx-static-serving-launchd-enable = builtins.seq agentsDeepSeq (
    if
      servingAgentLabels != [ ]
      && lib.all (
        label: lib.hasInfix "launchctl enable \"gui/$uid/${label}\"" servingAgentActivation
      ) servingAgentLabels
    then
      helpers.mkMarker "check-mlx-static-serving-launchd-enable" "activation enables every declared serving LaunchAgent before setupLaunchAgents"
    else
      throw "activation must enable every declared dev.mlx-model-server LaunchAgent"
  );

  mlx-static-resident-limits =
    if
      small9b.concurrency == 4
      && hasPair small9bAgent.config.ProgramArguments "--decode-concurrency" "4"
      && hasPair small9bAgent.config.ProgramArguments "--prompt-concurrency" "4"
      && small9bAgent.config.EnvironmentVariables.MLX_MAX_PENDING_REQUESTS == toString small9b.queueSize
      && limits.aliases.judge == small9b.model
      && limits.aliases.recorder == small9b.model
      && limits.aliases.medium == qwen.model
      && limits.aliases.small == small9b.model
      &&
        limits.routerUrl
        == "http://127.0.0.1:${toString hmConfigStaticServing.config.programs.litellmLocal.port}/v1"
      && limits.clients.ghGuard.url == "${limits.routerUrl}/chat/completions"
      && limits.clients.ghGuard.timeoutSeconds == small9b.timeoutSeconds
      && limits.clients.recorder.identity == "recorder"
      && limits.clients.recorder.models.medium == "medium"
      && limits.clients.recorder.models.small == "small"
      &&
        limits.clients.recorder.requestTimeoutSeconds == builtins.foldl' lib.max 0 (
          map (model: limits.models.${model}.timeoutSeconds) [
            qwen.model
            small9b.model
          ]
        )
      &&
        limits.clients.recorder.pipeTimeoutSeconds == builtins.foldl' lib.max 0 (
          map (model: limits.models.${model}.pipeTimeoutSeconds) [
            qwen.model
            small9b.model
          ]
        )
      && limits.clients.recorder.pipeTimeoutSeconds > limits.clients.recorder.requestTimeoutSeconds
      && limits.models.${small9b.model}.timeoutSeconds == small9b.timeoutSeconds
      && limits.models.${small9b.model}.pipeTimeoutSeconds > limits.models.${small9b.model}.timeoutSeconds
      && limits.models.${small9b.model}.queueSize == small9b.queueSize
      && limits.models.${qwen.model}.timeoutSeconds == qwen.timeoutSeconds
      && limits.models.${qwen.model}.pipeTimeoutSeconds > limits.models.${qwen.model}.timeoutSeconds
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
      throw "static resident mode must derive Qwen3.5 concurrency and client limits from the resident catalog with no swap or TTL";

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
