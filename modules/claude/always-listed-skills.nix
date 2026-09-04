# Always-listed skills — tier 1 of docs/architecture/agent-context-architecture.md
#
# Every other marketplace skill is marked `disable-model-invocation: true`. It
# leaves the session's skill listing and stays callable by /name — verified
# 2026-09-02 with a probe skill invoked headlessly, which returned its marker.
#
# THIS LIST IS MEASURED, NOT CHOSEN.
#
# It is exactly the set of skills the model has actually invoked itself, taken
# from `Skill` tool calls in the local session transcripts: 957 recorded calls
# across 101 distinct skills. A skill the model has never once reached for in
# that history cannot lose model-invocation it was not using, so demoting it is
# provably free — while a person typing /name is unaffected either way.
#
# An earlier version of this list was chosen by judgment about what an agent
# "ought" to discover. That judgment removed skills carrying 164,619 recorded
# invocations, so the list is now derived from usage and should be regenerated
# from it rather than edited by hand:
#
#   grep -rhoE '"name":"Skill","input":\{"skill":"[^"]+"' ~/.claude/projects \
#     --include='*.jsonl' | sed 's/.*"skill":"//;s/"$//' | cut -d: -f2- | sort -u
#
# Cost of being listed, measured in nix-ai: ~518 tokens of every session for a
# skill with a long description, ~98 on average, against ~10 for manual-invoke.
[
  "AskUserQuestion"
  "Load SendMessage tool"
  "Monitor"
  "PushNotification"
  "Skill"
  "ToolSearch"
  "adopt-export"
  "agentsmd-authoring"
  "ai-observability-goal"
  "artifact-design"
  "brainstorming"
  "claude-api"
  "claude-automation-recommender"
  "claude-skill-authoring"
  "clean_gone"
  "cli-helpers"
  "commit-push-pr"
  "dataviz"
  "deep-research"
  "delegate-to-ai"
  "deploy-routine-changes"
  "dispatching-parallel-agents"
  "docs-starlight-authoring"
  "double-check"
  "extracting-session-data"
  "finalize-pr"
  "gemini"
  "generate-html"
  "generate-island"
  "gh-cli-patterns"
  "git-flow-next"
  "git-workflow-standards"
  "github-code-search"
  "github-workflow-security-patterns"
  "goal"
  "granola-merger"
  "handoff"
  "hf-cli"
  "homelab-runbooks"
  "infrastructure-standards"
  "list"
  "llm-router-ops"
  "merge-pr"
  "mermaid-visualizer"
  "native-first"
  "nonexistent"
  "openbao-secrets"
  "openrouter-models"
  "pdf"
  "perf-reclaim"
  "perf-snapshot"
  "ponytail"
  "ponytail-help"
  "pr-standards"
  "pr-sweep"
  "pre-commit-architecture"
  "premium-agent-orchestration"
  "promote-release"
  "prune-branches"
  "quick-add-package"
  "receiving-code-review"
  "refresh-repo"
  "release-local"
  "reload-plugins"
  "replan"
  "rescue"
  "resolve-pr-threads"
  "resume"
  "retrospecting"
  "retrospecting quick"
  "reviewing-claude-config"
  "schedule"
  "screenpipe"
  "scrub-event"
  "scrub-pii"
  "session-status"
  "shared-workflow-org-refs"
  "ship"
  "simplify"
  "skills-registry"
  "splunk-homelab"
  "squash-merge-pr"
  "status-generator"
  "sync-inventory"
  "sync-main"
  "systematic-debugging"
  "test-e2e"
  "toggl-pdf-to-csv"
  "token-breakdown"
  "track-followups"
  "trigger-ai-reviews"
  "troubleshoot-precommit"
  "update-config"
  "using-git-worktrees"
  "validate-readme"
  "vault-backup"
  "vault-researcher"
  "verification-before-completion"
  "wrap-up"
  "writing-clearly-and-concisely"
  "writing-skills"
  "xlsx"
]
