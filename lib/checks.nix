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
  # Placeholder physical model id for regression tests. The real value is
  # sourced by consumers (nix-darwin) from AI_MODEL_LOCAL_LLM; tests only need
  # a valid non-empty mlx-community/* string to populate services.aiStack and
  # exercise lib/ai-stack-models.nix (a function since the role registry was
  # parameterized).
  testLocalModelId = "mlx-community/test-model";

  # Shared test module configuration — used by claude, mlx, and fabric regression checks
  baseTestModule = {
    _module.args.userConfig = {
      user.fullName = "JacobPEvans";
    };
    services.aiStack.defaultLocalModelId = testLocalModelId;
    home = {
      username = "test-user";
      homeDirectory = "/home/test-user";
      stateVersion = "25.11";
    };
  };

  mkHmConfig =
    extraModules:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        aiModule
        baseTestModule
      ]
      ++ extraModules;
    };

  hmConfig = mkHmConfig [ ];

  hmConfigAgentSkillsShared = mkHmConfig [
    {
      programs.agentSkills.root = "agents";
    }
  ];

  hmConfigVctCli = mkHmConfig [
    {
      programs.vctCli.enable = true;
    }
  ];

  # Second evaluation with fabric REST API LaunchAgent enabled — used by the
  # fabric-launchd positive check (default eval has enableServer = false).
  hmConfigFabricServer = mkHmConfig [ { programs.fabric.enableServer = true; } ];

  # Third evaluation exercising programs.mlx.catalog (lib/checks/mlx.nix
  # mlx-catalog): a server-like selection plus one direct host override that
  # must beat the catalog's mkDefault.
  hmConfigCatalog = mkHmConfig [
    {
      programs.mlx = {
        catalog = {
          qwen35-9b-optiq = {
            class = "swap";
          };
          qwen38-27b = {
            class = "resident";
            roles = [ "goal-judge" ];
          };
          qwen36-optiq.class = "resident";
          qwen3-coder-30b.class = "resident";
          gpt-oss-120b.class = "swap";
          qwen3-next-80b = {
            class = "swap";
            tweaks.ttl = 600;
          };
          # Carries an intrinsic proxy concurrencyLimit=1 (metal::malloc under
          # concurrency) — exercises modelConcurrencyLimits compilation.
          qwen3-next-80b-instruct.class = "swap";
          # Vision-language entry: exercises the per-model backend override
          # (catalog `backend` -> modelBackends -> mlx_vlm.server) while the
          # host backend stays mlx-lm for every other model.
          unlimited-ocr = {
            class = "swap";
            tweaks.ttl = 600;
          };
        };
        # Direct host setting on a catalog-managed key must win over the catalog.
        modelFlagOverrides."mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit".cacheMemoryMb = 8192;
      };
    }
  ];

  # Evaluation exercising programs.mlx.defaultModelKey (lib/checks/
  # mlx-default-model.nix): the declared default is one catalog entry, the
  # runtime override re-points it at another — the two-Mac shape where the
  # serving config is shared and only this key differs.
  hmConfigDefaultModel = mkHmConfig [
    {
      programs.mlx = {
        defaultModelKey = "qwen38-27b";
        catalog = {
          qwen38-27b.class = "resident";
          qwen36-35b = {
            class = "resident";
            roles = [ "goal-judge" ];
          };
        };
      };
    }
  ];

  # Two evaluations for the role-registry check (lib/checks/mlx-catalog-roles.nix).
  # The first binds the `small` role to a swap-class entry; the second assigns
  # one role name to two enabled entries, so the uniqueness assertion must come
  # back false. Kept out of hmConfigCatalog so the duplicate case cannot leak
  # into the checks that read that fixture.
  #
  # Both set programs.mlx.judge.model even though the judge stays disabled: the
  # check locates assertions by matching their `message`, and the judge
  # assertion's message interpolates that option, which has no default.
  judgeModelStub.programs.mlx.judge.model = "mlx-community/test-judge-model";
  hmConfigSmallRole = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.catalog = {
        qwen38-27b.class = "resident";
        qwen35-9b-optiq = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];
  hmConfigDupRole = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.catalog = {
        qwen38-27b = {
          class = "resident";
          roles = [ "small" ];
        };
        qwen35-9b-optiq = {
          class = "swap";
          roles = [ "small" ];
        };
      };
    }
  ];

  # Fourth evaluation exercising programs.mlx.clusterMode as the coordinator
  # (lib/checks/mlx-cluster.nix): rank env contract, watcher wiring, prefetch.
  # judgeModelStub rides along because lib/checks/mlx-cluster-sharding.nix reads
  # this config's `assertions` list, and the judge assertion's message
  # interpolates an option carrying no default — the same reason the role
  # fixtures above carry it.
  hmConfigCluster = mkHmConfig [
    judgeModelStub
    {
      programs.mlx.clusterMode = {
        enable = true;
        role = "coordinator";
        modelCatalogKey = "glm47-reap50";
        # glm4_moe is pipeline-only; the clusterMode assertions now reject
        # tensor-parallel on it, so this fixture must name the real mode.
        shardingMode = "pipeline";
        wiredLimitMb = 90000;
        standaloneWiredLimitMb = 118000;
      };
    }
  ];
  # Fifth evaluation exercising the token-meter HTTPS gate (lib/checks/
  # token-meter.nix): the module is off by default, so the agent only exists here.
  hmConfigTokenMeter = mkHmConfig [
    {
      programs.token-meter = {
        enable = true;
        bindAddress = "127.0.0.1";
      };
    }
  ];
  # Sixth evaluation exercising the session-sync agent (lib/checks/
  # session-sync.nix): also off by default, so the agent only exists here.
  hmConfigSessionSync = mkHmConfig [
    {
      programs.sessionSync = {
        enable = true;
        remote = "peer.example";
      };
    }
  ];
  # Seventh evaluation exercising the session-archive agent (lib/checks/
  # session-archive.nix): also off by default, so the agent only exists here.
  hmConfigSessionArchive = mkHmConfig [
    {
      programs.sessionArchive = {
        enable = true;
        endpoint = "https://example.invalid";
      };
    }
  ];
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
// (import ./checks/agent-skills.nix {
  inherit
    pkgs
    hmConfig
    hmConfigAgentSkillsShared
    ;
})
// (import ./checks/codex.nix { inherit pkgs hmConfig; })
// (import ./checks/cursor.nix { inherit pkgs hmConfig; })
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
// (import ./checks/mlx-single-model.nix { inherit pkgs src; })
// (import ./checks/mlx-bash32.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-watchdog.nix { inherit pkgs src; })
// (import ./checks/mlx-wedge-detect.nix { inherit pkgs src; })
// (import ./checks/mlx-worker-reap.nix { inherit pkgs hmConfig src; })
// (import ./checks/mlx-warmup.nix { inherit pkgs src; })
// (import ./checks/mlx-model-extra-args.nix { inherit pkgs; })
// (import ./checks/mlx-catalog.nix { inherit pkgs hmConfigCatalog; })
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
// (import ./checks/mlx-cluster-mem-headroom.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-health-gate.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-scripts.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-pd-settle-billing.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-peer-armed.nix { inherit pkgs hmConfigCluster src; })
// (import ./checks/mlx-cluster-soak.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-selfheal.nix { inherit pkgs src; })
// (import ./checks/mlx-cluster-recovery.nix { inherit pkgs src; })
// (import ./checks/litellm-local.nix { inherit pkgs hmConfig; })
// (import ./checks/fabric.nix {
  inherit
    pkgs
    hmConfig
    hmConfigFabricServer
    src
    ;
})
