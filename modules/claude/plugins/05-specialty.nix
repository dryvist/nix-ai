# Tier 5 — Niche, specialty, and synthetic marketplaces (superseded by all higher tiers).
#
# Duplicate Resolution Rule:
#   Plugins in this file are SUPERSEDED by ALL higher tiers (1, 2, 3, 4).
#
# Per-repo overrides:
#   Disabled globally but can be re-enabled in consumer repos via
#   `.claude/settings.json`. See docs/architecture/plugin-scoping.md.
#
# Marketplaces in this tier (sorted by relevance to user's stack, not stars —
# stars are unreliable for niche-classification because some upstreams like
# browser-use and fabric are very popular but the wrapped-skill marketplaces
# are specialty-use only):
#   - lunar-claude (basher83/lunar-claude, 18★)             — Proxmox + Ansible
#   - claude-code-plugins-plus (jeremylongshore/..., 2083★) — Terraform / IaC
#   - bitwarden-marketplace (bitwarden/ai-plugins, 90★)     — session analysis
#   - cc-dev-tools (Lucklyric/cc-dev-tools, 29★)            — community Codex/Gemini wrappers
#   - fabric-patterns (danielmiessler/fabric, 41428★ upstream, synthetic)
#   - huggingface-skills (huggingface/skills, 10371★)       — HF Hub ops
#   - obsidian-skills (kepano/obsidian-skills, 28277★)
#   - axton-obsidian-visual-skills (axtonliu/..., 2651★)
#   - visual-explainer-marketplace (nicobailon/..., 7816★)
#   - browser-use-skills (browser-use/browser-use, 91681★ upstream, synthetic)
#   - vct-cribl-pack-validator-skills (VisiCore/..., 0★, synthetic)
#   - wakatime (wakatime/claude-code-wakatime, 73★)         — telemetry

_:

{
  enabledPlugins = {
    # ========================================================================
    # lunar-claude — basher83/lunar-claude (Proxmox + Ansible)
    # ========================================================================
    "proxmox-infrastructure@lunar-claude" = false;
    "ansible-workflows@lunar-claude" = false;

    # ========================================================================
    # claude-code-plugins-plus — jeremylongshore/claude-code-plugins-plus
    # ========================================================================
    "infrastructure-as-code-generator@claude-code-plugins-plus" = false;
    "terraform-module-builder@claude-code-plugins-plus" = false;

    # ========================================================================
    # bitwarden-marketplace — bitwarden/ai-plugins
    # ========================================================================
    # Two plugins kept: claude-retrospective (3 skills), claude-config-validator
    # (1 skill).
    "claude-retrospective@bitwarden-marketplace" = true;
    "claude-config-validator@bitwarden-marketplace" = true;
    # NOT enabled — Bitwarden-specific:
    # bitwarden-code-review, bitwarden-software-engineer,
    # bitwarden-security-engineer, bitwarden-product-analyst, bitwarden-init,
    # atlassian-reader, bitwarden-atlassian-tools.

    # ========================================================================
    # cc-dev-tools — Lucklyric/cc-dev-tools (community AI vendor wrappers)
    # ========================================================================
    # WARNING: These plugins invoke external AI models (OpenAI, Google).

    # DISABLED — superseded by Tier 2 codex@openai-codex (official OpenAI plugin).
    "codex@cc-dev-tools" = false;

    # KEEP — no Google-official Claude plugin exists for Gemini delegation.
    "gemini@cc-dev-tools" = true;

    # Already disabled — requires TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID env vars
    # which aren't configured.
    "telegram-notifier@cc-dev-tools" = false;

    # ========================================================================
    # fabric-patterns — danielmiessler/fabric (synthetic, curated subset)
    # ========================================================================
    # DISABLED — 50+ tiny analyze_*/extract_*/write_* skills bloat the eager
    # skill index for marginal value. Use the Fabric MCP server instead, which
    # is already loaded on-demand:
    #   mcp__fabric__fabric_list_patterns
    #   mcp__fabric__fabric_run_pattern
    "fabric-patterns@fabric-patterns" = false;

    # ========================================================================
    # huggingface-skills — huggingface/skills
    # ========================================================================
    # Kept for hf CLI Hub operations (download/upload models, manage repos) —
    # user actively does HF model ops in nix-ai (MLX work).
    "hf-cli@huggingface-skills" = true;

    # ========================================================================
    # obsidian-skills + axton-obsidian-visual-skills + visual-explainer
    # ========================================================================
    # axton-obsidian-visual-skills enabled per user request — makes the
    # mermaid/excalidraw/canvas skills available in Claude. The repo uses a
    # non-standard `<root>/<skill>/SKILL.md` layout that the current
    # `modules/agent-skills/default.nix` discovery doesn't yet match, so
    # Codex/Gemini won't pick them up until that module is extended (tracked
    # separately). obsidian@obsidian-skills stays disabled globally; re-enable
    # in Obsidian-vault repos via per-repo .claude/settings.json.
    "obsidian@obsidian-skills" = false;
    "obsidian-visual-skills@axton-obsidian-visual-skills" = true;
    "visual-explainer@visual-explainer-marketplace" = false;

    # ========================================================================
    # browser-use-skills — browser-use/browser-use (synthetic)
    # ========================================================================
    # DISABLED globally — re-enable per-repo for browser automation work.
    # General browser testing is also covered by Tier 2 playwright@claude-plugins-official.
    "browser-use@browser-use-skills" = false;

    # ========================================================================
    # vct-cribl-pack-validator-skills — VisiCore/vct-cribl-pack-validator (synthetic)
    # ========================================================================
    # DISABLED globally — re-enable in Cribl pack repos (cribl, cc-edge-*,
    # cc-stream-*) via per-repo .claude/settings.json overrides.
    "cribl-pack-validator@vct-cribl-pack-validator-skills" = false;

    # ========================================================================
    # wakatime — wakatime/claude-code-wakatime (time tracking)
    # ========================================================================
    # Marketplace key is `wakatime` (org name), not `claude-code-wakatime`.
    # Plugin reference: claude-code-wakatime@wakatime.
    "claude-code-wakatime@wakatime" = true;
  };
}
