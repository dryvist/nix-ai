---
engine: copilot
imports:
  - githubnext/agentics/workflows/ci-doctor.md@main
on:
  workflow_run:
    workflows: ["CI Gate"]
    types: [completed]
    branches: [main, develop]
if: ${{ github.event.workflow_run.conclusion == 'failure' || github.event.workflow_run.conclusion == 'cancelled' }}
---

# CI Doctor

Imported from upstream agentics.
