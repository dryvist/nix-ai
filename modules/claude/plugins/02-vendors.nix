# Tier 2 — First-party AI/cloud vendor plugins and MCP integrations (preferred over Tiers 3–5).
# Tier 2 — First-party AI/cloud vendor plugins and MCP integrations
#
# Duplicate Resolution Rule:
#   Plugins in this file are PREFERRED over Tiers 3, 4, 5.
#   Plugins in this file are SUPERSEDED by Tier 1 only when an Anthropic-authored
#   equivalent exists.
#
# Marketplaces in this tier:
#   - openai-codex (openai/codex-plugin-cc, 17071★)
#       Official OpenAI Codex plugin. Supersedes the community variant
#       codex@cc-dev-tools in 05-specialty.nix.
#   - claude-plugins-official/external_plugins/* (parent repo 18410★)
#       Curated MCP integrations to first-party services hosted in the
#       claude-plugins-official marketplace, distinct from the
#       Anthropic-authored core plugins (which live in 01-official.nix).

_:

{
  enabledPlugins = {
    # ========================================================================
    # openai-codex — Official OpenAI Codex plugin
    # ========================================================================

    # Codex (Official): code review, adversarial review, task delegation, rescue
    "codex@openai-codex" = true;

    # ========================================================================
    # claude-plugins-official/external_plugins — First-party MCP integrations
    # ========================================================================
    # Most are disabled by default — enable per-repo when authentication is set
    # up and the integration is actively used.

    # Project Management
    "asana@claude-plugins-official" = false; # Requires Asana API token
    "linear@claude-plugins-official" = false; # Requires Linear API key

    # Version Control & Code
    "github@claude-plugins-official" = true; # Requires GITHUB_PERSONAL_ACCESS_TOKEN; gh CLI is the primary path though
    "gitlab@claude-plugins-official" = false; # Requires GitLab API token
    "greptile@claude-plugins-official" = false; # Removed 2026-03-20: not worth cost

    # Documentation & Context
    "context7@claude-plugins-official" = true; # CONTEXT7_API_KEY optional

    # Backend & Infrastructure
    "firebase@claude-plugins-official" = false;
    "supabase@claude-plugins-official" = false;
    "stripe@claude-plugins-official" = false;

    # Testing & Automation
    # Playwright (Tier 2 keeper) — supersedes playwright@claude-skills (Tier 4)
    # which is disabled in 04-community.nix.
    "playwright@claude-plugins-official" = true;

    # Frameworks
    "laravel-boost@claude-plugins-official" = false;

    # Communication
    # DISABLED — redundant with the claude_ai_Slack MCP server, which
    # exposes 28 tools covering search, read, send, reactions, canvas,
    # scheduling, etc. The slash-command skills bundled here are
    # wrappers around the same Slack API and are reachable via natural
    # language against the MCP server. Drop them to remove 5 skill
    # registrations + the plugin_slack_slack auth tools from every
    # session.
    "slack@claude-plugins-official" = false; # MCP covers the surface

    # Other
    "serena@claude-plugins-official" = false; # Requires Serena API key
  };
}
