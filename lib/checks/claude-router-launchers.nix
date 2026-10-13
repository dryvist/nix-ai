{ pkgs }:
let
  launchers = pkgs.callPackage ../../modules/claude-router-pkgs.nix { };
  fakeClaude = pkgs.writeShellScriptBin "claude" ''
    test "$ANTHROPIC_AUTH_TOKEN" = "$EXPECTED_AUTH_TOKEN"
    printf 'AUTH_TOKEN_PRESENT=yes\n'
    printf 'BASE_URL=%s\n' "$ANTHROPIC_BASE_URL"
    printf 'MODEL=%s\n' "$ANTHROPIC_MODEL"
    printf 'OPUS=%s\n' "$ANTHROPIC_DEFAULT_OPUS_MODEL"
    printf 'SONNET=%s\n' "$ANTHROPIC_DEFAULT_SONNET_MODEL"
    printf 'HAIKU=%s\n' "$ANTHROPIC_DEFAULT_HAIKU_MODEL"
    printf 'SUBAGENT=%s\n' "$CLAUDE_CODE_SUBAGENT_MODEL"
    test -z "$ANTHROPIC_API_KEY" && printf 'API_KEY_EMPTY=yes\n'
    test -z "$ANTHROPIC_CUSTOM_HEADERS" && printf 'CUSTOM_HEADERS_EMPTY=yes\n'
    test -z "$CLAUDE_CODE_OAUTH_TOKEN" && printf 'OAUTH_EMPTY=yes\n'
    test -z "$CLAUDE_CODE_USE_BEDROCK" && printf 'BEDROCK_EMPTY=yes\n'
    test -z "$CLAUDE_CODE_USE_VERTEX" && printf 'VERTEX_EMPTY=yes\n'
    test -z "$CLAUDE_CODE_USE_FOUNDRY" && printf 'FOUNDRY_EMPTY=yes\n'
    test -z "$OPENAI_API_KEY" && printf 'OPENAI_API_KEY_EMPTY=yes\n'
    test -z "''${CLAUDE_LLM_ROUTER_KEY:-}" && printf 'LLM_SOURCE_KEY_EMPTY=yes\n'
    test -z "''${CLAUDE_OCG_ROUTER_KEY:-}" && printf 'OCG_SOURCE_KEY_EMPTY=yes\n'
    test -z "''${OPENCODE_GO_API_KEY:-}" && printf 'DIRECT_SOURCE_KEY_EMPTY=yes\n'
    test -z "''${CLAUDE_LLM_KEY_COMMAND:-}''${CLAUDE_OCG_KEY_COMMAND:-}''${OCG_DIRECT_KEY_COMMAND:-}" \
      && printf 'KEY_COMMANDS_EMPTY=yes\n'
    test -z "''${NIX_AI_CLAUDE_ROUTER_FETCH_ATTEMPTED:-}" && printf 'FETCH_MARKER_EMPTY=yes\n'
    test -z "''${NIX_AI_CLAUDE_ROUTER_FETCH_MODE:-}" && printf 'FETCH_MODE_EMPTY=yes\n'
    printf 'NONESSENTIAL_TRAFFIC=%s\n' "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
    printf 'UNKNOWN_MODEL_ENFORCEMENT=%s\n' "$CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT"
    printf 'ARG=<%s>\n' "$@"
  '';
  fakeKeyCommand = pkgs.writeShellScriptBin "fetch-test-key" ''
    export "$TEST_KEY_ENV=$TEST_KEY_VALUE"
    exec "$@"
  '';
