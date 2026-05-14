# Tier 1 — Anthropic-published marketplaces (highest precedence in duplicate resolution).
# Tier 1 — Anthropic Official
#
# Duplicate Resolution Rule:
#   Plugins in this file are PREFERRED over ALL other tiers (2, 3, 4, 5).
#   Nothing supersedes Tier 1.
#
# When a role (e.g., code-reviewer, playwright) ships from both Tier 1 and a
# lower tier, KEEP the Tier 1 variant and disable the lower-tier duplicate
# in its respective NN-descriptor.nix file.
#
# Marketplaces in this tier:
#   - claude-plugins-official (anthropics/claude-plugins-official, 18410★)
#       Anthropic-authored core plugins. First-party MCP integrations
#       (GitHub, Slack, Stripe, etc.) ALSO live in this marketplace upstream
#       but are kept in 02-vendors.nix because their priority logic is
#       "first-party AI/cloud vendor", not "Anthropic-authored plugin".
#   - anthropic-agent-skills (anthropics/skills, 127235★)
#       Anthropic-curated skill bundles (xlsx, docx, pptx, pdf).

_:

{
  enabledPlugins = {
    # ========================================================================
    # claude-plugins-official — Anthropic-authored core plugins
    # ========================================================================

    # Git Workflow (essential)
    "commit-commands@claude-plugins-official" = true;

    # Code Review (essential) — Tier 1 keepers; supersedes Tier 4 duplicates
    # in 04-community.nix (codebase-cleanup, tdd-workflows, code-refactoring all ship
    # a code-reviewer agent that we disable there).
    "code-review@claude-plugins-official" = true;
    "pr-review-toolkit@claude-plugins-official" = true;

    # Feature Development — provides feature-dev:code-reviewer (high-confidence
    # filter variant, complementary to pr-review-toolkit:code-reviewer).
    "feature-dev@claude-plugins-official" = true;

    # Security guidance (useful for infra work)
    "security-guidance@claude-plugins-official" = true;

    # Plugin Development (user maintains claude-code-plugins repo)
    "plugin-dev@claude-plugins-official" = true;
    "hookify@claude-plugins-official" = true;

    # Setup & Management
    "claude-code-setup@claude-plugins-official" = true;
    "claude-md-management@claude-plugins-official" = true;

    # Language Servers & Developer Tools
    "pyright-lsp@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = false; # Minimal TS usage

    # Explicit denies — marketplace auto-installs, we lock them off.
    # ralph-loop: 0 invocations in 3 months of session history.
    "ralph-loop@claude-plugins-official" = false;

    # ========================================================================
    # anthropic-agent-skills — Anthropic-curated skill bundles
    # ========================================================================

    # Document Skills (xlsx, docx, pptx, pdf) — universally useful
    "document-skills@anthropic-agent-skills" = true;
  };
}
