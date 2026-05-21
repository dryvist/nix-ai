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
#       Anthropic-curated skill bundles: document-skills (xlsx/docx/pptx/pdf),
#       example-skills (frontend-design, theme-factory, brand-guidelines,
#       web-artifacts-builder, canvas-design, webapp-testing, mcp-builder,
#       skill-creator, doc-coauthoring, algorithmic-art, slack-gif-creator,
#       internal-comms), and claude-api (Anthropic SDK reference).

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

    # Frontend Design — standalone single-skill plugin. The bundled variant
    # ships in example-skills@anthropic-agent-skills below; description text
    # differs slightly between sources, both kept per explicit request.
    "frontend-design@claude-plugins-official" = true;

    # Code transformation skills — refactoring + simplification for docs
    # work and general code maintenance.
    "code-modernization@claude-plugins-official" = true;
    "code-simplifier@claude-plugins-official" = true;

    # Dev kits — Agent SDK + MCP server scaffolding. Useful for docs sites
    # that document or embed Claude/MCP integrations.
    "agent-sdk-dev@claude-plugins-official" = true;
    "mcp-server-dev@claude-plugins-official" = true;

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

    # Example Skills bundle — front-end / design / web-authoring skills:
    # frontend-design, brand-guidelines, theme-factory, web-artifacts-builder,
    # canvas-design, webapp-testing, mcp-builder, skill-creator,
    # doc-coauthoring, algorithmic-art, slack-gif-creator, internal-comms.
    # The last three (slack-gif-creator, algorithmic-art, internal-comms)
    # will be quieted via skillOverrides once the ai-assistant-instructions
    # input is bumped — keeps context lean in sessions unrelated to design
    # work. skillOverrides targets bare skill names, so the bundled
    # frontend-design above and the standalone frontend-design plugin
    # both stay visible.
    "example-skills@anthropic-agent-skills" = true;

    # Claude API / SDK reference — useful for docs repos that document Claude
    # integrations and for tuning prompt caching / model selection.
    "claude-api@anthropic-agent-skills" = true;
  };
}
