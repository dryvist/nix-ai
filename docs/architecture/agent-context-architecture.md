# Agent Context Architecture

What every agent session loads at startup, across every harness, and the tiers
that decide it. Supersedes [`plugin-scoping.md`](plugin-scoping.md), which
covers Claude Code only.

## The budget, measured

Every number here comes from fresh headless sessions in this repo on
2026-09-02, using `--settings` / `--setting-sources` overrides (which outrank
user settings), read from the first `usage` block of each transcript.

| Configuration | First request |
| --- | ---: |
| Default | 128,949 |
| Agent teams off | 127,975 |
| `ENABLE_TOOL_SEARCH=false` ("load everything") | 127,749 |
| `--setting-sources user` (drop project + local) | 113,889 |
| `--setting-sources ''` (no settings at all) | **64,068** |

> **The 64,068 row is withdrawn.** `--setting-sources ''` drops settings layers
> but does **not** detach MCP servers, so it was measured with MCP attached and
> is not a floor. **The floor is 32,914**, measured from an empty directory
> outside `$HOME` with no MCP and no settings.
>
> Every conclusion drawn from the 64k figure was wrong, in particular "a
> subagent cannot go below ~64k". A subagent measuring 80,746 is 41% floor, so
> **a sub-60k subagent is a lever problem, not a harness limitation**.

Read it as two blocks:

- **Floor 32,914 — for a session that loads every built-in tool.** Claude
  Code's own system prompt plus its built-in tool schemas. It is *not* an
  absolute floor: an agent definition declaring `tools: Read` measures
  **22,680**, because `tools:` gates which schemas load, not merely which may
  execute. See the measurement companion.
- **Addressable ~56k** — everything above it: the plugin set and the skill and
  agent listings it generates, MCP configuration, and the instruction chain.
  Roughly 3,900 of what the old figure called immovable is instruction content,
  which is the most user-controllable material in the session.

Full nested decomposition, instrument properties, refuted hypotheses and the
manual-invoke precondition:
[`agent-context-measurement.md`](agent-context-measurement.md).

Two things that are *not* the problem, tested rather than assumed:

- **MCP tool schemas.** The startup injection is a names-only index (94 names,
  3,324 bytes). Setting `ENABLE_TOOL_SEARCH` to its documented maximally-eager
  value costs ~1,200 tokens. Tool search is not a lever here.
- **Agent listings.** The current enabled set computes to ~1,600 bytes.

## Which tree each harness reads

The single most important table here: a cut only helps a harness that reads the
tree being cut.

| Harness | Reads | Entries today |
| --- | --- | ---: |
| Claude Code | `~/.claude/skills` + enabled plugin skills + `<repo>/.claude/skills` | 6 + plugins |
| Codex | `~/.agents/skills` natively (`~/.codex/skills` holds only `.system`) | 72 |
| Cursor | `~/.agents/skills` and `<repo>/.agents/skills` natively | 72 |
| OpenCode | `~/.agents/skills` natively | 72 |
| qwen | `~/.qwen/skills` → symlink to the shared tree | 72 |
| agy / Antigravity | `~/.gemini/antigravity{,-cli}/skills`, `~/.gemini/config/skills` → same tree | 72 |
| Hermes | Runs off-box; no local skill tree on the workstation | — |

**Claude Code does not read `~/.agents/skills`.** Verified: `microsoft-foundry`
lives in that tree, is shipped by no enabled plugin, and does not appear in a
Claude session's skill listing. Every shared-tree name that *does* appear is
there under its plugin prefix (`github-workflows:merge-pr`), not as the flat
name the shared tree uses.

The consequence is the thing to remember: **`programs.agentSkills.activeGroups`
scopes six harnesses and does nothing for Claude.** Claude's levers are its
plugin set, `~/.claude/skills`, and `<repo>/.claude/skills`.

## The three tiers

Every skill sits in exactly one tier. The default is the cheapest one.

| Tier | Cost at startup | Reached by | Use for |
| --- | --- | --- | --- |
| **always-listed** | Full name + description, every session | Model picks it unprompted | A small core that applies to any task in any repo |
| **group-listed** | Name + description, only in repos declaring the group | Model picks it unprompted, in that repo | Domain skills — nix, homelab, cribl, docs |
| **manual-invoke** | **Nothing** until called | `/name`, typed | Everything else. This is the default. |

`manual-invoke` is `disable-model-invocation: true` in the skill's frontmatter.
Claude Code documents such skills as staying "completely out of context until
you invoke them with `/name`" — full reachability at zero listing cost.

### Harness support for tier 3 is not uniform

`disable-model-invocation` is a Claude Code frontmatter key. Whether Codex,
Cursor, OpenCode, qwen and agy honour it is an Agent Skills spec question that
is **not yet verified**. Until it is, assume those harnesses have two tiers —
present in the tree, or not — and scope them with group membership rather than
with the manual-invoke marker. Do not promise a third tier a harness cannot
deliver.

