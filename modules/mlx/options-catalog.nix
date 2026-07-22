#
# MLX Module — validated model catalog (programs.mlx.catalog)
#
# The catalog is the DRY boundary between nix-ai (owns HOW a model is served:
# parser stack, chat-template kwargs, per-class flag profiles — catalog-data.nix)
# and host config (owns WHICH entries run, in which class, plus a few
# type-bounded tweaks). Detailed serve args in a host file are a smell; add or
# fix them here instead.
#
# Compilation targets the existing per-model surfaces, so the catalog composes
# with (and can be overridden by) direct host settings:
#   entry args         -> modelExtraArgs.<physical id>        (mkDefault)
#   class flag profile -> modelFlagOverrides.<physical id>    (mkDefault per key)
#   class == "swap"    -> models.<physical id> (llama-swap swap-tier entry)
#   selection roles     -> services.aiStack.roleOverrides.<role>
# Hosts assign logical roles to catalog entries without repeating physical IDs.
#
{ config, lib, ... }:
let
  cfg = config.programs.mlx;
  catalogData = import ./catalog-data.nix;

  enabled = lib.filterAttrs (_: sel: sel.enable) cfg.catalog;

  entryFor =
    name:
    catalogData.${name} or (throw ''
      programs.mlx.catalog."${name}": unknown catalog entry.
      Known entries: ${lib.concatStringsSep ", " (lib.attrNames catalogData)}
    '');

  profileFor =
    name: sel:
    let
      entry = entryFor name;
    in
    entry.classes.${sel.class}.flags or (throw ''
      programs.mlx.catalog."${name}": class "${sel.class}" is not offered by
      this entry (offered: ${lib.concatStringsSep ", " (lib.attrNames entry.classes)}).
      A class must be validated on real hardware before the catalog offers it.
    '');

  # Bounded host tweaks (non-null only) merge over the validated class profile.
  # ttl is proxy/idle lifecycle, not a serve flag — pulled out separately.
  flagsFor =
    name: sel:
    profileFor name sel
    // lib.filterAttrs (k: v: k != "ttl" && v != null) sel.tweaks
    // lib.optionalAttrs (sel.class == "swap" && sel.tweaks.ttl != null) {
      autoUnloadIdleSeconds = sel.tweaks.ttl;
    };

  swapTtlFor =
    name: sel:
    if sel.tweaks.ttl != null then
      sel.tweaks.ttl
    else
      (profileFor name sel).autoUnloadIdleSeconds or 900;

  residents = lib.filterAttrs (_: sel: sel.class == "resident") enabled;
  swaps = lib.filterAttrs (_: sel: sel.class == "swap") enabled;

  # Physical ids already served by the role registry (services.aiStack.models).
  # A swap-class entry that is ALSO role-registered (e.g. gpt-oss owning the
  # "default" role but demoted from preload) must keep its single registry
  # backend — emitting a models.<id> entry too would collide in llama-swap's
  # model table and clobber the alias/useModelName wiring. Its args therefore
  # travel via modelExtraArgs and its swap profile via modelFlagOverrides.
  registryPhysicals = lib.attrValues config.services.aiStack.models;
  isRegistry = name: lib.elem (entryFor name).model registryPhysicals;

  argsViaExtraArgs = residents // lib.filterAttrs (name: _: isRegistry name) swaps;
  swapsNonRegistry = lib.filterAttrs (name: _: !(isRegistry name)) swaps;

  residentWeightGb = lib.foldl' (acc: name: acc + (entryFor name).weightGb) 0.0 (
    lib.attrNames residents
  );
  catalogRoleOverrides = lib.foldl' (
    acc: name: acc // lib.genAttrs enabled.${name}.roles (_role: (entryFor name).model)
  ) { } (lib.attrNames enabled);
  selectedRoles = lib.concatMap (name: enabled.${name}.roles) (lib.attrNames enabled);
