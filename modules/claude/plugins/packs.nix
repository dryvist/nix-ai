# Named project-scoped plugin packs — single source of truth.
#
# A "pack" groups plugins that belong to one domain so a repo can import the
# whole set with one command instead of hand-listing plugins. Packs are NOT
# enabled at user level; a repo that needs one runs `ai-pack <name>` inside its
# worktree, which merges the pack into the committed `.claude/settings.json`.
# Claude Code deep-merges that over user settings on session start.
#
# This file is the canonical definition. `modules/claude/skill-packs.nix`
# renders each pack to `~/.config/ai-packs/<name>.json`, and `nix-ai.lib.skillPacks`
# exposes the same attrset to foreign consumers. See
# docs/architecture/plugin-scoping.md.
#
# Adding a plugin to a pack does NOT enable it globally — keep the global
# enablement decision in the tier files (01..05-*.nix) and the personal tier.
{
  # ---- Packs for plugins disabled globally in this PR (Splunk: 0 real use) ----

  # API / backend design helpers.
  api = {
    "api-design-principles@claude-skills" = true;
    "rest-api-design@claude-skills" = true;
    "better-auth@claude-skills" = true;
    "backend-development@claude-code-workflows" = true;
  };

  # Building MCP servers / Agent SDK apps.
  mcp-dev = {
    "mcp-server-dev@claude-plugins-official" = true;
    "agent-sdk-dev@claude-plugins-official" = true;
  };

  # Legacy / mainframe modernization (COBOL, .NET-Framework uplift, etc.).
  modernization = {
    "code-modernization@claude-plugins-official" = true;
  };

  # Generic dev-ops / issue-analysis tooling.
  devtools = {
    "analyze-issue@cc-marketplace" = true;
    "devops-automator@cc-marketplace" = true;
  };

  # ---- Packs mirroring the existing Tier-5 per-repo mappings (plugin-scoping.md) ----

  # Infrastructure-as-code (Terraform).
  terraform = {
    "terraform-module-builder@claude-code-plugins-plus" = true;
    "infrastructure-as-code-generator@claude-code-plugins-plus" = true;
  };

  # Proxmox homelab = Terraform + Proxmox.
  proxmox = {
    "terraform-module-builder@claude-code-plugins-plus" = true;
    "infrastructure-as-code-generator@claude-code-plugins-plus" = true;
    "proxmox-infrastructure@lunar-claude" = true;
  };

  # Ansible automation.
  ansible = {
    "ansible-workflows@lunar-claude" = true;
  };

  # Cribl pack validation (cc-edge-*, cc-stream-*, cribl).
  cribl = {
    "cribl-pack-validator@vct-cribl-pack-validator-skills" = true;
  };

  # Obsidian vault repos.
  obsidian = {
    "obsidian@obsidian-skills" = true;
    "obsidian-visual-skills@axton-obsidian-visual-skills" = true;
    "visual-explainer@visual-explainer-marketplace" = true;
  };

  # Browser-automation repos.
  browser = {
    "browser-use@browser-use-skills" = true;
  };
}
