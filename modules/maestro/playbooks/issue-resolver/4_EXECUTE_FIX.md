# Execute Fix

Implement the fix, tests, and create PR for the selected issue.

## Context

Loop iteration: {{LOOP_NUMBER}}
Target repository: $MAESTRO_CURRENT_REPO

## Prerequisites

- [ ] Verify `selected-issue.json` exists from previous step
- [ ] If `no-issue-selected.json` exists, skip this document

## Tasks

- [ ] Read issue details from `selected-issue.json`
- [ ] Extract issue number: `ISSUE_NUMBER=$(jq -r '.number' selected-issue.json)`
- [ ] Create an isolated worktree: run `/refresh-repo`, then use the AI tool's
      native worktree mechanism (Claude's `EnterWorktree` → `.claude/worktrees/`).
      If creating one manually, place it **outside** the repo working tree (a
      sibling of the clone), never as a child — `git worktree add` into the
      checkout pollutes the main branch's working directory.
- [ ] Analyze issue requirements thoroughly
- [ ] Implement the fix following repository conventions
- [ ] Add or update tests as appropriate
- [ ] Run linting and tests: repository-specific commands
- [ ] Commit with message: `fix: <description>\n\nFixes #$ISSUE_NUMBER`
- [ ] Push branch to origin
- [ ] Create draft PR: `gh pr create --fill --draft --body "Fixes #$ISSUE_NUMBER"`
- [ ] Write PR details to `pr-created.json`

## Commit Message Format

```text
<type>: <description>

Fixes #<issue_number>
```

## Output

Creates `pr-created.json`:

```json
{"pr_number": 456, "pr_url": "https://github.com/...", "issue_number": 123}
```
