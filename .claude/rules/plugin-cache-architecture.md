---
description: Marketplace symlinks vs cache, never delete cache mid-session, never mutate cache from activation scripts
paths:
  - "**/.claude/plugins/**"
  - "**/modules/claude/**"
  - "**/plugins.nix"
  - "**/plugins/*.nix"
  - "**/orphan-cleanup.nix"
---

# Plugin Cache Architecture

## Marketplace Symlinks

Marketplace directories (`~/.claude/plugins/marketplaces/`) are single directory symlinks
to the Nix store, NOT recursive per-file symlinks.

**Never use `recursive = true` or `force = true` in `plugins.nix`:**

- `recursive = true` creates per-file symlinks, which allows `.backup` file pollution
- `force = true` causes home-manager to rename existing files to `.backup`, polluting
  Claude Code's plugin cache when it re-indexes from marketplaces
- Neither is needed because Claude Code only READS from marketplaces

## Read/Write Separation

- **Marketplaces** (`~/.claude/plugins/marketplaces/`): Read-only. Managed by Nix.
  Claude Code reads plugin definitions from here but never writes.
- **Cache** (`~/.claude/plugins/cache/`): Read-write. Owned by Claude Code.
  Plugin state, indexes, and cached data live here.

## Never Delete Plugin Cache Mid-Session

Deleting `~/.claude/plugins/cache/` or `~/.claude/plugins/installed_plugins.json` during
an active Claude Code session creates an unbreakable hook error loop. All registered hooks
(PreToolUse, PostToolUse, Stop) reference files inside the cache directory. Deleting it
causes every hook invocation to fail, including the Stop hook, creating an infinite error
loop that requires force-killing the process.

Cache staleness is handled automatically by `verify-cache-integrity.sh` on every
`darwin-rebuild switch`. No manual cache deletion is ever needed.

## Never Mutate Plugin Cache from Activation Scripts

`home.activation` scripts MUST NOT run `claude plugins update`, `claude plugins marketplace update`,
or any command that creates/deletes directories under `~/.claude/plugins/cache/`.

These commands regenerate cache directories with new hashes, which breaks `${CLAUDE_PLUGIN_ROOT}`
references in active Claude Code sessions. All registered hooks (PreToolUse, PostToolUse, Stop)
resolve `${CLAUDE_PLUGIN_ROOT}` at session start — when the old hash path disappears, every hook
call fails, including the Stop hook, creating an unbreakable error loop.

The correct mechanism is:

- **Nix-managed marketplace symlinks** update the store path on rebuild
- **`verify-cache-integrity.sh`** (in `orphan-cleanup.nix`) detects stale caches via hash comparison
  and purges only when the store path actually changed
- **Claude Code detects marketplace changes on new session start** — no forced re-index needed

Commit `edba1ad` (2026-03-19) introduced an `updateClaudePlugins` activation script that violated
this rule, causing intermittent hook failures in active sessions. It was removed in the subsequent fix.

## Synthetic Marketplaces

Repos with skills but no native `.claude-plugin/` structure (e.g., `browser-use/browser-use`)
need a synthetic marketplace wrapper. The derivation in `claude-config.nix` must create:

1. **Marketplace manifest**: `.claude-plugin/marketplace.json` at the marketplace root
2. **Per-plugin manifest**: `.claude-plugin/plugin.json` inside each plugin directory
3. **Skills symlink**: linking to the upstream repo's skills

Without the per-plugin `plugin.json`, Claude Code reports "Plugin X not found in marketplace Y"
even when the marketplace.json correctly declares the plugin.

Additionally, Claude Code discovers marketplaces via `~/.claude/plugins/known_marketplaces.json`
(its actual registry), NOT directly from `extraKnownMarketplaces` in `settings.json`. Entries
propagate from `extraKnownMarketplaces` only when Claude Code can successfully fetch the
marketplace from the declared GitHub source. Synthetic marketplaces fail this fetch (no upstream
structure), so the `knownMarketplacesMerge` activation in `settings.nix` ensures the local
`installLocation` is registered directly.

## Migration Path

Phase 1 of `orphan-cleanup.nix` handles the one-time migration from `recursive = true`
(real directories with per-file symlinks) to directory symlinks. After the first rebuild,
marketplace paths are already symlinks and the migration code is a no-op.