in
{
  options.programs.mlx = {
    catalog = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this catalog entry is compiled into the serving config.";
            };
            class = lib.mkOption {
              type = lib.types.enum [
                "resident"
                "swap"
              ];
              description = "Validated serving class: resident (preload-capable brain, big caps) or swap (on-demand, idle-unloaded, small caps). The entry must offer the class.";
            };
            roles = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Logical AI-stack roles served by this catalog entry. The catalog resolves the physical model ID.";
            };
            tweaks = {
              cacheMemoryMb = lib.mkOption {
                type = lib.types.nullOr (lib.types.ints.between 1024 32768);
                default = null;
                description = "Override the class profile's KV-cache budget (MB), within safe bounds.";
              };
              maxNumSeqs = lib.mkOption {
                type = lib.types.nullOr (lib.types.ints.between 1 16);
                default = null;
                description = "Override the class profile's continuous-batch width, within safe bounds.";
              };
              maxRequestTokens = lib.mkOption {
                type = lib.types.nullOr (lib.types.ints.between 4096 131072);
                default = null;
                description = "Override the class profile's per-request token ceiling, within safe bounds.";
              };
              ttl = lib.mkOption {
                type = lib.types.nullOr (lib.types.ints.between 300 3600);
                default = null;
                description = "Swap-class only: idle seconds before unload (both llama-swap ttl and worker --auto-unload-idle-seconds).";
              };
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          qwen36-optiq.class = "resident";
          qwen3-coder-30b.class = "resident";
          gpt-oss-120b.class = "swap";
          qwen3-next-80b = {
            class = "swap";
            tweaks.ttl = 600;
          };
        }
      '';
      description = "Validated-model catalog selections. Keys name entries in modules/mlx/catalog-data.nix; the catalog owns parser stacks and per-class flag profiles, the host only picks entries, classes, and bounded tweaks.";
    };

    residentWeightBudgetGb = lib.mkOption {
      type = lib.types.numbers.between 10 120;
      default = 70;
      description = "Eval-time ceiling on the summed 4-bit weight footprint of resident-class catalog entries. Guards against scheduling a resident set whose weights alone crowd out KV caches and the OS working set.";
    };
  };

  config = lib.mkIf (cfg.enable && enabled != { }) {
    assertions = [
      {
        assertion = residentWeightGb <= cfg.residentWeightBudgetGb;
        message = ''
          programs.mlx.catalog: resident-class weights sum to ${toString residentWeightGb} GB,
          exceeding residentWeightBudgetGb = ${toString cfg.residentWeightBudgetGb}.
          Demote an entry to class = "swap" or raise the budget deliberately.
        '';
      }
      {
        assertion = lib.length selectedRoles == lib.length (lib.unique selectedRoles);
        message = "programs.mlx.catalog: each logical role may be assigned to only one enabled catalog entry.";
      }
      {
        # ttl is lifecycle for on-demand models; residents ignore it (they
        # follow proxy.idleTtl), so a resident ttl tweak would be a silent
        # no-op misconfiguration.
        assertion = lib.all (name: residents.${name}.tweaks.ttl == null) (lib.attrNames residents);
        message = ''
          programs.mlx.catalog: tweaks.ttl is only meaningful on class = "swap"
          entries — resident-class models follow programs.mlx.proxy.idleTtl.
          Remove the ttl tweak from the resident entr(y/ies) or demote them.
        '';
      }
      {
        assertion = cfg.gpuMemoryUtilization == null || cfg.gpuMemoryUtilization <= 0.85;
        message = ''
          programs.mlx.gpuMemoryUtilization must stay <= 0.85 on catalog hosts —
          above that the Metal cache-clear trip sits inside normal serving load.
        '';
      }
    ];

    programs.mlx = {
      # Registry models (residents + role-registered swaps) read
      # modelExtraArgs; non-registry swap args travel on the models.<id>
      # entry instead. mkDefault everywhere: a direct host setting on the
      # same physical id wins over the catalog.
      modelExtraArgs = lib.mapAttrs' (
        name: _sel: lib.nameValuePair (entryFor name).model (lib.mkDefault (entryFor name).args)
      ) argsViaExtraArgs;

      modelServer = lib.mapAttrs' (
        name: _sel: lib.nameValuePair (entryFor name).model (lib.mkDefault (entryFor name).server)
      ) (lib.filterAttrs (name: _sel: ((entryFor name).server or "vllm-mlx") != "vllm-mlx") enabled);

      modelFlagOverrides = lib.mapAttrs' (
        name: sel:
        lib.nameValuePair (entryFor name).model (lib.mapAttrs (_: lib.mkDefault) (flagsFor name sel))
      ) enabled;

      # A catalog entry may pin a proxy-side concurrency cap (e.g. the 80B that
      # aborts under parallel dispatch). Compile it to the per-physical-id
      # override; mkDefault so a direct host setting still wins.
      modelConcurrencyLimits = lib.mapAttrs' (
        name: _sel: lib.nameValuePair (entryFor name).model (lib.mkDefault (entryFor name).concurrencyLimit)
      ) (lib.filterAttrs (name: _sel: (entryFor name) ? concurrencyLimit) enabled);

      models = lib.mapAttrs' (
        name: sel:
        lib.nameValuePair (entryFor name).model (
          lib.mkDefault {
            ttl = swapTtlFor name sel;
            # The swap-tier cmd builder raw-concatenates extraArgs, so quote
            # each token here (JSON kwargs contain shell metacharacters).
            extraArgs = map lib.escapeShellArg (entryFor name).args;
          }
        )
      ) swapsNonRegistry;
    };

    services.aiStack.roleOverrides = lib.mapAttrs (
      _role: model: lib.mkDefault model
    ) catalogRoleOverrides;
  };
}
