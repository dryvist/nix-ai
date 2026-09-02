# Measuring agent context

How to measure what a session loads, what the number decomposes into, and the
hypotheses that were tested and refuted. Companion to
[`agent-context-architecture.md`](agent-context-architecture.md), which holds
the tiers and the budgets.

## The decomposition

Nested ablation, one variable per step, single measurement window. Rows sum to
the total; there is no balancing remainder.

| Cumulative configuration | Tokens | Step adds | What the step adds |
| --- | ---: | ---: | --- |
| empty dir outside `$HOME`, no MCP, no settings | **32,914** | — | Claude Code's own prompt + built-in tool schemas |
| …in this repo | 36,846 | +3,932 | repo and parent instruction chain |
| …+ user settings | 71,772 | **+34,926** | plugins (skills, agents), hooks, rules, MCP config |
| …+ project settings | 80,746 | +8,974 | this repo's `.claude/settings.json` |
| …+ 5 local MCP servers | 89,360 | +8,614 | MCP tool schemas |

Inside the +34,926, from transcript attachments: `skill_listing` 12,543 ·
`agent_listing_delta` 1,153 · `deferred_tools_delta` 506 · `~/.claude/rules`
3,920 (measured by removal). The remaining **16,804 is not decomposable from a
transcript** — plugin instructions, agent definitions and MCP server
instructions arrive inside the system prompt, not as attachments. It is named
as unattributed rather than folded into a plausible label.

## Properties of the instrument

- **`--strict-mcp-config` is mandatory.** A bare `claude -p` attaches hosted MCP
  connectors that connect nondeterministically per run and swing the total by
  **0–25,000 tokens with no configuration change at all** — two runs twenty
  minutes apart differed by ~16,000. Any comparison without it is noise.
- **Compare differences, not absolutes.** Totals drift upward within a session;
  differences inside one short window are stable to ±25 tokens.
- **The floor is a control, and it is not exactly constant.** The working
  directory path is part of the prompt, so a longer temp directory name moves it
  a few tokens. Treat drift beyond ~200 as a changed environment.
- **`claude -p` under-reports an interactive session.** Its first user message is
  8 bytes; `SessionStart` hook output is injected only interactively.
- **Never subtract a floor measured under different conditions.** An afternoon of
  figures was lost to subtracting a no-MCP floor from totals measured with MCP
  attached. That error is what produced the withdrawn 64k floor.
- **Byte counts understate savings.** An instruction trim predicted at −5,137
  from byte counts measured **−11,854**. Measure where a measurement is possible.

## Refuted — tested, not assumed

Each was plausible, each would have led to a wrong or destructive change, and
three were acted on before being tested.

| Hypothesis | Test | Result |
| --- | --- | --- |
| `ENABLE_TOOL_SEARCH` gates eager tool schemas | all four values, real env var | inert; `false` == unset exactly |
| session-capture hooks cost ~24,000 | remove them, replicate | **0** |
| nested memory files drive the excess | hide the container holding 122 | **0** |
| worktree count drives context | add 16 worktrees to a clean repo | **0**, to the token |
| directory path under the workspace root | empty probes in three parents | identical |
| the two rules trees are double-loaded | remove one, measure | one store path, two routes, read once |

**A correlation across repos is not a cause.** The only hypotheses that survived
were tested by removing exactly one thing and measuring.

## The manual-invoke tier has a precondition, and it has failed once

Marking a skill `disable-model-invocation: true` removes it from the listing and
keeps it callable by `/name`: a probe skill measured **518 tokens listed against
10 marked**, still invocable. The mechanism is sound.

Delivering it is not solved. Most marketplaces are third-party and
`~/.claude/plugins/cache/` is read-only nix store, so the frontmatter has to be
injected by a derivation — which **changes every marketplace's store path and
invalidates Claude Code's plugin cache**. `installed_plugins.json` keeps
pointing at the old locations.

A first attempt shipped without handling this. After the converge, 113 of 115
`installPath` entries were missing and **no plugin skill loaded at all** —
neither a marked one nor an unmarked keep-list one. It measured as a
16,588-token saving and was entirely capability loss. It was reverted.

Any implementation must:

1. Refresh `installed_plugins.json` in the same activation that changes a
   marketplace path.
2. Be verified by **invoking a keep-list skill on the live system after the
   converge**. A token measurement cannot distinguish a demoted skill from a
   missing one; only invocation can.
3. Derive the keep-list from recorded usage, not from judgment about what an
   agent "ought" to reach for. That judgment, applied to skill groups, once
   removed 121 skills carrying 164,619 recorded invocations.

## Not yet built

A `lib/checks/` assertion that every catalogued skill is reachable through
exactly one tier, so an untiered skill fails the build instead of disappearing
quietly. `lib/checks/mcp.nix` does this for MCP servers already
(`shared-mcp-on-demand-reachable`); skills have no equivalent. Until it exists,
reachability is a manual spot inspection and a capability can vanish without
anything reporting it.
