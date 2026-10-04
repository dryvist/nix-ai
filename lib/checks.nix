# Nix quality checks - thin aggregator
# Individual check groups live in lib/checks/{lint,claude,agent-skills,codex,codex-otel,antigravity-cli,mcp,mlx,fabric}.nix
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
  roleMap,
  homebrewFor,
  agentNofile,
}:
let
  inherit (import ./checks-fixtures.nix { inherit pkgs home-manager aiModule; })
    testLocalModelId
    mkHmConfigWith
    mkHmConfig
    hmConfig
    hmConfigUntrusted
    hmConfigOhMyOpenagent
    hmConfigOhMyOpenagentTrusted
    hmConfigAgentSkillsShared
    hmConfigVctCli
    hmConfigFabricServer
    hmConfigCatalog
    hmConfigStaticServing
    hmConfigSmallRole
    hmConfigDupRole
    hmConfigCluster
    hmConfigTokenMeter
    hmConfigTokenMeterLegacy
    hmConfigTokenMeterLegacyDisabled
    hmConfigTokenMeterNoMenu
    hmConfigSessionSync
    hmConfigSessionArchive
    hmConfigLitellmLocal
    hmConfigMcpLaunchPrefix
    ;
  mkHmConfigDarwin =
    (import ./checks-fixtures.nix {
      inherit home-manager aiModule;
      pkgs = import pkgs.path {
        system = "aarch64-darwin";
        config.allowUnfree = true;
      };
    }).mkHmConfig;
in
(import ./checks/lint.nix { inherit pkgs src; })
// (import ./checks/agent-nofile.nix {
  inherit
    pkgs
    src
    mkHmConfig
    mkHmConfigDarwin
    agentNofile
    ;
})
// (import ./checks/zcode-job.nix {
  inherit pkgs;
  hmConfigDarwin = mkHmConfigDarwin [ ];
})
// (import ./checks/token-meter.nix {
  inherit
    pkgs
    src
    hmConfig
    hmConfigTokenMeter
    hmConfigTokenMeterLegacy
    hmConfigTokenMeterLegacyDisabled
    hmConfigTokenMeterNoMenu
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
// (import ./checks/ai-stack.nix { inherit pkgs testLocalModelId roleMap; })
// (import ./checks/mlx-role-map.nix { inherit pkgs roleMap; })
// (import ./checks/ai-stack-endpoint.nix { inherit pkgs; })
// (import ./checks/ai-stack-drift-check.nix { inherit pkgs src; })
// (import ./checks/claude.nix { inherit pkgs hmConfig; })
// (import ./checks/telemetry.nix { inherit pkgs mkHmConfigWith; })
// (import ./checks/codex-otel.nix { inherit pkgs mkHmConfigWith; })
// (import ./checks/opencode-otel.nix { inherit pkgs mkHmConfigWith; })
// (import ./checks/agent-skills-repo-link.nix { inherit pkgs; })
// (import ./checks/agent-skills-groups.nix { inherit pkgs mkHmConfig; })
// (import ./checks/manual-invoke-marking.nix { inherit pkgs src; })
// (import ./checks/mattpocock-skills.nix {
  inherit
    pkgs
    src
    mkHmConfig
    ;
  # opencode.json is one of the artefacts under test.
  hmConfig = hmConfigUntrusted;
})
// (import ./checks/installed-cache-marking.nix { inherit pkgs src; })
// (import ./checks/agent-skills.nix {
  inherit
    pkgs
    hmConfig
    hmConfigAgentSkillsShared
    ;
})
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/fast-delegation.nix { inherit pkgs mkHmConfig; })
// (import ./checks/codex-approvals.nix { inherit pkgs hmConfig mkHmConfig; })
// (import ./checks/cli-ownership.nix { inherit pkgs hmConfig hmConfigUntrusted; })
// (import ./checks/untrusted-clis.nix {
  inherit
    pkgs
    hmConfig
    hmConfigUntrusted
    homebrewFor
    ;
})
// (import ./checks/oh-my-openagent.nix {
  inherit
    pkgs
    hmConfig
    hmConfigUntrusted
    hmConfigOhMyOpenagent
    hmConfigOhMyOpenagentTrusted
    ;
})
// (import ./checks/cursor.nix {
  inherit pkgs;
  hmConfig = hmConfigUntrusted;
})
// (import ./checks/herdr.nix {
  inherit pkgs;
  hmConfig = hmConfigUntrusted;
})
// (import ./checks/qwen-code.nix {
  inherit pkgs;
  hmConfig = hmConfigUntrusted;
})
// (import ./checks/opencode.nix {
  inherit pkgs;
  hmConfig = hmConfigUntrusted;
})
// (import ./checks/antigravity-cli.nix { inherit pkgs hmConfig; })
// (import ./checks/vct-cli.nix {
  inherit
    pkgs
    hmConfig
    hmConfigVctCli
    ;
})
// (import ./checks/mcp.nix { inherit pkgs hmConfig hmConfigMcpLaunchPrefix; })
// (import ./checks/autonomous-profile.nix {
  inherit pkgs;
  render = renderAutonomous;
})
// (import ./checks/mlx.nix { inherit pkgs hmConfig; })
// (import ./checks/mlx-static-serving.nix {
  inherit
    pkgs
    src
    hmConfigStaticServing
    mkHmConfig
    ;
})
// (import ./checks/mlx-catalog-vlm.nix { inherit pkgs src hmConfigCatalog; })
// (import ./checks/mlx-mtp-reachable.nix { inherit pkgs mkHmConfig; })
// (import ./checks/mlx-model-extra-args.nix { inherit pkgs; })
// (import ./checks/mlx-catalog.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-backend-selection.nix { inherit pkgs hmConfigCatalog; })
// (import ./checks/mlx-catalog-roles.nix {
  inherit
    pkgs
    hmConfigSmallRole
    hmConfigDupRole
    ;
})
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
// (import ./checks/litellm-local-launch-prefix.nix { inherit pkgs mkHmConfig; })
// (import ./checks/litellm-local-scripts.nix { inherit pkgs src; })
// (import ./checks/litellm-local-aliases.nix { inherit pkgs hmConfig; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
