# Codex Module Options
#
# Declarative options for OpenAI Codex CLI configuration.
# Follows the same per-agent option patterns as the other agent modules
# (see docs/architecture/per-agent-flakes.md).
{ lib, ... }:

let
  mcpClient = import ../mcp/client.nix { inherit lib; };
  nullableStr = lib.types.nullOr lib.types.str;
  nullableReasoningEffort = lib.types.nullOr (
    lib.types.enum [
      "minimal"
      "low"
      "medium"
      "high"
      "xhigh"
    ]
  );
  nullableVerbosity = lib.types.nullOr (
    lib.types.enum [
      "low"
      "medium"
      "high"
    ]
  );
in
{
  options.programs.codex = {
    # Hooks
    # Feature flags (maps to [features] table in config.toml)
    features = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = { };
      description = "Codex feature flags (maps to [features] in config.toml)";
    };

    model = lib.mkOption {
      type = nullableStr;
      default = null;
      description = "Default Codex model.";
    };

    modelProvider = lib.mkOption {
      type = nullableStr;
      default = null;
      description = "Default model provider identifier.";
    };

    modelReasoningEffort = lib.mkOption {
      type = nullableReasoningEffort;
      default = "medium";
      description = "Default reasoning effort for Codex.";
    };

    modelVerbosity = lib.mkOption {
      type = nullableVerbosity;
      default = "medium";
      description = "Default model verbosity.";
    };

    planModeReasoningEffort = lib.mkOption {
      type = nullableReasoningEffort;
      default = "high";
      description = "Default reasoning effort for plan mode.";
    };

    reviewModel = lib.mkOption {
      type = nullableStr;
      default = null;
      description = "Model to use for Codex review flows.";
    };

    serviceTier = lib.mkOption {
      type = nullableStr;
      default = null;
      description = "Default Codex service tier.";
    };

    webSearch = lib.mkOption {
      type = nullableStr;
      default = null;
      description = "Codex web search mode.";
    };

    # Trusted project directories
    trustedProjectDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional directories to trust (merged with shared permission dirs)";
    };

    projectDocFallbackFilenames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      internal = true;
      description = "Project doc fallback filenames emitted to Codex config.toml; read-only.";
    };

    # Approval policy
    approvalPolicy = lib.mkOption {
      type = lib.types.enum [
        "untrusted"
        "on-failure"
        "on-request"
        "never"
      ];
      default = "never";
      description = ''
        Default approval policy for Codex sessions.

        `never` by design: an approval prompt stalls any unattended run
        (cron, CI, container) on a question nobody is there to answer.
        Safety comes from `sandbox_mode = "workspace-write"` plus the
        execpolicy `forbidden` rules rendered from the shared deny list —
        both of which hold without a human present. This mirrors the
        empty ASK tier in the shared permission data.
      '';
    };

    # excludedMcpServers + mcpServerNames come from the shared MCP client helper.
  }
  // mcpClient.mkClientOptions "Codex";
}
