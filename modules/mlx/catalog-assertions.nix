# Catalog assertions, split out of options-catalog.nix.
#
# Extracted for the 12 KB per-file gate, and the split is along a real seam:
# these four are the catalog's CONTRACT (what a selection may not do), while
# what remains in options-catalog.nix is the option schema and the config it
# generates. Nothing here reads anything the caller does not pass.
{
  lib,
  cfg,
  residentWeightGb,
  selectedRoles,
  residents,
}:
[
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
    # Bound kept; its stated reason was wrong until 2026-09-01. It cited the
    # cache-clear trip, which raising util moves further OUT of reach, not
    # into serving load. The bound buys a ceiling on the allocation CAP —
    # the half that protects anything. Bases: ./options-cache.nix.
    assertion = cfg.gpuMemoryUtilization == null || cfg.gpuMemoryUtilization <= 0.85;
    message = ''
      programs.mlx.gpuMemoryUtilization must stay <= 0.85 on catalog hosts —
      the per-worker allocation cap is gpuMemoryUtilization *
      max_recommended_working_set_size, and above 0.85 a single worker may
      claim almost the whole wired ceiling.
    '';
  }
]
