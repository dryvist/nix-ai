# Codex OpenAI model policy: Luna at xhigh (AGENTS.md, "Delegation routing").
{
  pkgs,
  hmConfig,
}:
let
  cfg = hmConfig.config.programs.codex;
  homeFileNames = builtins.attrNames hmConfig.config.home.file;
  codexProfilePaths = builtins.filter (
    path: pkgs.lib.hasInfix "codex/" path && pkgs.lib.hasSuffix ".config.toml" path
  ) homeFileNames;
  codexProfileSources = map (
    path: (builtins.getAttr path hmConfig.config.home.file).source
  ) codexProfilePaths;
in
{
  # Apply the OpenAI model policy to OpenAI profiles; Z.ai and LiteLLM profiles keep their provider settings.
  codex-openai-model-policy =
    assert cfg.modelFamily == "luna";
    assert cfg.model == null || pkgs.lib.hasSuffix "-luna" cfg.model;
    assert cfg.modelReasoningEffort == "xhigh";
    assert cfg.planModeReasoningEffort == "xhigh";
    pkgs.runCommand "check-codex-openai-model-policy"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - ${pkgs.lib.escapeShellArgs (map toString codexProfileSources)} <<'PYEOF'
        import sys
        import tomllib

        checked = 0
        for profile_path in sys.argv[1:]:
            with open(profile_path, "rb") as profile_file:
                profile = tomllib.load(profile_file)

            provider = profile.get("model_provider", "openai")
            if provider is not None and provider.lower() != "openai":
                continue

            assert profile.get("model", "").endswith("-luna"), profile_path
            assert profile.get("model_reasoning_effort") == "xhigh", profile_path
            checked += 1

        print(f"codex-openai-model-policy: {checked} OpenAI profiles use Luna at xhigh")
        PYEOF
        touch $out
      '';
}
