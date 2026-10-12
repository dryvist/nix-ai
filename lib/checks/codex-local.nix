{ pkgs, hmConfigRouter }:
let
  routerProfile = hmConfigRouter.config.home.file.".codex/local.config.toml".source;
  localRouterAlias = "small";
  routerAliases = import ../../modules/litellm-local/aliases.nix;
in
{
  codex-local-router-profile =
    assert builtins.elem localRouterAlias routerAliases;
    pkgs.runCommand "check-codex-local-router-profile"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        expectedBaseUrl = hmConfigRouter.config.services.aiStack.llmRouterEndpoint;
      }
      ''
        python3 - ${routerProfile} "$expectedBaseUrl" <<'PY'
        import sys, tomllib

        profile_path, expected_base_url = sys.argv[1:]
        with open(profile_path, "rb") as f:
            cfg = tomllib.load(f)

        assert cfg["model"] == "small", cfg.get("model")
        assert cfg["model_provider"] == "router", cfg.get("model_provider")
        assert cfg["model_reasoning_effort"] == "low", cfg.get("model_reasoning_effort")
        provider = cfg["model_providers"]["router"]
        assert provider["name"] == "router", provider
        assert provider["base_url"] == expected_base_url, provider
        assert provider["env_key"] == "AGENT_ROUTER_KEY", provider
        assert provider["wire_api"] == "responses", provider

        print("codex-local-router-profile: provider, alias, reasoning, endpoint, and scoped key name verified")
        PY
        touch $out
      '';
}
