# Claude Code permission set: the shared allow/ask lists rendered by the common
# formatter, plus the deny overlay that keeps redundant hosted-connector and
# unused built-in tool schemas out of every session.
#
# Extracted from claude-config.nix to keep that file under the org file-size
# cap, the same reason ./mcp-render.nix, ./marketplaces.nix and ./automode.nix
# live beside it.
{ formatters, permissions }:
{
  allow = formatters.claude.formatAllowed permissions;

  # A denied tool's schema is not loaded, so `deny` is the only lever that
  # reaches the claude.ai hosted connectors: they are `claude.ai config` scope,
  # and `claude mcp remove` accepts only local, user and project scopes.
  #
  # Measured in one window against a 114,072 control in this repo:
  #
  #   deny all 11 hosted connectors        88,564   -25,508
  #   deny Hugging Face + Context7        108,675    -5,397
  #   deny the 8 unauthenticated stubs    114,078         0
  #
  # Only these two are denied, because only these two are REDUNDANT: a local
  # `huggingface` MCP server and a Context7 plugin (209 recorded calls, against
  # 14 through the hosted copy) already provide them. Nothing becomes
  # unreachable.
  #
  # The 8 unauthenticated stubs cost exactly nothing and are left alone —
  # denying them would be churn with no measured benefit.
  #
  # The same mechanism applies to built-in tools, and their schemas are not
  # small. Counted by tool-call pattern across 1,651 local transcripts (a naive
  # name grep overcounts by ~100x, because every session's own schema dump
  # contains every tool name), LSP and NotebookEdit had 0 invocations each.
  #
  # DesignSync, ReadMcpResourceDirTool, ReadMcpResourceTool and
  # ListMcpResourcesTool are not in the settings schema's permissionRule
  # enum (json.schemastore.org/claude-code-settings.json) and are not denied
  # here — a denied entry outside the enum fails schema validation.
  #
  # Workflow (5) and ReportFindings (4) would add a further 2,800 and are
  # deliberately NOT denied: they have been used, so removing them trades
  # capability for tokens rather than scoping. Artifact and TaskOutput are
  # already deferred through ToolSearch and denying them is worth only ~550
  # between them. EndConversation stays for the same reason it exists.
  deny = formatters.claude.formatDenied permissions ++ [
    "mcp__claude_ai_Hugging_Face__*"
    "mcp__claude_ai_Context7__*"
    "LSP"
    "NotebookEdit"
  ];

  ask = formatters.claude.formatAsk permissions;
}
