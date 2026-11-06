# The local API URL is defined once, then consumed by clients and the existing
# fallback watcher. Keep this check against the evaluated Home Manager output.
{
  pkgs,
  src,
  hmConfig,
  hmConfigLitellmLocal,
  hmConfigStaticServing,
  mkHmConfig,
}:
let
  inherit (pkgs) lib;
  consumerFiles = [
    "modules/antigravity-cli/default.nix"
    "modules/cecli/settings.nix"
    "modules/claude/settings-env.nix"
    "modules/codex/settings.nix"
    "modules/fabric/packages.nix"
    "modules/litellm-local/commands.nix"
    "modules/litellm-local/launchd.nix"
    "modules/mlx/default.nix"
    "modules/mlx/packages.nix"
    "modules/mlx/static-residents.nix"
    "modules/opencode/default.nix"
    "modules/qwen-code/endpoint.nix"
    "modules/scripts/litellm-fallback-probe.sh"
    "vars/ai-stack.nix"
    "orchestrator/examples/skills/code-explain.yaml"
    "orchestrator/examples/skills/code-review.yaml"
    "orchestrator/examples/skills/structured-extract.yaml"
    "orchestrator/examples/skills/vault-search.yaml"
    "orchestrator/examples/workflows/code-review-pipeline.yaml"
    "orchestrator/src/orchestrator/indexing/pipeline.py"
    "orchestrator/src/orchestrator/router.py"
    "orchestrator/src/orchestrator/skill_schema.py"
    "orchestrator/src/orchestrator/workflows/nodes.py"
  ];
  staleUrl = "http://127.0.0.1:11434";
  hasStaleClientUrl = builtins.any (
    path: lib.hasInfix staleUrl (builtins.readFile (src + "/${path}"))
  ) consumerFiles;

  local = hmConfigLitellmLocal.config;
  localUrl = local.services.aiStack.localRouterUrl;
  watcher = local.launchd.agents.litellm-fallback-watch.config;
  watchEnvironment = watcher.EnvironmentVariables;
  watcherCoversProxy =
    watcher.Label == "dev.litellm-fallback-watch"
    && watcher.StartInterval > 0
    && watchEnvironment.LITELLM_LOCAL_URL == lib.removeSuffix "/v1" localUrl
    &&
      watchEnvironment.LITELLM_ALERT_URL_FILE
      == local.home.homeDirectory + "/.config/mlx-cluster/alert-url";

  bearerFromEnv = mkHmConfig [
    {
      programs.litellmLocal.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointBearerFromEnv = true;
      };
    }
  ];
  bearerConfig = bearerFromEnv.config.services.aiStack;
  startScriptSource = builtins.readFile (src + "/modules/litellm-local/commands.nix");
  bearerStartUsesEnv =
    bearerConfig.llmEndpointBearerFromEnv
    && bearerConfig.llmEndpointTokenFile == null
    && lib.hasInfix "if aiStack.llmEndpointTokenFile != null then" startScriptSource
    && lib.hasInfix "OPENAI_API_KEY:?" startScriptSource;

in
assert !hasStaleClientUrl || throw "A local client still hardcodes http://127.0.0.1:11434";
assert
  localUrl == local.programs.litellmLocal.baseUrl
  || throw "localRouterUrl must derive from the enabled proxy base URL";
assert
  local.programs.litellmLocal.port == 4100
  || throw "the local proxy must use the allocated loopback port 4100";
assert
  hmConfigStaticServing.config.home.sessionVariables.MLX_API_URL
  == hmConfigStaticServing.config.services.aiStack.localRouterUrl
  || throw "MLX_API_URL must derive from services.aiStack.localRouterUrl";
assert
  watcherCoversProxy
  || throw "dev.litellm-fallback-watch must probe the local proxy and reuse the shared Slack webhook";
assert
  bearerStartUsesEnv
  || throw "the token-file branch must be skipped when OPENAI_API_KEY comes from the launch prefix";
assert
  hmConfig.config.home.sessionVariables.MLX_API_URL == hmConfig.config.services.aiStack.localRouterUrl
  || throw "the standard MLX client URL must derive from services.aiStack.localRouterUrl";
{
  local-router-url = pkgs.runCommand "check-local-router-url" { } ''
    touch $out
  '';
}
