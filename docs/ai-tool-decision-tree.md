# AI Tool Decision Tree

When to use which tool for AI-assisted tasks in the nix-ai ecosystem.

## Quick Reference

| Situation | Use | Why |
| --- | --- | --- |
| One-shot text transformation in a shell pipeline | `fabric --pattern X` | Pipe-based, no Claude Code needed |
| YouTube video processing | `fabric -y URL --pattern summarize` | Built-in yt-dlp + Jina extraction |
| Want Claude Code to auto-invoke a pattern | Fabric skills (synthetic marketplace) | 32 curated patterns auto-loaded by description match |
| Want to explicitly call a pattern from Claude Code | Fabric MCP server | Pattern appears as a callable MCP tool |
| Single external model call | Bifrost (`localhost:30080`) | OpenAI-compatible, multi-provider |
| Writing Python/Go code that calls an LLM | Anthropic SDK / OpenAI SDK | Direct API, no middleware |

## When to Use Fabric CLI

Best for: **shell pipelines and one-shot transformations**

```bash
# Summarize an article
cat article.md | fabric --pattern summarize

# Extract wisdom from a YouTube video
fabric -y "https://youtube.com/watch?v=..." --pattern extract_wisdom

# Generate a commit message from a diff
git diff --staged | fabric --pattern create_git_diff_commit

# Review code
cat src/main.go | fabric --pattern review_code
```

Use when:

- You're in a terminal, not a Claude Code session
- You want to pipe stdin through a pattern
- You need YouTube/URL extraction (built-in yt-dlp + Jina)
- You want local MLX inference for a quick task

## When to Use Fabric Skills (Claude Code Auto-Discovery)

Best for: **letting Claude Code pick the right pattern automatically**

32 curated patterns are registered as Claude Code skills via the synthetic
marketplace. Claude Code loads them based on description matching — you don't
need to ask for a specific pattern.

Use when:

- You're in a Claude Code session
- The task naturally matches a pattern (summarize, extract, analyze, review)
- You want Claude to decide whether a fabric pattern is useful

Not for:

- Tasks that need a specific pattern — use the CLI or MCP server instead
- Patterns not in the curated 32 — use CLI or expand the set (#446)

## When to Use Fabric MCP Server

Best for: **explicit pattern invocation from Claude Code**

The MCP server (community-maintained `ksylvan/fabric-mcp`) exposes patterns
as callable tools. Disabled by default.

Use when:

- You want to call a specific pattern by name from Claude Code
- You need structured tool-call semantics (vs free-text skill matching)

Not for:

- Shell pipelines (use CLI — faster, no MCP overhead)
- Auto-discovery (use skills — MCP requires explicit invocation)

## When to Use Bifrost

Best for: **external model calls and multi-provider routing**

| Tool | Use Case |
| --- | --- |
| Bifrost (`localhost:30080`) | Single model call via OpenAI-compatible API |

Use when:

- You need a non-Claude model (Gemini, OpenRouter, local MLX)
- You're building a workflow that routes across providers

## Anti-Patterns

| Don't Do This | Do This Instead |
| --- | --- |
| Use MCP server for a quick shell pipeline | `echo "text" \| fabric --pattern X` |
| Manually invoke fabric skills from Claude Code | Let auto-discovery match by description |
| Use fabric for multi-step automated workflows | Use the orchestrator (when it has consumers) |
| Route through Bifrost for a task fabric handles | Use fabric directly — it already talks to MLX |