in
{
  claude-router-launchers =
    pkgs.runCommand "check-claude-router-launchers"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          fakeClaude
          fakeKeyCommand
        ];
      }
      ''
        set -euo pipefail
        test -L ${launchers.claudeOcg}/bin/claude-go

        assert_line() {
          grep -Fxq -- "$1" <<<"$2" || {
            printf 'missing expected launcher output: %s\n' "$1" >&2
            exit 1
          }
        }

        export LLM_ROUTER_URL=https://router.example.invalid/v1
        export ANTHROPIC_API_KEY=ambient-api-key
        export ANTHROPIC_AUTH_TOKEN=ambient-auth-token
        export ANTHROPIC_CUSTOM_HEADERS=ambient-header
        export CLAUDE_CODE_OAUTH_TOKEN=ambient-oauth-token
        export CLAUDE_CODE_USE_BEDROCK=1
        export CLAUDE_CODE_USE_VERTEX=1
        export CLAUDE_CODE_USE_FOUNDRY=1
        export OPENAI_API_KEY=ambient-openai-key
        export CLAUDE_LLM_ROUTER_KEY=
        export CLAUDE_LLM_KEY_COMMAND=fetch-test-key
        export TEST_KEY_ENV=CLAUDE_LLM_ROUTER_KEY
        export TEST_KEY_VALUE=router-dummy-key
        export EXPECTED_AUTH_TOKEN=$TEST_KEY_VALUE

        llm_default_output="$(${launchers.claudeLlm}/bin/claude-llm)"
        assert_line 'MODEL=medium' "$llm_default_output"
        assert_line 'BASE_URL=https://router.example.invalid' "$llm_default_output"

        llm_output="$(
          ${launchers.claudeLlm}/bin/claude-llm --model custom-model 'two words'
        )"
        assert_line 'AUTH_TOKEN_PRESENT=yes' "$llm_output"
        assert_line 'BASE_URL=https://router.example.invalid' "$llm_output"
        assert_line 'MODEL=custom-model' "$llm_output"
        assert_line 'OPUS=medium' "$llm_output"
        assert_line 'SONNET=medium' "$llm_output"
        assert_line 'HAIKU=small' "$llm_output"
        assert_line 'SUBAGENT=medium' "$llm_output"
        assert_line 'API_KEY_EMPTY=yes' "$llm_output"
        assert_line 'CUSTOM_HEADERS_EMPTY=yes' "$llm_output"
        assert_line 'OAUTH_EMPTY=yes' "$llm_output"
        assert_line 'BEDROCK_EMPTY=yes' "$llm_output"
        assert_line 'VERTEX_EMPTY=yes' "$llm_output"
        assert_line 'FOUNDRY_EMPTY=yes' "$llm_output"
        assert_line 'OPENAI_API_KEY_EMPTY=yes' "$llm_output"
        assert_line 'LLM_SOURCE_KEY_EMPTY=yes' "$llm_output"
        assert_line 'KEY_COMMANDS_EMPTY=yes' "$llm_output"
        assert_line 'FETCH_MARKER_EMPTY=yes' "$llm_output"
        assert_line 'FETCH_MODE_EMPTY=yes' "$llm_output"
        assert_line 'NONESSENTIAL_TRAFFIC=1' "$llm_output"
        assert_line 'UNKNOWN_MODEL_ENFORCEMENT=1' "$llm_output"
        assert_line 'ARG=<--model>' "$llm_output"
        assert_line 'ARG=<custom-model>' "$llm_output"
        assert_line 'ARG=<two words>' "$llm_output"

        export CLAUDE_OCG_ROUTER_KEY=
        export CLAUDE_OCG_KEY_COMMAND=fetch-test-key
        export TEST_KEY_ENV=CLAUDE_OCG_ROUTER_KEY
        export TEST_KEY_VALUE=ocg-dummy-key
        export EXPECTED_AUTH_TOKEN=$TEST_KEY_VALUE
        ocg_output="$(${launchers.claudeOcg}/bin/claude-go prompt)"
        assert_line 'BASE_URL=https://router.example.invalid' "$ocg_output"
        assert_line 'MODEL=go-mimo-flash' "$ocg_output"
        assert_line 'OPUS=go-mimo-flash' "$ocg_output"
        assert_line 'SONNET=go-mimo-flash' "$ocg_output"
        assert_line 'HAIKU=go-deepseek-flash' "$ocg_output"
        assert_line 'SUBAGENT=go-deepseek-flash' "$ocg_output"
        assert_line 'OCG_SOURCE_KEY_EMPTY=yes' "$ocg_output"
        assert_line 'ARG=<prompt>' "$ocg_output"

        export OPENCODE_GO_API_KEY=
        export OCG_DIRECT_KEY_COMMAND=fetch-test-key
        export TEST_KEY_ENV=OPENCODE_GO_API_KEY
        export TEST_KEY_VALUE=direct-dummy-key
        export EXPECTED_AUTH_TOKEN=$TEST_KEY_VALUE
        direct_output="$(
          ${launchers.claudeOcg}/bin/claude-ocg --direct --model custom-direct-model prompt
        )"
        assert_line 'BASE_URL=https://opencode.ai/zen/go' "$direct_output"
        assert_line 'MODEL=custom-direct-model' "$direct_output"
        assert_line 'OPUS=qwen3.7-plus' "$direct_output"
        assert_line 'SONNET=qwen3.7-plus' "$direct_output"
        assert_line 'HAIKU=qwen3.7-plus' "$direct_output"
        assert_line 'SUBAGENT=qwen3.7-plus' "$direct_output"
        assert_line 'DIRECT_SOURCE_KEY_EMPTY=yes' "$direct_output"
        assert_line 'ARG=<--model>' "$direct_output"
        assert_line 'ARG=<custom-direct-model>' "$direct_output"
        assert_line 'ARG=<prompt>' "$direct_output"

        touch "$out"
      '';
}
