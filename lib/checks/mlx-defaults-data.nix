# Declared-default expectations for programs.mlx.
#
# Split out of ./mlx.nix, which reached the .file-size.yml ceiling. The split is
# by responsibility: this file is the DATA (what each option's default should
# be), and mlx.nix keeps the checks that exercise behaviour -- the rendered
# server command, the LaunchAgent, the negative cases.
#
# `mlxCfg` is passed in rather than re-derived so both files assert against the
# same evaluated configuration.
{ mlxCfg, hmConfig }:
[
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
    expected = 1;
  }
  {
    name = "mlx.prefillBatchSize";
    actual = mlxCfg.prefillBatchSize;
    expected = null;
  }
  {
    # DERIVED from the backend, not a constant. It was a flat `true`, which
    # meant an mlx-lm host's config read "batching on" against a builder
    # that emits no --continuous-batching at all -- a config that described
    # a capability the server did not have. This fixture selects mlx-lm, so
    # false is the truthful value; a vllm-mlx host gets true.
    name = "mlx.continuousBatching";
    actual = mlxCfg.continuousBatching;
    expected = mlxCfg.modelServerBackend == "vllm-mlx";
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
]
