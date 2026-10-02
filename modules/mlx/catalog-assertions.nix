# Catalog assertions, split out of options-catalog.nix.
#
# Extracted for the 12 KB per-file gate, and the split is along a real seam:
# these three are the catalog's CONTRACT (what a selection may not do), while
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
]