## One declaration, many renderers

A repository declares its groups once:

```yaml
# AGENTS.md frontmatter
skill-groups: [core, homelab]
```

Everything else is generated from that declaration plus the group→skill map
nix-ai publishes at `~/.agents/skills/GROUPS.json`:

| Output | Consumed by |
| --- | --- |
| `<repo>/.agents/skills/` symlinks | Codex, Cursor, OpenCode, qwen, agy |
| `<repo>/.claude/skills/` symlinks | Claude Code |
| `<repo>/.claude/settings.json` `enabledPlugins` | Claude Code |
| `.mcp.json`, `.codex/config.toml`, `opencode.json` | the matching harness |

Renderer: `agent-skill-groups link`, invoked from
`~/.config/direnv/lib/agent-skill-groups.sh`, which direnv sources before every
`.envrc`. It manages only `/nix/store` symlinks and writes `.git/info/exclude`.

**Never hand-write a per-harness file.** A second loading path beside the
native one is what produced the 2026-09-02 regression: the shared tree was
trimmed to 72 for the five harnesses that read it, while the linker
simultaneously wrote 80 skills into `<repo>/.claude/skills` — the one tree
Claude does read — taking `tofu-proxmox` from 82k to 133k–183k.

The rule that follows: **the linker must emit each skill at its declared tier**,
so a group-listed skill is linked and listed, and a manual-invoke skill is
linked and marked. Linking everything at tier 1 is what costs.

## Rules

1. **Default to manual-invoke.** A skill earns a listing by being useful in
   repos that have not declared its group.
2. **Cut the tree the harness actually reads**, per the table above. A cut
   aimed at the wrong tree measures as zero.
3. **Measure both directions before believing a lever.** Both `auto` and
   `false` were tested for `ENABLE_TOOL_SEARCH`; the difference was ~1k, which
   is how it was ruled out as a lever.
4. **Nothing may become unreachable.** Moving a skill down a tier is only valid
   if it can still be invoked — by `/name`, or by declaring its group in the
   repo that needs it.
5. **Only new sessions see a cut.** Listings are injected at startup; a running
   session keeps whatever it began with.

## Measuring

```sh
# first request of every recent session, per repo
agent-context-baseline            # see modules/scripts/agent-context-baseline.sh
```

Per-harness native equivalents, no new code:

| Harness | Command |
| --- | --- |
| Claude | first `usage` block of a fresh transcript; `/context` for the split |
| Codex | `codex debug prompt-input \| wc -c` |
| OpenCode | `opencode debug skill`, `opencode stats` |
| qwen / agy | tree parity against `~/.agents/skills` |

Targets: **main session < 90k**; **subagent < 60k** — reachable: it needs
~20,700 cut from ~47,800 of configurable content, and the skill listing alone
is 12,543.

## Measured: MCP is the largest block, not skills

Measured 2026-09-02 with `claude -p "reply OK"` in `nix-ai`, first-request
tokens. This supersedes the initial framing of this document, which assumed the
skill listing was the dominant cost.

| Configuration | First request |
| --- | ---: |
| default | 111,311 |
| `--strict-mcp-config` (no MCP) | 71,516 |
| `--strict-mcp-config --setting-sources ''` | 36,693 |

MCP tool schemas cost **39,795 tokens**. For comparison, in the same session the
skill listing is 17,026, the agent listing 6,217, and the always-on instruction
chain roughly 13,500.

Isolating the local servers (`--strict-mcp-config --mcp-config <file>`):

| Local MCP set | First request | Cost over no-MCP |
| --- | ---: | ---: |
| none | 71,516 | — |
| `codex,fabric,grep,time` | 76,990 | 5,474 |
| all seven | 109,015 | 37,499 |

Per server, over the four-server baseline: **zammad 22,139**, apple-events
6,746, vikunja 3,140. A single incident-tracking server that a typical session
never calls is one fifth of that session's entire context.

Hence the third tier applies to MCP servers exactly as it does to skills:
`programs.aiMcp.onDemandServers` holds servers out of the always-on profile and
renders each to `~/.claude/mcp-available/<name>.json`, so a session that needs
one attaches it explicitly:

```sh
claude --mcp-config ~/.claude/mcp-available/zammad.json
```

`lib/checks/mcp.nix` -> `shared-mcp-on-demand-reachable` asserts both halves:
an on-demand server must be absent from the always-on profile **and** present as
an attachable file. Absent from both is a silent capability loss, which is the
failure mode this tier is most likely to produce.

### `ENABLE_TOOL_SEARCH` does not help — settled

Tested as a real environment variable rather than a `--settings` override, which
an earlier measurement had used and which does not reach the startup decision:
`auto:10` 108,176 / `auto` 113,580 / unset 111,311 / `false` 111,311. The
documented "load everything" value equals the default exactly. The knob is inert
on this stack; the saving has to come from not attaching a server at all.
