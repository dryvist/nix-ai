# Skill category map — one group per deployed skill. Read by default.nix,
# which also derives the deployment groups `activeGroups` gates from it.
# Group meanings are documented beside the import.
{
  # Universal: applies to any task in any repository. Keep this small —
  # every member is listed in every session on every harness.
  core = [
    "code-quality-standards"
    "commit-commands-commit"
    "delegate-to-ai"
    "goal"
    "handoff"
    "native-first"
    "ponytail"
    "premium-agent-orchestration"
    "resume"
    "session-status"
    "skills-registry"
    "track-followups"
  ];

  # Branching, PRs, releases, CI troubleshooting.
  git = [
    "analyzing-git-sessions"
    "codeql-permission-classification"
    "commit-commands-clean_gone"
    "commit-commands-commit-push-pr"
    "finalize-pr"
    "gh-cli-patterns"
    "git-flow-next"
    "git-workflow-standards"
    "github-actions-silent-failures"
    "github-workflow-security-patterns"
    "issue-sweep"
    "merge-pr"
    "pr-standards"
    "pr-sweep"
    "pre-commit-architecture"
    "promote-release"
    "prune-branches"
    "rebase-pr"
    "refresh-repo"
    "resolve-pr-threads"
    "shape-issues"
    "shared-workflow-org-refs"
    "ship"
    "sync-main"
    "trigger-ai-reviews"
    "troubleshoot-precommit"
    "troubleshoot-rebase"
    "troubleshoot-worktree"
  ];

  # Session continuity, retrospectives, usage analysis.
  session = [
    "auto-maintain"
    "extracting-session-data"
    "multi-model-review"
    "replan"
    "retrospecting"
    "token-breakdown"
    "wrap-up"
    "wrap-up-docs"
  ];

  # Authoring skills, hooks, plugins and their config.
  authoring = [
    "claude-automation-recommender"
    "claude-skill-authoring"
    "hookify-configure"
    "hookify-help"
    "hookify-hookify"
    "hookify-list"
    "reviewing-claude-config"
    "skill-creator"
    "validate-readme"
    "writing-rules"
  ];

  # Code review, delegation tiers, and the ponytail helpers.
  review = [
    "code-review-code-review"
    "delegate-to-router"
    "feature-dev-feature-dev"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
    "ponytail-review"
    "review-standards"
  ];
  nix = [
    "nix-tool-policy"
  ];
  homelab = [
    "dell-idrac-bmc-ops"
    "homelab-runbooks"
    "infrastructure-standards"
    "openbao-dynamic-aws-creds"
    "openbao-secrets"
    "orchestrate-infra"
    "proxmox-cluster-ops"
    "pxe-netboot"
    "sync-inventory"
    "terrakube-ops"
    "test-e2e"
    "workstation-offbox-backup"
    "zfs-resumable-transfers"
  ];
  ai = [
    "autoresearch"
    "claude-api"
    "codex-adversarial-review"
    "codex-cancel"
    "codex-cli-runtime"
    "codex-rescue"
    "codex-result"
    "codex-result-handling"
    "codex-review"
    "codex-setup"
    "codex-status"
    "gemini"
    "gpt-5-4-prompting"
    "hf-cli"
    "huggingface-best"
    "huggingface-community-evals"
    "huggingface-datasets"
    "huggingface-gradio"
    "huggingface-llm-trainer"
    "huggingface-local-models"
    "huggingface-paper-publisher"
    "huggingface-tool-builder"
    "huggingface-trackio"
    "huggingface-vision-trainer"
    "huggingface-zerogpu"
    "langfuse"
    "llm-router-ops"
    "mcp-builder"
    "microsoft-foundry"
    "openrouter-models"
    "perf-reclaim"
    "perf-snapshot"
    "train-sentence-transformers"
    "transformers-js"
  ];
  docs = [
    "brand-guidelines"
    "dashmotion"
    "doc-coauthoring"
    "internal-comms"
  ];
  research = [
    "github-code-search"
    "huggingface-papers"
    "last30days"
  ];
  workspace = [
    "algorithmic-art"
    "canvas-design"
    "docx"
    "file-organizer"
    "frontend-design"
    "pdf"
    "pptx"
    "slack-gif-creator"
    "theme-factory"
    "web-artifacts-builder"
    "webapp-testing"
    "workspace-standards"
    "xlsx"
  ];
}
