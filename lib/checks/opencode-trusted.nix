# Trusted OpenCode provider and launcher checks.
{
  pkgs,
  hmConfig,
  mkHmConfig,
}:
let
  settingsFile = hmConfig.config.home.file.".config/opencode/opencode.json".source;
  sessionPlugin = hmConfig.config.home.file.".config/opencode/plugins/go-session.js".source;
  package = hmConfig.config.programs.opencode.package;
  trustedPackage =
    import ../../modules/opencode/trusted.nix
      {
        inherit (pkgs) lib;
        inherit pkgs;
      }
      {
        inherit package;
      };
  wallPackage =
    import ../../modules/opencode/sandbox.nix
      {
        inherit (pkgs) lib;
        inherit pkgs;
      }
      {
        inherit package;
        home = hmConfig.config.home.homeDirectory;
        workRoot = "${hmConfig.config.home.homeDirectory}/opencode-work";
        binaryName = "opencode-wall";
        realBinaryName = "opencode";
      };
  fakePackage = pkgs.writeShellScriptBin "opencode" ''
    printf '%s\n' \
      "$PWD" \
      "$LLM_ROUTER_URL" \
      "$AGENT_ROUTER_KEY" \
      "$OPENCODE_API_KEY" \
      "$@" > "$OPENCODE_TEST_OUTPUT"
  '';
  fakeCredentialPrefix = pkgs.writeShellScriptBin "opencode-test-credentials" ''
    export LLM_ROUTER_URL=https://router.example.invalid/v1
    export AGENT_ROUTER_KEY=router-test-key
    export OPENCODE_API_KEY=go-test-key
    exec "$@"
  '';
  launcher =
    import ../../modules/opencode/trusted.nix
      {
        inherit (pkgs) lib;
        inherit pkgs;
      }
      {
        package = fakePackage;
        launchPrefix = [ "${fakeCredentialPrefix}/bin/opencode-test-credentials" ];
      };
  localConfig = mkHmConfig [
    {
      programs = {
        opencode.enable = true;
        litellmLocal.enable = true;
      };
      services.aiStack = {
        llmEndpoint = "router";
        llmEndpointTokenFile = "/run/test/router-token";
        llmRouterEndpoint = "https://router.example.invalid/v1";
      };
    }
  ];
  localSettings = localConfig.config.home.file.".config/opencode/opencode.json".source;
in
{
  opencode-go-session-plugin =
    pkgs.runCommand "check-opencode-go-session-plugin"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
      }
      ''
        cp ${../../modules/opencode/plugins/go-session.js} "$TMPDIR/plugin.mjs"
        cp ${./scripts/opencode-go-session-plugin-test.mjs} "$TMPDIR/test.mjs"
        node "$TMPDIR/test.mjs" "$TMPDIR/plugin.mjs"
        touch $out
      '';

  opencode-trusted-package-build = pkgs.runCommand "check-opencode-trusted-package-build" { } ''
    test -x ${package}/bin/opencode
    test -x ${trustedPackage}/bin/opencode
    test -x ${wallPackage}/bin/opencode-wall
    touch $out
  '';

  opencode-trusted-provider-config =
    pkgs.runCommand "check-opencode-trusted-provider-config" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        test -s ${sessionPlugin}
        jq -e '
          .permission == "allow" and
          .model == "litellm/medium" and
          .small_model == "litellm/small" and
          .provider.litellm.options == {
            baseURL: "{env:LLM_ROUTER_URL}",
            apiKey: "{env:AGENT_ROUTER_KEY}"
          } and
          (["large", "medium", "small", "go-mimo-flash", "go-deepseek-flash",
            "go-glm-flash", "go-kimi-k3", "go-qwen-plus", "go-minimax-m3"] -
            (.provider.litellm.models | keys)) == [] and
          .provider["opencode-go"].options.baseURL == "https://opencode.ai/zen/go/v1" and
          .provider["opencode-go"].options.apiKey == "{env:OPENCODE_API_KEY}" and
          (.provider["opencode-go"].options.headers // {}) == {} and
          .provider["opencode-go"].models["go-mimo-flash"].id == "mimo-v2.6-flash" and
          (.provider["opencode-go"].models | keys) == ["go-deepseek-flash", "go-glm-flash", "go-kimi-k3", "go-mimo-flash"] and
          .provider["opencode-go-anthropic"].npm == "@ai-sdk/anthropic" and
          .provider["opencode-go-anthropic"].models["go-qwen-plus"].id == "qwen3.7-plus" and
          (.provider["opencode-go-anthropic"].models | keys) == ["go-minimax-m3", "go-qwen-plus"]
        ' ${settingsFile} >/dev/null
        if grep -Eq '(router-test-key|go-test-key)' ${settingsFile}; then
          echo "provider credentials must be environment references" >&2
          exit 1
        fi
        jq -e '
          .provider.mlx.name == "MLX (local)" and
          .provider.mlx.options.baseURL == "http://127.0.0.1:11434/v1"
        ' ${localSettings} >/dev/null
        touch $out
      '';

  opencode-trusted-launcher = pkgs.runCommand "check-opencode-trusted-launcher" { } ''
    export PATH="${pkgs.git}/bin:$PATH"
    for workdir in "$TMPDIR/no-repository" "$TMPDIR/repository-outside-work-root"; do
      mkdir -p "$workdir"
      if [ "$workdir" = "$TMPDIR/repository-outside-work-root" ]; then
        git -C "$workdir" init -q
      else
        test ! -e "$workdir/.git"
      fi
      cd "$workdir"
      output="$TMPDIR/opencode-output-$(basename "$workdir")"
      OPENCODE_TEST_OUTPUT="$output" ${launcher}/bin/opencode --model litellm/medium "hello world"
      grep -Fx "$PWD" "$output" >/dev/null
      grep -Fx "https://router.example.invalid/v1" "$output" >/dev/null
      grep -Fx "router-test-key" "$output" >/dev/null
      grep -Fx "go-test-key" "$output" >/dev/null
      grep -Fx -- "--model" "$output" >/dev/null
      grep -Fx "litellm/medium" "$output" >/dev/null
      grep -Fx "hello world" "$output" >/dev/null
    done
    touch $out
  '';
}
