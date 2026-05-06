# Plugin Scoping — User-Level vs Per-Repo

How Claude Code plugins are partitioned between **user-level** (every session) and
**per-repo** (only sessions inside a specific worktree).

## The problem

Claude Code allocates a **skill listing budget** — by default, 1% of the context window
(~2k tokens of 200k) for skill descriptions. With 45+ globally-enabled plugins generating
~250 skills, descriptions overflow the budget and Claude Code silently drops most of them.
`/doctor` reports lines like `237 skill descriptions dropped`.

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
| `terraform-aws`, `terraform-aws-bedrock`, `terraform-aws-static-website`, `terraform-runs-on` | `terraform-module-builder@claude-code-plugins-plus`, `infrastructure-as-code-generator@claude-code-plugins-plus` |
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

## Budget headroom

`modules/claude/options.nix` sets `skillListingBudgetFraction = 0.03` (3%) — well above
the 1% upstream default. This gives ~6k tokens for skill listings, comfortable headroom
for the universal plugin set without dropping descriptions even if a few project plugins
are also enabled per-repo.

If `/doctor` ever reports drops again:

1. Check whether new universal-tier plugins were added (Tier 1–4) — prefer pruning over
   raising the budget.
2. If pruning is not viable, raise `skillListingBudgetFraction` in
   `modules/claude/options.nix` (each 0.01 ≈ 2k tokens).

## Verification

After changing user-level config in nix-ai:

1. `nix flake check` — option regression test verifies the budget setting is present.
2. `darwin-rebuild switch` to deploy.
3. Fresh Claude Code session in `~/git/nix-ai/main`:
   - `/doctor` → no "skill descriptions dropped" line.
   - `/context` → Skills line ≤ 6k tokens.

After adding per-repo `.claude/settings.json` in a consumer repo:

1. Fresh session inside the repo worktree.
2. `/skills` → confirm the per-repo plugins are listed.
3. `/skills` in an unrelated repo → confirm those plugins are *not* listed.

## Related

- `modules/claude/plugins/05-specialty.nix` — globally disabled project-specific plugins
- `modules/claude/options.nix` — `skillListingBudgetFraction` option
- `modules/claude/settings.nix` — settings.json generator
- `.claude/rules/plugin-cache-architecture.md` — read/write boundaries for plugin cache
