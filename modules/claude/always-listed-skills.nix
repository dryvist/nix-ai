# Always-listed skills — tier 1 of docs/architecture/agent-context-architecture.md
#
# Every other marketplace skill is marked `disable-model-invocation: true`. It
# leaves the session's skill listing and stays callable by /name — verified
# 2026-09-02 with a probe skill invoked headlessly, which returned its marker.
#
# THIS LIST IS MEASURED, NOT CHOSEN. Two filters, both mechanical:
#
#   1. the model invoked it at least TWICE in local session transcripts;
#   2. the name is a real skill — some directory ships a SKILL.md for it.
#
# Filter 2 exists because the extraction previously captured tool names
# (`AskUserQuestion`, `Monitor`, `Skill`, `ToolSearch`) and slash commands,
# which are not skills and can never match a SKILL.md directory. They cost a
# reader's attention and prove nothing about the tier.
#
# Filter 1 replaces an earlier "invoked at least once" rule, which listed 102
# names — over half of them single-use. At ~98 tokens of every session per
# listed skill, and of every subagent, a one-off is not a core skill. A
# demoted skill is not lost: /name still reaches it.
#
# Regenerate rather than hand-editing:
#
#   used=$(grep -rhoE '"name":"Skill","input":\{"skill":"[^"]+"' ~/.claude/projects \
#     --include='*.jsonl' | sed 's/.*"skill":"//;s/"$//' | cut -d: -f2- \
#     | sort | uniq -c | awk '$1>=2{$1="";sub(/^ /,"");print}' | sort -u)
#   real=$(find ~/.claude/plugins/cache -type f -name SKILL.md \
#     | awk -F/ '{print $(NF-1)}' | sort -u)
#   comm -12 <(echo "$used") <(echo "$real")
#
# `skills-registry` is kept unconditionally: without it the tier is a trapdoor,
# because nothing in the session would name the skills it has hidden.
#
# Cost of being listed, measured in nix-ai: ~518 tokens of every session for a
# skill with a long description, ~98 on average, against ~10 for manual-invoke.
[
  "ai-observability-goal"
  "brainstorming"
  "claude-api"
  "claude-skill-authoring"
  "delegate-to-ai"
  "dispatching-parallel-agents"
  "extracting-session-data"
  "finalize-pr"
  "gemini"
  "gh-cli-patterns"
  "git-flow-next"
  "github-code-search"
  "github-workflow-security-patterns"
  "goal"
  "handoff"
  "homelab-runbooks"
  "infrastructure-standards"
  "llm-router-ops"
  "merge-pr"
  "native-first"
  "openbao-secrets"
  "pdf"
  "ponytail"
  "pr-sweep"
  "pre-commit-architecture"
  "premium-agent-orchestration"
  "promote-release"
  "prune-branches"
  "receiving-code-review"
  "refresh-repo"
  "replan"
  "resolve-pr-threads"
  "retrospecting"
  "screenpipe"
  "session-status"
  "shared-workflow-org-refs"
  "ship"
  "skills-registry"
  "splunk-homelab"
  "sync-inventory"
  "sync-main"
  "systematic-debugging"
  "toggl-pdf-to-csv"
  "token-breakdown"
  "track-followups"
  "using-git-worktrees"
  "wrap-up"
  "writing-clearly-and-concisely"
]
