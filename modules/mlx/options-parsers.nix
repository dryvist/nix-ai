#
# MLX Module — Tool and reasoning parser options
#
# Server-side tool calling returns structured tool_calls in OpenAI API responses.
# Without these flags, streaming tool calls are broken (raw XML leaks as text)
# and non-streaming relies on a fragile generic parser.
#
{ lib, ... }:
{
  options.programs.mlx = {
    # enableAutoToolChoice — Activate model-specific tool call parsing (--enable-auto-tool-choice).
    # No-op when request has no `tools` parameter, so safe to leave on.
    # Default: true — primary use case is tool calling via MCP.
    enableAutoToolChoice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic tool choice for supported models. No-op when request has no tools.";
    };

    # toolCallParser — Tool call parser (--tool-call-parser).
    # Default: "hermes" — handles Nemotron XML format (<tool_call><function=...>)
    # that Qwen3.5 produces, and supports native tool format for multi-turn
    # conversations. Override to "auto", "qwen3_coder", etc. if needed.
    # Set to null on hosts that pin parsers per model via modelExtraArgs
    # (a global parser and a per-model one would emit the flag twice).
    # Enum matches the vllm-mlx 0.4.0 roster.
    toolCallParser = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "auto"
          "mistral"
          "qwen"
          "qwen3_coder"
          "llama"
          "hermes"
          "harmony"
          "gpt-oss"
          "deepseek"
          "kimi"
          "granite"
          "nemotron"
          "xlam"
          "functionary"
          "gemma4"
          "glm47"
          "minimax"
        ]
      );
      default = "hermes";
      description = "Tool call parser. Only used with enableAutoToolChoice. 'hermes' handles Nemotron XML (<tool_call><function=...>) and supports native tool format for multi-turn conversations.";
    };

    # reasoningParser — Reasoning content extraction (--reasoning-parser).
    # Extracts <think>...</think> into structured reasoning_content field.
    # DISABLED PENDING VERIFICATION: vllm-mlx 0.2.6 had a bug where
    # --reasoning-parser and --tool-call-parser were mutually exclusive in
    # streaming mode (server.py bypassed the tool parser when reasoning parser
    # was active). 0.2.9 may have fixed this — re-enable cautiously after
    # verifying that streaming tool_calls still work for Qwen3-class models.
    # Without this flag, <think> blocks still appear in content text — most
    # consumers parse them from text as a fallback.
    reasoningParser = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "qwen3"
          "deepseek_r1"
          "gpt_oss"
          "harmony"
          "gemma4"
          "glm4"
          "mistral"
        ]
      );
      default = null;
      description = "Reasoning content extraction parser. Disabled by default — conflicts with tool-call-parser in streaming mode (vllm-mlx bug).";
    };

    # modelExtraArgs — extra vllm-mlx serve args for REGISTRY models, keyed by
    # physical model id. The role registry (services.aiStack.models) builds one
    # backend per unique physical model with uniform global flags; this is the
    # per-backend escape hatch for flags that genuinely differ per model —
    # e.g. a host serving gpt-oss (--tool-call-parser harmony) alongside a
    # Qwen coder (--tool-call-parser qwen3_coder) sets the global
    # toolCallParser to null and pins one parser per physical id here.
    # (cfg.models.*.extraArgs already covers ad-hoc non-registry models.)
    modelExtraArgs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = lib.literalExpression ''
        {
          "mlx-community/<large-model>" = [
            "--tool-call-parser"
            "harmony"
          ];
        }
      '';
      description = "Additional vllm-mlx serve arguments per physical registry model id, appended after the global flags.";
    };
  };
}
