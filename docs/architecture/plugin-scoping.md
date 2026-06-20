# Plugin Scoping — User-Level vs Per-Repo

How Claude Code plugins are partitioned between **user-level** (every session) and
**per-repo** (only sessions inside a specific worktree).

## The problem

Claude Code allocates a **skill listing budget** — by default, 1% of the context window
for skill descriptions. With many globally-enabled plugins generating hundreds of skills,
descriptions overflow the budget and Claude Code silently drops most of them. `/doctor`
reports them under "skill descriptions dropped".

When descriptions are dropped, semantic skill discovery degrades — Claude can no longer
match user requests to dropped skills because it cannot see what those skills do.

## The two-layer model

```text
~/.claude/settings.json                   ← user-level (Nix-managed)
  enabledPlugins:                            Universal-only: code-review, commit-commands,
    "code-review@…": true                    document-skills, python-development, etc.
    "ansible-workflows@…": false
    "terraform-module-builder@…": false

  +
~/git/<repo>/main/.claude/settings.json   ← per-repo (committed, deep-merged on session start)
  enabledPlugins:                            Project-specific overrides: ansible, terraform,
    "ansible-workflows@…": true              proxmox, cribl-pack-validator, etc.
    "proxmox-infrastructure@…": true
```

Claude Code deep-merges project-scoped settings on top of user settings on session start.
A plugin disabled at user level can be re-enabled per-repo without touching global config.

## Universal plugins (stay at user level)

Tier 1–4 plugins in `modules/claude/plugins/` are universal or cross-cutting:
code review, commits, PRs, document skills, Python/backend development helpers, etc.
These apply to every session regardless of repo and stay enabled in
`~/.claude/settings.json`.

## Project-specific plugins (per-repo enable)

Tier 5 plugins (`modules/claude/plugins/05-specialty.nix`) are disabled at user level
and re-enabled per-repo. Mapping:

| Repo | Plugins to enable in `<repo>/.claude/settings.json` |
| --- | --- |
| `terraform-proxmox` | `terraform-module-builder@claude-code-plugins-plus`, `infrastructure-as-code-generator@claude-code-plugins-plus`, `proxmox-infrastructure@lunar-claude` |
| `terraform-aws`, `terraform-aws-bedrock`, `terraform-aws-static-website`, `terraform-runs-on`, `tf-splunk-aws` | `terraform-module-builder@claude-code-plugins-plus`, `infrastructure-as-code-generator@claude-code-plugins-plus` |
| `ansible-proxmox`, `ansible-proxmox-apps` | `ansible-workflows@lunar-claude`, `proxmox-infrastructure@lunar-claude` |
| `ansible-splunk` | `ansible-workflows@lunar-claude` |
| `cribl`, `cc-edge-*`, `cc-stream-*` | `cribl-pack-validator@vct-cribl-pack-validator-skills` |
| Obsidian-vault repos | `obsidian@obsidian-skills`, `obsidian-visual-skills@axton-obsidian-visual-skills`, `visual-explainer@visual-explainer-marketplace` |
| Browser-automation repos | `browser-use@browser-use-skills` |

Add to a repo:

```json
{
  "enabledPlugins": {
    "terraform-module-builder@claude-code-plugins-plus": true,
    "infrastructure-as-code-generator@claude-code-plugins-plus": true
  }
}
```

Commit to `.claude/settings.json` (not `.claude/settings.local.json` — the `.local` variant
is gitignored and won't propagate to teammates or worktrees).

## Skill packs (one-command import)

Hand-listing plugins per repo is error-prone and duplicates the grouping everywhere it is
used. **Packs** name a reusable bundle once and let a repo import the whole set:

```bash
cd ~/git/<repo>/<worktree>
ai-pack terraform     # merges the pack's enabledPlugins into ./.claude/settings.json
git add .claude/settings.json && git commit -m "chore: enable terraform skill pack"
ai-pack --list        # show all packs
```

Packs are defined once in [`modules/claude/plugins/packs.nix`](../../modules/claude/plugins/packs.nix)
(also exported as `nix-ai.lib.skillPacks`) and rendered by Nix to `~/.config/ai-packs/<name>.json`.
`ai-pack <name>` deep-merges the chosen pack into the repo's committed `.claude/settings.json`.

| Pack | Plugins | Typical repos |
| --- | --- | --- |
| `terraform` | terraform-module-builder, infrastructure-as-code-generator | `terraform-*`, `tf-*` |
| `proxmox` | `terraform` + proxmox-infrastructure | `terraform-proxmox`, `ansible-proxmox*` |
| `ansible` | ansible-workflows | `ansible-*` |
| `cribl` | cribl-pack-validator | `cribl`, `cc-edge-*`, `cc-stream-*` |
| `obsidian` | obsidian, obsidian-visual-skills, visual-explainer | Obsidian-vault repos |
| `browser` | browser-use | Browser-automation repos |
| `api` | api-design-principles, rest-api-design, better-auth, backend-development | API/backend repos |
| `mcp-dev` | mcp-server-dev, agent-sdk-dev | Repos building MCP servers / SDK apps |
| `modernization` | code-modernization | Legacy-uplift repos |
| `devtools` | analyze-issue, devops-automator | Ad-hoc, when needed |

The last four packs hold plugins that were globally enabled until they showed **zero real use
across all Splunk session history** — now globally disabled (Tier 1/4) and imported per-repo.
A pack only re-enables a plugin *inside* the importing repo; the plugin stays installed at user
level, so the per-repo override works without a rebuild.

## Budget headroom

The `skillListingBudgetFraction` option (schema and default provided by the
`nix-claude-code` flake input) controls how much of the context window Claude
Code reserves for skill descriptions. Raising it above the upstream default gives
headroom for the universal plugin set without dropping descriptions even if a few
project plugins are also enabled per-repo.

If `/doctor` ever reports drops again:

1. Check whether new universal-tier plugins were added (Tier 1–4) — prefer pruning over
   raising the budget.
2. If pruning is not viable, set a higher `skillListingBudgetFraction` in
   `modules/claude-config.nix`.

## Verification

After changing user-level config in nix-ai:

1. `nix flake check` — option regression test verifies the budget setting is present.
2. `darwin-rebuild switch` to deploy.
3. Fresh Claude Code session in `~/git/nix-ai/main`:
   - `/doctor` → no "skill descriptions dropped" line.
   - `/context` → Skills line within the configured budget fraction.

After adding per-repo `.claude/settings.json` in a consumer repo:

1. Fresh session inside the repo worktree.
2. `/skills` → confirm the per-repo plugins are listed.
3. `/skills` in an unrelated repo → confirm those plugins are *not* listed.

## Related

- `modules/claude/plugins/05-specialty.nix` — globally disabled project-specific plugins
- `modules/claude-config.nix` — Claude config wiring (`skillListingBudgetFraction`, plugin enables)
- `.claude/rules/plugin-cache-architecture.md` — read/write boundaries for plugin cache
