# Skill category map — one group per deployed skill. Read by default.nix,
# which also derives the deployment groups `activeGroups` gates from it.
# Group meanings are documented beside the import.
#
# `rec` so `iac` can alias `homelab` below instead of repeating its list —
# same skills, a second name that matches the topic-driven group vocabulary
# (default.nix's activeGroups, repo-link's per-repo AGENTS.md declarations).
rec {
  # Universal: applies to any task in any repository. Keep this small —
  # every member is listed in every session on every harness.
  core = [
    # frontend-design and canvas-design: any repository can produce a
    # diagram, a slide, a page or a chart, so these are tier 1 by
    # directive rather than by measured invocation count.
    "canvas-design"
    "code-quality-standards"
    "commit-commands-commit"
    "delegate-to-ai"
    "frontend-design"
    "goal"
    # Delegation mechanics are universal: every repository's session has bulk
    # reads to hand off, and a skill only this session can reach is a skill
    # nothing delegates through.
    "local-subagents"
    # The one-command helper for the fast-subagent tier: the same universal
    # delegation habit as local-subagents, and the skill every session is
    # meant to keep re-using for routine steps.
    "fast-subagent"
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
    "commit-commands-clean_gone"
    "commit-commands-commit-push-pr"
    "finalize-pr"
    "gh-cli-patterns"
    "gh-stack"
    "git-flow-next"
    "git-workflow-standards"
    "github-actions-silent-failures"
    "issue-sweep"
    "merge-pr"
    "pr-standards"
    "pr-stacks"
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
    "reviewing-agent-definitions"
    "reviewing-claude-config"
    "reviewing-command-definitions"
    "reviewing-project-guidance"
    "reviewing-runtime-configuration"
    "skill-creator"
    "validate-readme"
    "writing-rules"
  ];

  # Code review, delegation tiers, and the ponytail helpers.
  review = [
    "code-review-code-review"
    # Superseded upstream by `local-subagents` in `core`. It stays listed
    # until the marketplace pin advances past that release: this map must
    # name every DEPLOYED skill (lib/checks/agent-skills.nix), and the pinned
    # marketplace still ships this one. Naming a skill that is not deployed
    # is tolerated; the reverse is a check failure.
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
  # Topic-vocabulary alias for `homelab` (repo-link/agent-skill-groups.sh maps
  # GitHub topics terraform/opentofu/iac/infrastructure-as-code/ansible to this
  # name) — B6 "topic-scoped skill groups": infra-standards, infra-orchestration,
  # homelab-ops and openbao, opt-in per repo instead of always installed.
  iac = homelab;
  # Topic-vocabulary group for the codeql-resolver skills (repo-link maps the
  # `codeql` GitHub topic here) — opt-in per repo instead of bundled into `git`.
  security = [
    "codeql-permission-classification"
    "github-workflow-security-patterns"
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
    "codex-transfer"
    "gemini"
    "gpt-5-4-prompting"
    "hf-cli"
    "hf-cloud-aws-context-discovery"
    "hf-cloud-python-env-setup"
    "hf-cloud-sagemaker-deployment-planner"
    "hf-cloud-sagemaker-iam-preflight"
    "hf-cloud-sagemaker-production-defaults"
    "hf-cloud-serving-image-selection"
    "hf-mem"
    "huggingface-best"
    "huggingface-community-evals"
    "huggingface-datasets"
    "huggingface-gradio"
    "huggingface-llm-trainer"
    "huggingface-local-models"
    "huggingface-lora-space-builder"
    "huggingface-paper-publisher"
    "huggingface-spaces"
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
    "trl-training"
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
    "docx"
    "file-organizer"
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
