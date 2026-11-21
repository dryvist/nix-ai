{
  pkgs,
  lib,
  curl ? pkgs.curl,
  localRouterUrl ? null,
  localRouterToken ? null,
}:
let
  claudeLlmRouterModels = {
    model = "medium";
    opus = "medium";
    sonnet = "medium";
    haiku = "small";
    subagent = "medium";
  };
  claudeOcgRouterModels = {
    model = "go-mimo-flash";
    opus = "go-mimo-flash";
    sonnet = "go-mimo-flash";
    haiku = "go-deepseek-flash";
    subagent = "go-deepseek-flash";
  };
  claudeRouterNames = lib.unique (
    builtins.attrValues claudeLlmRouterModels ++ builtins.attrValues claudeOcgRouterModels
  );
  modelDiscoveryScript = import ./claude-router-discovery.nix;

  mkClaudeRouter =
    {
      name,
      routerKeyEnv ? null,
      routerKeyCommandEnv ? null,
      routerModels,
      routerUrl ? null,
      fixedRouterToken ? null,
      customHeaders ? "",
      discoverModels ? false,
      direct ? null,
      aliases ? [ ],
    }:
    let
      # A fixed-token launcher runs no key lookup, so it carries none of the key variables.
      keyed = fixedRouterToken == null;
      supportsDirect = direct != null;
      directKeyEnv = if supportsDirect then direct.keyEnv else "";
      directKeyCommandEnv = if supportsDirect then direct.keyCommandEnv else "";
      directBaseUrl = if supportsDirect then direct.baseUrl else "";
      directModels =
        if supportsDirect then
          direct.models
        else
          {
            model = "";
            opus = "";
            sonnet = "";
            haiku = "";
            subagent = "";
          };
      clearCredentialEnv = [
        "CLAUDE_LLM_ROUTER_KEY="
        "CLAUDE_LLM_KEY_COMMAND="
        "CLAUDE_OCG_ROUTER_KEY="
        "CLAUDE_OCG_KEY_COMMAND="
        "CLAUDE_HOMELAB_ROUTER_KEY="
        "CLAUDE_HOMELAB_KEY_COMMAND="
        "OPENCODE_GO_API_KEY="
        "OCG_DIRECT_KEY_COMMAND="
      ]
      ++ lib.optionals supportsDirect [
        "${directKeyEnv}="
        "${directKeyCommandEnv}="
      ];
      launcher = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = lib.optionals discoverModels [
          curl
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          ${lib.optionalString keyed ''
            router_key_env=${lib.escapeShellArg routerKeyEnv}
            router_key_command_env=${lib.escapeShellArg routerKeyCommandEnv}
            direct_key_env=${lib.escapeShellArg directKeyEnv}
            direct_key_command_env=${lib.escapeShellArg directKeyCommandEnv}
          ''}
          supports_direct=${if supportsDirect then "1" else "0"}
          mode=router
          if [[ "''${NIX_AI_CLAUDE_ROUTER_FETCH_ATTEMPTED:-}" == 1 ]]; then
            mode="''${NIX_AI_CLAUDE_ROUTER_FETCH_MODE:-router}"
          fi
          model_override=
          args=()

          while (($#)); do
            case "$1" in
              --)
                args+=("$@")
                break
                ;;
              --direct)
                if [[ "$supports_direct" == 1 ]]; then
                  mode=direct
                else
                  printf '%s\n' ${lib.escapeShellArg "${name}: --direct is not supported"} >&2
                  exit 2
                fi
                ;;
              --model)
                args+=("$1")
                if (($# > 1)); then
                  shift
                  args+=("$1")
                  model_override=$1
                fi
                ;;
              --model=*)
                args+=("$1")
                model_override="''${1#--model=}"
                ;;
              *)
                args+=("$1")
                ;;
            esac
            shift
          done
          set -- "''${args[@]}"

          if [[ "$mode" == direct ]]; then
            ${lib.optionalString keyed ''
              key_name=$direct_key_env
              command_name=$direct_key_command_env
            ''}
            base_url=${lib.escapeShellArg directBaseUrl}
            model=${lib.escapeShellArg directModels.model}
            opus_model=${lib.escapeShellArg directModels.opus}
            sonnet_model=${lib.escapeShellArg directModels.sonnet}
            haiku_model=${lib.escapeShellArg directModels.haiku}
            subagent_model=${lib.escapeShellArg directModels.subagent}
          else
            ${lib.optionalString keyed ''
              key_name=$router_key_env
              command_name=$router_key_command_env
            ''}
            router_url=${
              if routerUrl != null then lib.escapeShellArg routerUrl else "\${LLM_ROUTER_URL:?set LLM_ROUTER_URL}"
            }
            router_url="''${router_url%/}"
            base_url="''${router_url%/v1}"
            model=${lib.escapeShellArg routerModels.model}
            opus_model=${lib.escapeShellArg routerModels.opus}
            sonnet_model=${lib.escapeShellArg routerModels.sonnet}
            haiku_model=${lib.escapeShellArg routerModels.haiku}
            subagent_model=${lib.escapeShellArg routerModels.subagent}
          fi

          if [[ -n "$model_override" ]]; then
            model=$model_override
          fi

          ${
            if fixedRouterToken != null then
              ''
                key_value=${lib.escapeShellArg fixedRouterToken}
                anthropic_auth_token=
              ''
            else
              ''
                key_value="''${!key_name:-}"
                if [[ -z "$key_value" ]]; then
                  if [[ "''${NIX_AI_CLAUDE_ROUTER_FETCH_ATTEMPTED:-}" == 1 ]]; then
                    printf '%s\n' "${name}: key command did not set $key_name" >&2
                    exit 1
                  fi
                  key_command="''${!command_name:-}"
                  if [[ -z "$key_command" ]]; then
                    printf '%s\n' "${name}: set $key_name, or $command_name to fetch it" >&2
                    exit 1
                  fi
                  read -ra fetch <<<"$key_command"
                  if ((''${#fetch[@]} == 0)); then
                    printf '%s\n' "${name}: $command_name is empty" >&2
                    exit 1
                  fi
                  exec env \
                    NIX_AI_CLAUDE_ROUTER_FETCH_ATTEMPTED=1 \
                    "NIX_AI_CLAUDE_ROUTER_FETCH_MODE=$mode" \
                    "''${fetch[@]}" "$0" "$@"
                fi
                anthropic_auth_token=$key_value
              ''
          }

          ${lib.optionalString discoverModels (modelDiscoveryScript {
            inherit name;
          })}

          ${if discoverModels then "env" else "exec env"} \
            ${lib.concatMapStringsSep " " lib.escapeShellArg clearCredentialEnv} \
            ANTHROPIC_API_KEY= \
            ANTHROPIC_AUTH_TOKEN="$anthropic_auth_token" \
            ANTHROPIC_BASE_URL="$base_url" \
            ANTHROPIC_CUSTOM_HEADERS=${lib.escapeShellArg customHeaders} \
            ANTHROPIC_MODEL="$model" \
            ANTHROPIC_DEFAULT_OPUS_MODEL="$opus_model" \
            ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet_model" \
            ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku_model" \
            CLAUDE_CODE_OAUTH_TOKEN= \
            CLAUDE_CODE_USE_BEDROCK= \
            CLAUDE_CODE_USE_VERTEX= \
            CLAUDE_CODE_USE_FOUNDRY= \
            CLAUDE_CODE_SUBAGENT_MODEL="$subagent_model" \
            CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 \
            ${lib.optionalString discoverModels ''CLAUDE_CODE_MAX_CONTEXT_TOKENS="$context_window"''} \
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
            NIX_AI_CLAUDE_ROUTER_FETCH_ATTEMPTED= \
            NIX_AI_CLAUDE_ROUTER_FETCH_MODE= \
            OPENAI_API_KEY= \
            PATH="$HOME/.local/bin:$PATH" \
            ${if discoverModels then ''claude --settings "$settings_file" "$@"'' else ''claude "$@"''}
        '';
      };
    in
    if aliases == [ ] then
      launcher
    else
      pkgs.runCommand "${name}-aliases" { } ''
        mkdir -p "$out/bin"
        ln -s ${launcher}/bin/${name} "$out/bin/${name}"
        ${lib.concatMapStringsSep "\n" (
          binAlias: "ln -s ${launcher}/bin/${name} \"$out/bin/${binAlias}\""
        ) aliases}
      '';

in
{
  claudeLlm = mkClaudeRouter {
    name = "claude-llm";
    routerKeyEnv = "CLAUDE_LLM_ROUTER_KEY";
    routerKeyCommandEnv = "CLAUDE_LLM_KEY_COMMAND";
    routerModels = claudeLlmRouterModels;
    discoverModels = true;
  };

  claudeHomelab = mkClaudeRouter {
    name = "claude-homelab";
    routerKeyEnv = "CLAUDE_HOMELAB_ROUTER_KEY";
    routerKeyCommandEnv = "CLAUDE_HOMELAB_KEY_COMMAND";
    routerModels = claudeLlmRouterModels;
    discoverModels = true;
  };

  claudeLocal = mkClaudeRouter {
    name = "claude-local";
    routerModels = claudeLlmRouterModels;
    routerUrl =
      if localRouterUrl == null then throw "claude-local requires localRouterUrl" else localRouterUrl;
    fixedRouterToken =
      if localRouterToken == null then
        throw "claude-local requires localRouterToken"
      else
        localRouterToken;
    customHeaders =
      if localRouterToken == null then
        throw "claude-local requires localRouterToken"
      else
        "x-litellm-api-key: Bearer ${localRouterToken}\nx-litellm-tags: claude-local";
    discoverModels = true;
  };

  claudeOcg = mkClaudeRouter {
    name = "claude-ocg";
    routerKeyEnv = "CLAUDE_OCG_ROUTER_KEY";
    routerKeyCommandEnv = "CLAUDE_OCG_KEY_COMMAND";
    routerModels = claudeOcgRouterModels;
    direct = {
      keyEnv = "OPENCODE_GO_API_KEY";
      keyCommandEnv = "OCG_DIRECT_KEY_COMMAND";
      baseUrl = "https://opencode.ai/zen/go";
      models = {
        model = "qwen3.7-plus";
        opus = "qwen3.7-plus";
        sonnet = "qwen3.7-plus";
        haiku = "qwen3.7-plus";
        subagent = "qwen3.7-plus";
      };
    };
    aliases = [ "claude-go" ];
  };

  routerNames = claudeRouterNames;
}
