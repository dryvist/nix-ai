# Regression assertions for non-GCP sre-skills wiring and GCP exclusions.
#
# Split out of agent-skills.nix to stay under the per-file size gate.
{
  pkgs,
  hmConfig,
}:
let
  helpers = import ./helpers.nix { inherit pkgs; };
  sourceTable = import ../../modules/agent-skills/sources.nix;
  cfg = hmConfig.config.programs.agentSkills;
  deployedSkillNames = builtins.attrNames cfg.deployedSkillPaths;
  managedSkillEntries = builtins.filter (
    n:
    builtins.match "^\\.codex/skills/[^/]+$" n != null
    && n != ".codex/skills/INDEX.md"
    && n != ".codex/skills/GROUPS.json"
  ) deployedSkillNames;
  groupsData = builtins.fromJSON (
    builtins.unsafeDiscardStringContext hmConfig.config.home.file.".codex/skills/GROUPS.json".text
  );
  sreObservabilitySkills = [
    "anomaly-detection"
    "data-ingestion"
    "generic-mitigations"
    "monitoring-graphs"
    "postmortem-aggregator"
    "postmortem-generator"
  ];
  excludedGcpSreSkills = [
    "cloud-logging"
    "cloud-monitoring"
    "gcp-architecture-discovery"
    "gcp-mcp-setup"
    "gcp-playbooks"
    "gcp-setup"
    "gcp-slo-management"
    "investigation-entrypoint"
    "safe-sre-investigator"
  ];
in
{
  agent-skills-sre =
    assert
      builtins.all (name: cfg.local ? ${name}) sourceTable.sre-skills.skills
      || throw "Non-GCP sre-skills entries missing from programs.agentSkills.local";
    assert
      builtins.elem ".codex/skills/pre-publish-checker" managedSkillEntries
      || throw "pre-publish-checker skill not deployed in active review group";
    assert
      builtins.all (
        name:
        (groupsData.observability or { }) ? ${name}
        && !(builtins.elem ".codex/skills/${name}" managedSkillEntries)
      ) sreObservabilitySkills
      || throw "SRE observability skills must be opt-in in GROUPS.json.observability, not globally deployed";
    assert
      builtins.all (
        name:
        !(cfg.local ? ${name})
        && !(builtins.elem ".codex/skills/${name}" managedSkillEntries)
        && !((groupsData.observability or { }) ? ${name})
      ) excludedGcpSreSkills
      || throw "GCP-focused skills from sre-skills must not be wired or deployed";
    helpers.mkMarker "check-agent-skills-sre" "Non-GCP sre-skills mapped and GCP-focused skills excluded";
}
