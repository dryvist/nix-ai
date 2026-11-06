---
type: Reference
title: Model policy admission
description: Pure evaluation of role-map and local catalog models against the shared model policy.
timestamp: "2026-11-06"
---

## Admission

`lib/model-policy.nix` reads
`ansible/roles/llm_model_catalog/files/model-policy.json` from the
`homelab-contracts` input. `lib/role-map.nix` checks all role-map model IDs
and the complete local catalog aggregated by `modules/mlx/catalog-data.nix`.
The enabled MLX module also checks caller-supplied role maps.

Each served ID requires exactly 1 policy record, a nonempty `upstream_id`,
a `dossier` path or URL, and a valid `upstream_created` date. Copies sharing
an upstream must agree on its creation date. Denials apply to served IDs
and upstream IDs. Every model kind follows the same admission rules.

Age uses Gregorian calendar days from `upstream_created` through `as_of`,
including leap years. The interval is inclusive: age 0 through `max_age_days`
passes. Future dates, missing dates, and ambiguous dates fail. Quantized
copies use their upstream creation date. Evaluation uses no current time.

The guard activates when the pinned contracts input contains the policy.
Until that input bump, an absent file leaves admission unchanged. A present
invalid policy fails evaluation. The synthetic policy under
`lib/checks/fixtures/model-policy/` supplies regression inputs only.

The lead can evaluate the fixture regressions and current policy admission:

```sh
nix eval .#checks.x86_64-linux.model-policy.drvPath
```

The repository-wide evaluation command is:

```sh
nix flake check --no-build --all-systems
```
