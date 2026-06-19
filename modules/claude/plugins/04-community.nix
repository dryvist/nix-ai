# Tier 4 — Community marketplaces ordered by GitHub stars (preferred over specialty tier only).
# Tier 4 — Community by GitHub-stars popularity
#
# Duplicate Resolution Rule:
#   Plugins in this file are PREFERRED over Tier 5 only.
#   Plugins in this file are SUPERSEDED by Tiers 1, 2, 3.
#   Within Tier 4, prefer the marketplace with higher GitHub stars.
#
# Marketplaces in this tier (sorted by popularity, verified 2026-05-02):
#   - claude-code-workflows (wshobson/agents, 34640★)        — most popular community
#   - superpowers-marketplace (obra/superpowers-marketplace, 925★)
#   - cc-marketplace (ananddtyagi/cc-marketplace, 679★)
#   - claude-skills (secondsky/claude-skills, 129★)         — single-skill specialty plugins

_:

{
  enabledPlugins = {
    # ========================================================================
    # claude-code-workflows — wshobson/agents (34640★)
    # ========================================================================
    # When two Tier 4 marketplaces ship the same role we generally prefer this
    # one (highest stars). Per-plugin notes annotate which agents are duplicates
    # of higher-tier variants and where the keeper lives.

    # Backend / Frameworks (kept — many unique agents)
    # Agents: backend-architect, event-sourcing-architect, graphql-architect,
    #         performance-engineer (DUP — keeper observability-monitoring),
    #         security-auditor (DUP — full-stack-orchestration disabled below;
    #                           remaining variant is here, plus Tier 1
    #                           code-review covers most security review needs),
    #         tdd-orchestrator (KEEPER for this role at Tier 4),
    #         temporal-python-pro, test-automator (DUP — keeper unit-testing).
    # DISABLED (0 real use per Splunk) — import per-repo via packs.nix `api`.
    "backend-development@claude-code-workflows" = false;

    # Agents: django-pro, fastapi-pro, python-pro (all unique).
    "python-development@claude-code-workflows" = true;

    # Agents: monorepo-architect (unique).
    "developer-essentials@claude-code-workflows" = true;

    # Testing (selective)
    # Agents: debugger (unique), test-automator (KEEPER for this role).
    # Best-judgement keeper among 5 community test-automator dups: this one
    # has the most direct name match for general unit-testing work.
    "unit-testing@claude-code-workflows" = true;

    # DISABLED — code-reviewer (DUP, superseded by Tier 1 pr-review-toolkit:code-reviewer)
    #            tdd-orchestrator (DUP — keeper backend-development:tdd-orchestrator).
    "tdd-workflows@claude-code-workflows" = false;

    # DISABLED — code-reviewer (DUP, superseded by Tier 1 pr-review-toolkit:code-reviewer)
    #            legacy-modernizer (rarely used).
    "code-refactoring@claude-code-workflows" = false;

    # DISABLED — code-reviewer + test-automator both DUP. Loses deps-audit/
    # tech-debt/refactor-clean skills, which is acceptable for token savings.
    "codebase-cleanup@claude-code-workflows" = false;

    # DISABLED — ALL agents are duplicates: deployment-engineer (keeper
    # cicd-automation), performance-engineer (keeper observability-monitoring),
    # security-auditor (DUP), test-automator (keeper unit-testing).
    "full-stack-orchestration@claude-code-workflows" = false;

    # DISABLED — performance-engineer + test-automator both DUP.
    "performance-testing-review@claude-code-workflows" = false;

    # Orchestration & Observability (kept — unique agents)
    # Agents: context-manager (unique).
    "agent-orchestration@claude-code-workflows" = true;

    # Agents: database-optimizer (unique), network-engineer (unique),
    #         observability-engineer (unique), performance-engineer (KEEPER
    #         for this role across 4 community variants — best domain fit).
    "observability-monitoring@claude-code-workflows" = true;

    # Cloud / DevOps
    # Agents: cloud-architect (unique), deployment-engineer (KEEPER — keeper
    #         for this role; full-stack-orchestration variant disabled above),
    #         devops-troubleshooter, kubernetes-architect, terraform-specialist
    #         (all unique).
    "cicd-automation@claude-code-workflows" = true;

    # ========================================================================
    # superpowers-marketplace — obra/superpowers-marketplace (925★)
    # ========================================================================

    # Core enhancement suite — keep the canonical plugin.
    "superpowers@superpowers-marketplace" = true;

    # DISABLED — niche experiments not in active use.
    "superpowers-lab@superpowers-marketplace" = false;

    # DISABLED — plugin-development helpers superseded by Tier 1
    # plugin-dev@claude-plugins-official.
    "superpowers-developing-for-claude-code@superpowers-marketplace" = false;

    # Already disabled — auto-continuation not in use.
    # "double-shot-latte@superpowers-marketplace" = false;

    # ========================================================================
    # cc-marketplace — ananddtyagi/cc-marketplace (679★)
    # ========================================================================
    # Official source for claudecodecommands.directory plugins.

    # Essential issue analysis + worktree creation utilities (unique to this marketplace).
    # analyze-issue: DISABLED (0 real use per Splunk) — packs.nix `devtools`.
    "analyze-issue@cc-marketplace" = false;
    "create-worktrees@cc-marketplace" = true;

    # User actively uses Python — kept for python-expert agent (unique).
    "python-expert@cc-marketplace" = true;

    # CI/CD, cloud infra, monitoring, deployment automation (unique).
    # DISABLED (0 real use per Splunk) — import per-repo via packs.nix `devtools`.
    "devops-automator@cc-marketplace" = false;

    # NOT enabled: double-check (unnecessary), infrastructure-maintainer (too generic),
    # monitoring-observability-specialist (Splunk repos don't need this),
    # awesome-claude-code-plugins (AGGREGATION — use true sources directly).

    # ========================================================================
    # claude-skills — secondsky/claude-skills (129★)
    # ========================================================================
    # Each plugin here is a single specialty skill loaded for every session.
    # Disable plugins that aren't in the user's day-to-day stack — re-enable
    # per-repo via committed .claude/settings.json overrides when relevant.

    # API design — DISABLED (0 real use per Splunk) — packs.nix `api`.
    "api-design-principles@claude-skills" = false;
    "rest-api-design@claude-skills" = false;

    # Authentication — DISABLED (0 real use per Splunk) — packs.nix `api`.
    "better-auth@claude-skills" = false;
    "oauth-implementation@claude-skills" = false; # Superseded by better-auth above.

    # DISABLED — not in user's stack (no JS/web app dev, no GraphQL, no WS,
    # no CSRF/XSS exposure, light DB work):
    "graphql-implementation@claude-skills" = false;
    "websocket-implementation@claude-skills" = false;
    "csrf-protection@claude-skills" = false;
    "xss-prevention@claude-skills" = false;
    "jest-generator@claude-skills" = false;
    "vitest-testing@claude-skills" = false;
    "playwright@claude-skills" = false; # Superseded by Tier 2 playwright@claude-plugins-official.
    "vulnerability-scanning@claude-skills" = false; # CI handles
    "recommendation-engine@claude-skills" = false;
    "sql-query-optimization@claude-skills" = false;
  };
}
