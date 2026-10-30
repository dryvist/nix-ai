#
# Qwen Code Module — Aggregator
#
# Qwen Code (https://github.com/QwenLM/qwen-code) is Alibaba's terminal
# coding agent. Claude-Code-style UX for Qwen3-Coder and any other
# OpenAI/Anthropic/Gemini-compatible endpoint.
#
# Uses a Qwen catalog entry's static resident endpoint when the host serves
# one; otherwise it follows the configured local proxy or stack endpoint.
# Cloud Dashscope / OpenRouter / OpenAI access is opt-in: run `qwen` with the
# provider keys in its environment.
#
# Why nixpkgs (not llm-agents / brew / uvx): it is the only source with a cache
# hit on every consumer. llm-agents.nix has a far newer qwen-code and stays
# selectable via `installVia`, but defaulting to it made nix-darwin build the
# package from source — it has no numtide substituter — and that build OOMs a
# CI runner. A Homebrew formula, the original source, had no Linux path at all,
# which is one of the reasons this stack could not leave the Mac.
#
{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:

let
  cfg = config.programs.qwen-code;
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  modelMode = import ./model-mode.nix { inherit config lib; };
  modelEndpoints = map (modelName: modelMode.endpoint modelName) cfg.models;
  residentLoopbackPorts = lib.unique (
    lib.filter (port: port != null) (
      map (
        endpoint:
        if endpoint == null then
          null
        else
          let
            matched = builtins.match "https?://(127\\.0\\.0\\.1|localhost):([0-9]+)(/.*)?" endpoint;
          in
          if matched == null then null else lib.toInt (builtins.elemAt matched 1)
      ) modelEndpoints
    )
  );
  # Open only the loopback port of the endpoint Qwen Code actually uses; a
  # remote endpoint needs no loopback allowance.
  loopbackEndpoint = builtins.match "https?://(127\\.0\\.0\\.1|localhost):([0-9]+)(/.*)?" (
    import ./endpoint.nix { inherit config; }
  );
  localPorts =
    if modelMode.bySize then
      residentLoopbackPorts
    else
      lib.optional (loopbackEndpoint != null) (lib.toInt (builtins.elemAt loopbackEndpoint 1));

  sandboxedQwen = import ./sandbox.nix { inherit pkgs lib; } {
    qwen = cfg.package;
    home = config.home.homeDirectory;
    workRoot = cfg.sandbox.workRoot;
    inherit localPorts;
  };
in
{
  imports = [
    ./native-hooks.nix
    ./options.nix
    ./settings.nix
    ../litellm-local/options.nix
  ];

  config = lib.mkMerge [
    { programs.qwen-code.sandboxLocalPorts = localPorts; }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.sandbox.enable || pkgs.stdenv.hostPlatform.isDarwin;
          message = "programs.qwen-code.sandbox.enable needs macOS: the Seatbelt profile is applied by /usr/bin/sandbox-exec.";
        }
        {
          assertion = !cfg.sandbox.enable || cfg.package != null;
          message = "programs.qwen-code.sandbox.enable needs a packaged qwen binary so the launcher can name its executable.";
        }
        {
          assertion =
            !modelMode.bySize
            || (
              cfg.models != [ ]
              && lib.all modelMode.isQwenCatalogModel cfg.models
              && lib.elem cfg.model cfg.models
            );
          message = "programs.qwen-code.model and models must name Qwen model catalog keys, with the selected model in the allowed set.";
        }
        {
          assertion = !modelMode.bySize || lib.all modelMode.hasResidentModel cfg.models;
          message = "programs.qwen-code.models must name Qwen catalog entries served by this host's static MLX residents.";
        }
        {
          assertion = !(modelMode.isQwenCatalogModel cfg.model) || modelMode.hasResidentModel cfg.model;
          message = "programs.qwen-code.model names a Qwen catalog key without a static MLX resident on this host.";
        }
      ];

      programs.qwen-code.package = lib.mkMerge [
        (lib.mkIf (cfg.installVia == "llm-agents") (lib.mkDefault llmAgents.qwen-code))
        (lib.mkIf (cfg.installVia == "nixpkgs") (lib.mkDefault pkgs.qwen-code))
      ];

      home = {
        packages = lib.optional (cfg.package != null) (
          if cfg.sandbox.enable then sandboxedQwen else cfg.package
        );
        file.".qwen/.keep".text = "# Managed by Nix — programs.qwen-code\n";
      };
    })
  ];
}
