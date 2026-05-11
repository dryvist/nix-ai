---
tools:
  github:
    toolsets: [default]

safe-outputs:
  create-issue:
    title-prefix: "[health-audit] "
    labels: ["ai:created"]
    group: true
    max: 8
    expires: 7d
    close-older-issues: true

  add-labels:
    allowed: ["type:ci", "type:chore", "type:security", "priority:critical", "priority:high", "priority:medium", "priority:low", "size:xs"]
    max: 16

  close-issue:
    required-title-prefix: "[health-audit] "
    required-labels: ["ai:created"]
    max: 10
    state-reason: "completed"
---
