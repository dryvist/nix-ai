# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,antigravity-cli,mcp,mlx,fabric}.nix
#
# THESE CHECKS ONLY EXIST FOR x86_64-linux (see flake.nix `checks`). On a Mac,
# `nix flake check` therefore passes them VACUOUSLY — it never evaluates them,
# so a broken assertion here returns exit 0 and looks green. Two separate
# catalog defects shipped to develop behind that false negative (2026-08-14).
#
# Validate a check on a Mac by naming the system explicitly:
#   nix eval '.#checks.x86_64-linux.<check>.drvPath'
#
# The lint checks are the ones this bites most often, because they are pure
# source scans that a Mac can run directly — but only if you invoke them, since
# `nix flake check` skips them here. Run both before pushing:
#   nix run nixpkgs#statix -- check .
#   nix run nixpkgs#deadnix -- -L --fail .
{
  pkgs,
  src,
  home-manager,
  aiModule,
  renderAutonomous,
}:
let
  inherit (import ./checks-fixtures.nix { inherit pkgs home-manager aiModule; })
    testLocalModelId
    mkHmConfigWith
    mkHmConfig
    hmConfig
    hmConfigAgentSkillsShared
    hmConfigVctCli
    hmConfigFabricServer
    hmConfigCatalog
    hmConfigDefaultModel
    hmConfigSmallRole
    hmConfigDupRole
    hmConfigCluster
    hmConfigTokenMeter
    hmConfigSessionSync
    hmConfigSessionArchive
    hmConfigLitellmLocal
    ;
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/token-meter.nix {
  inherit
    pkgs
    src
    hmConfig
    hmConfigTokenMeter
    ;
})
// (import ./checks/session-sync.nix {
  inherit
    pkgs
    hmConfig
    hmConfigSessionSync
    ;
})
// (import ./checks/session-archive.nix {
  inherit
    pkgs
    hmConfig
    hmConfigSessionArchive
    ;
})
// (import ./checks/ai-stack.nix { inherit pkgs testLocalModelId; })
// (import ./checks/ai-stack-endpoint.nix { inherit pkgs; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/telemetry.nix { inherit pkgs mkHmConfigWith; })
// (import ./checks/agent-skills-repo-link.nix { inherit pkgs; })
// (import ./checks/agent-skills-groups.nix { inherit pkgs mkHmConfig; })
// (import ./checks/manual-invoke-marking.nix { inherit pkgs src; })
// (import ./checks/agent-skills.nix {
  inherit
    pkgs
    hmConfig
    hmConfigAgentSkillsShared
    ;
})
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/cursor.nix { inherit pkgs hmConfig; })
// (import ./checks/herdr.nix { inherit pkgs hmConfig; })
// (import ./checks/qwen-code.nix { inherit pkgs hmConfig; })
// (import ./checks/antigravity-cli.nix { inherit pkgs hmConfig; })
// (import ./checks/vct-cli.nix {
  inherit
    pkgs
    hmConfig
    hmConfigVctCli
    ;
})
// (import ./checks/mcp.nix { inherit pkgs hmConfig; })
// (import ./checks/autonomous-profile.nix {
  inherit pkgs;
  render = renderAutonomous;
})
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ./checks/mlx-catalog-vlm.nix { inherit pkgs hmConfigCatalog src; })
// (import ./checks/mlx-mtp-reachable.nix { inherit pkgs mkHmConfig; })
// (import ./checks/mlx-single-model.nix { inherit pkgs src; })
// (import ./checks/mlx-bash32.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-watchdog.nix { inherit pkgs src; })
// (import ./checks/mlx-wedge-detect.nix { inherit pkgs src; })
// (import ./checks/mlx-wedge-metricsfree.nix { inherit pkgs src; })
// (import ./checks/mlx-worker-reap.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-warmup.nix { inherit pkgs src; })
// (import ./checks/mlx-model-extra-args.nix { inherit pkgs; })
// (import ./checks/mlx-catalog.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-backend-selection.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-worker-flag-surface.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-proxy-logging.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-default-model.nix { inherit pkgs hmConfigDefaultModel; })
// (import ./checks/mlx-catalog-roles.nix {
  inherit
    pkgs
    hmConfigSmallRole
    hmConfigDupRole
    ;
})
// (import ./checks/mlx-harmony.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-cluster.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-sharding.nix { inherit pkgs hmConfigCluster; })
// (import ./checks/mlx-cluster-watcher-env.nix { inherit pkgs hmConfigCluster; })
// (import ./checks/mlx-cluster-peer-env.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-pd-env.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-pd-callsites.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-pd-settle-billing.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-mem-headroom.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-health-gate.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-scripts.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-selfheal.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-recovery.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-peer-armed.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-soak.nix { inherit pkgs src; })
// (import ./checks/litellm-local.nix {
  inherit
    pkgs
    hmConfig
    hmConfigLitellmLocal
    ;
})
// (import ./checks/litellm-local-negative.nix { inherit pkgs mkHmConfig; })
// (import ./checks/litellm-local-scripts.nix { inherit pkgs src; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
