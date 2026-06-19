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
#       Anthropic-curated skill bundles. The marketplace exposes three
#       plugins (document-skills, example-skills, claude-api) whose
#       manifests declare partitioned `skills` arrays — but each plugin
#       checks out the FULL anthropics/skills repo, so every plugin
#       loads the SAME 17 skills (algorithmic-art, brand-guidelines,
#       canvas-design, claude-api, doc-coauthoring, docx, frontend-design,
#       internal-comms, mcp-builder, pdf, pptx, skill-creator,
#       slack-gif-creator, theme-factory, web-artifacts-builder,
#       webapp-testing, xlsx). Enabling more than one = duplicate
#       registrations for zero added coverage. Verified 2026-05-27 on
#       disk against the cache checkouts. Keep ONE; disable the rest.

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

    # Frontend Design — standalone single-skill plugin. The bundled
    # variant inside anthropic-agent-skills now ships under the kept
    # document-skills plugin only (example-skills disabled below). This
    # standalone is retained because its description text differs from
    # the bundled variant; loaders that match on description benefit
    # from both being present.
    "frontend-design@claude-plugins-official" = true;

    # Code transformation skills — refactoring + simplification for docs
    # work and general code maintenance.
    # code-modernization: DISABLED (legacy/mainframe uplift; 0 real use per
    # Splunk). Import per-repo via packs.nix `modernization` when needed.
    "code-modernization@claude-plugins-official" = false;
    "code-simplifier@claude-plugins-official" = true;

    # Dev kits — Agent SDK + MCP server scaffolding. DISABLED (0 real use per
    # Splunk). Import per-repo via packs.nix `mcp-dev` when building MCP/SDK apps.
    "agent-sdk-dev@claude-plugins-official" = false;
    "mcp-server-dev@claude-plugins-official" = false;

    # Language Servers & Developer Tools
    "pyright-lsp@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = false; # Minimal TS usage

    # Explicit denies — marketplace auto-installs, we lock them off.
    # ralph-loop: 0 invocations in 3 months of session history.
    "ralph-loop@claude-plugins-official" = false;

    # ========================================================================
    # anthropic-agent-skills — Anthropic-curated skill bundles
    #
    # All three plugins in this marketplace check out the entire
    # anthropics/skills repo and expose the SAME 17 skills, ignoring
    # the manifest's per-plugin skill array. See the marketplace
    # comment above for the full list and verification details.
    # Enabling more than one yields duplicate registrations for zero
    # added coverage. Keep ONE; disable the rest.
    #
    # Keeper: document-skills (most generic name, clearest mental
    # model for the bundle). Re-evaluate if upstream ever honors the
    # manifest split.
    # ========================================================================

    "document-skills@anthropic-agent-skills" = true;

    # DISABLED — duplicates document-skills (identical 17 skills on
    # disk). The skill set previously credited to this plugin is now
    # served via document-skills:* namespace.
    "example-skills@anthropic-agent-skills" = false;

    # DISABLED — duplicates document-skills. The claude-api skill is
    # still reachable via document-skills:claude-api.
    "claude-api@anthropic-agent-skills" = false;
  };
}
