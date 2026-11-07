---
type: Reference
title: Model policy admission
description: Model admission and dated benchmark evidence from the shared model policy.
timestamp: "2026-11-07"
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

The shared policy is required. An absent file or invalid policy fails
evaluation, including when no models are configured. The synthetic policy under
`lib/checks/fixtures/model-policy/` supplies regression inputs only.

## Dated benchmark evidence

`checks.x86_64-linux.model-policy-benchmarks` calls `validate_policy` from
`tests/llm_model_catalog/test_model_policy.py` in the same locked
`homelab-contracts` input. That validator owns dossier paths, benchmark sections,
scores, dates, and source requirements. Every policy model is checked, including
models without role assignments. Validation uses the shared validator's current
UTC date; synthetic fixtures use their policy's `as_of` date.

The check builds during CI's `nix flake check`. A missing dossier, missing or
empty benchmark section, or undated benchmark fails the build. Fixtures cover
these rejections and a dated numeric result with a source. The pure Nix admission
checks run at evaluation time; the shared Python evidence check runs at build
time. Evaluation alone does not execute the evidence check.

## Verification

The lead can evaluate the fixture regressions and current policy admission:

```sh
nix eval .#checks.x86_64-linux.model-policy.drvPath
```

The repository-wide evaluation command is:

```sh
nix flake check --no-build --all-systems
```

CI supplies Nix evaluation and build proof. To run the evidence check alone:

```sh
nix build .#checks.x86_64-linux.model-policy-benchmarks
```
