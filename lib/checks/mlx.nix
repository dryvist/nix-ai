# MLX module regression tests and LaunchAgent validation
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  mlxCfg = hmConfig.config.programs.mlx;
in
{
  # Verify all expected MLX option paths exist.
  # Flat structure — no nested backend settings (vllm-mlx only since v0.2.6).
  mlx-options-regression = helpers.mkOptionsRegression {
    label = "MLX";
    checkName = "check-mlx-options-regression";
    cfg = mlxCfg;
    expectedOptions = [
      "autoUnloadIdleSeconds"
      "bufferCacheLimitGb"
      "cacheMemoryMb"
      "chunkedPrefillTokens"
      "completionBatchSize"
      "continuousBatching"
      "defaultModel"
      "enable"
      "enableAutoToolChoice"
      "enableMetrics"
      "enablePrefixCaching"
      "gpuMemoryUtilization"
      "host"
      "huggingFaceHome"
      "maxTokens"
      "maxNumSeqs"
      "memoryHardLimitGb"
      "models"
      "pagedKvCache"
      "port"
      "prefillBatchSize"
      "proxy"
      "reasoningParser"
      "serverLogLevel"
      "toolCallParser"
    ];
  };

  # Verify MLX evaluated config values match expected defaults.
  mlx-defaults-regression = helpers.mkDefaultsRegression {
    label = "MLX";
    checkName = "check-mlx-defaults-regression";
    checks = [
      {
        name = "mlx.enable";
        actual = mlxCfg.enable;
        expected = true;
      }
      {
        # Presence-only check — the actual model id is parameterized via
        # services.aiStack.defaultLocalModelId and not hardcoded in this
        # repo. Verifying it's a non-empty string is enough; the consumer
        # owns the value.
        name = "mlx.defaultModel-populated";
        actual = mlxCfg.defaultModel != null && mlxCfg.defaultModel != "";
        expected = true;
      }
      {
        name = "mlx.port";
        actual = mlxCfg.port;
        expected = 11434;
      }
      {
        name = "mlx.host";
        actual = mlxCfg.host;
        expected = "127.0.0.1";
      }
      {
        name = "mlx.huggingFaceHome";
        actual = mlxCfg.huggingFaceHome;
        expected = "/Volumes/HuggingFace";
      }
      {
        name = "mlx.cacheMemoryMb";
        actual = mlxCfg.cacheMemoryMb;
        expected = 8192;
      }
      {
        name = "mlx.gpuMemoryUtilization";
        actual = mlxCfg.gpuMemoryUtilization;
        expected = 0.8;
      }
      {
        name = "mlx.autoUnloadIdleSeconds";
        actual = mlxCfg.autoUnloadIdleSeconds;
        expected = 1800;
      }
      {
        name = "mlx.bufferCacheLimitGb";
        actual = mlxCfg.bufferCacheLimitGb;
        expected = 12;
      }
      {
        name = "mlx.enableMetrics";
        actual = mlxCfg.enableMetrics;
        expected = true;
      }
      {
        name = "mlx.proxy.idleTtl";
        actual = mlxCfg.proxy.idleTtl;
        expected = 900;
      }
      {
        name = "mlx.proxy.concurrencyLimit";
        actual = mlxCfg.proxy.concurrencyLimit;
        expected = 4;
      }
      {
        name = "mlx.prefillBatchSize";
        actual = mlxCfg.prefillBatchSize;
        expected = null;
      }
      {
        name = "mlx.continuousBatching";
        actual = mlxCfg.continuousBatching;
        expected = true;
      }
      {
        name = "mlx.maxNumSeqs";
        actual = mlxCfg.maxNumSeqs;
        expected = 4;
      }
      {
        name = "mlx.enablePrefixCaching";
        actual = mlxCfg.enablePrefixCaching;
        expected = true;
      }
      {
        name = "mlx.pagedKvCache";
        actual = mlxCfg.pagedKvCache;
        expected = true;
      }
      {
        name = "mlx.chunkedPrefillTokens";
        actual = mlxCfg.chunkedPrefillTokens;
        expected = null;
      }
      {
        name = "mlx.completionBatchSize";
        actual = mlxCfg.completionBatchSize;
        expected = null;
      }
      {
        name = "mlx.maxTokens";
        actual = mlxCfg.maxTokens;
        expected = 8192;
      }
      {
        name = "mlx.memoryHardLimitGb";
        actual = mlxCfg.memoryHardLimitGb;
        expected = 99;
      }
      {
        name = "mlx.enableAutoToolChoice";
        actual = mlxCfg.enableAutoToolChoice;
        expected = true;
      }
      {
        name = "mlx.toolCallParser";
        actual = mlxCfg.toolCallParser;
        expected = "hermes";
      }
      {
        name = "mlx.reasoningParser";
        actual = mlxCfg.reasoningParser;
        expected = null;
      }
      {
        name = "mlx.serverLogLevel";
        actual = mlxCfg.serverLogLevel;
        expected = "info";
      }
      # Environment variables
      {
        name = "mlx.env.MLX_DEFAULT_MODEL";
        actual = hmConfig.config.home.sessionVariables.MLX_DEFAULT_MODEL;
        expected = mlxCfg.defaultModel;
      }
      {
        name = "mlx.env.MLX_API_URL";
        actual = hmConfig.config.home.sessionVariables.MLX_API_URL;
        expected = "http://127.0.0.1:11434/v1";
      }
      {
        name = "mlx.env.MLX_PORT";
        actual = hmConfig.config.home.sessionVariables.MLX_PORT;
        expected = "11434";
      }
      {
        name = "mlx.env.MLX_HOST";
        actual = hmConfig.config.home.sessionVariables.MLX_HOST;
        expected = "127.0.0.1";
      }
    ];
  };

  # The backend-neutral serverLogLevel must reach the selected server's native
  # command. This catches a backend switch silently falling back to its own
  # logging default while the evaluated option still reports "debug".
  mlx-server-log-level =
    let
      testServerPkg = pkgs.writeShellScriptBin "mlx-lm-server-test" "exit 0";
      cmd =
        (import ../../modules/mlx/model-server-cmd.nix {
          inherit (pkgs) lib;
          cfg = mlxCfg;
          mlxModelServerPkg = testServerPkg;
        }).mkModelCmd
          mlxCfg.defaultModel;
    in
    assert
      builtins.match ".*--log-level INFO.*" cmd != null
      || throw "programs.mlx.serverLogLevel=info did not render --log-level INFO for mlx_lm";
    helpers.mkMarker "check-mlx-server-log-level" "MLX server log level: INFO reaches the official mlx_lm command";

  # Validate MLX LaunchAgent ProgramArguments use llama-swap proxy,
  # and that the generated llama-swap config JSON contains required fields.
  # With the llama-swap architecture, model-server flags live inside the JSON
  # config (embedded in cmd strings), not in the LaunchAgent ProgramArguments.
  mlx-launchd =
    let
      launchdCfg = hmConfig.config.launchd.agents.mlx-model-server.config;
      args = launchdCfg.ProgramArguments;
      argsStr = builtins.concatStringsSep " " args;

      # Proxy-level flags that must NEVER appear in ProgramArguments (belong in JSON config)
      bannedInProxyArgs = [
        "--max-kv-size"
        "--prefill-step-size"
        "--prompt-cache-size"
        "--decode-concurrency"
        "--prompt-concurrency"
        "--draft-model"
        "--num-draft-tokens"
        "--pipeline"
        "serve"
      ];
      presentBanned = builtins.filter (f: builtins.match ".*${f}.*" argsStr != null) bannedInProxyArgs;

      # llama-swap proxy args that must always be present
      requiredSubstrings = [
        "--config"
        "--watch-config"
        "--listen"
      ];
      missingRequired = builtins.filter (f: builtins.match ".*${f}.*" argsStr == null) requiredSubstrings;

      # Verify the --config argument has a following path argument.
      # The path is a mutable runtime config (e.g. ~/.config/mlx/llama-swap.json)
      # that llama-swap watches for changes via --watch-config.
      configArgIdx =
        let
          idxList = builtins.filter (i: builtins.elemAt args i == "--config") (
            builtins.genList (i: i) (builtins.length args)
          );
        in
        if idxList == [ ] then -1 else builtins.head idxList;
      configFileArg =
        if configArgIdx >= 0 && configArgIdx + 1 < builtins.length args then
          builtins.elemAt args (configArgIdx + 1)
        else
          "";
      configArgPresent = configFileArg != "";
    in
    assert
      presentBanned == [ ]
      || throw "Banned flags in llama-swap ProgramArguments (should be in JSON config): ${builtins.toJSON presentBanned}";
    assert
      missingRequired == [ ]
      || throw "Missing required llama-swap proxy flags in ProgramArguments: ${builtins.toJSON missingRequired}";
    assert configArgPresent || throw "ProgramArguments has --config but no following path argument";
    helpers.mkMarker "check-mlx-launchd" "MLX LaunchAgent: llama-swap proxy args verified (--config ${configFileArg} --watch-config --listen present)";

  # Verify OOM prevention: ProcessType in LaunchAgent.
  # HardResourceLimits is intentionally absent — it would only cap the llama-swap
  # proxy process, not the MLX model-server children where memory lives.
  # ProcessType defaults to Interactive since #916: Background's QoS clamp
  # throttles Metal decode ~8x; the OOM backstop is the RSS hard limit
  # (programs.mlx.memoryHardLimitGb), not Jetsam eligibility.
  mlx-launchd-memory-safety =
    let
      launchdCfg = hmConfig.config.launchd.agents.mlx-model-server.config;
    in
    assert
      launchdCfg.ProcessType == "Interactive"
      || throw "ProcessType default must be \"Interactive\" — Background QoS clamps Metal decode ~8x (#916)";
    assert
      (!(launchdCfg ? HardResourceLimits) || launchdCfg.HardResourceLimits == null)
      || throw "HardResourceLimits must NOT be set on the llama-swap proxy (only constrains proxy, not model-server children)";
    helpers.mkMarker "check-mlx-launchd-memory-safety" "MLX LaunchAgent memory safety: ProcessType=Interactive verified; HardResourceLimits correctly absent from proxy";

  # Negative test: verify the banned-flag detection logic actually catches bad flags.
  # Without this, a regex typo in mlx-launchd could silently pass banned flags through.
  # These are flags that must NOT appear in the llama-swap proxy ProgramArguments
  # (they belong in the JSON config cmd strings, not the proxy args).
  mlx-launchd-negative =
    let
      # Synthetic args strings containing banned flags — each MUST be detected
      testCases = [
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 serve model";
          bannedFlag = "serve";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --max-kv-size 1024";
          bannedFlag = "--max-kv-size";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --prefill-step-size 256";
          bannedFlag = "--prefill-step-size";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --prompt-cache-size 512";
          bannedFlag = "--prompt-cache-size";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --decode-concurrency 4";
          bannedFlag = "--decode-concurrency";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --prompt-concurrency 2";
          bannedFlag = "--prompt-concurrency";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --draft-model foo";
          bannedFlag = "--draft-model";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --num-draft-tokens 8";
          bannedFlag = "--num-draft-tokens";
        }
        {
          input = "llama-swap --config foo.json --listen 127.0.0.1:11434 --pipeline parallel";
          bannedFlag = "--pipeline";
        }
      ];
      # Same detection logic as mlx-launchd — if this changes there, it must change here
      detect = flag: str: builtins.match ".*${flag}.*" str != null;
      # Every banned flag must be detected
      undetected = builtins.filter (tc: !(detect tc.bannedFlag tc.input)) testCases;
    in
    assert
      undetected == [ ]
      || throw "Negative test failed — banned flags NOT detected: ${
        builtins.toJSON (map (tc: tc.bannedFlag) undetected)
      }";
    helpers.mkMarker "check-mlx-launchd-negative" "MLX LaunchAgent negative: ${toString (builtins.length testCases)} banned flag patterns verified detectable";
}
