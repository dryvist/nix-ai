# Architectural Decision Records

ADRs capture the reasoning behind non-obvious design choices in nix-ai.
Each record follows the format: **Context → Decision → Consequences**.

## Documents in This Directory

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-static-vs-dynamic-model-config.md) | Static vs dynamic model config files for PAL MCP | Accepted | 2026-04-18 |
| [0002](0002-activation-merge-pattern.md) | Activation-time deep-merge instead of Nix store symlinks | Accepted | 2026-04-18 |
| [0003](0003-galileo-ai-observability.md) | Galileo AI observability — fail-closed homelab integration | Accepted | 2026-05-22 |

## Format

Each ADR uses this structure:

```markdown
## Context
What problem prompted this decision? What constraints existed?

## Decision
What was decided, and why this option over the alternatives?

## Consequences
What are the trade-offs? What becomes easier? What becomes harder?
```

## When to Add an ADR

Write an ADR when:

- A design choice will surprise a future contributor (human or AI)
- Multiple reasonable approaches exist and the chosen one has non-obvious trade-offs
- A decision has already been revisited once — document it so it is not revisited again
