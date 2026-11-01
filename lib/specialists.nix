# Specialist subagents. One entry renders one Claude Code agent file and one
# Codex role, registered in Codex config.toml under [agents.<name>].
#
# `owns` names the MCP servers only this specialist may load. Owned servers are
# removed from every shared harness profile and render only into their owner's
# agent, and an entry renders only once every server it owns is enabled.
#
# `model` is the Claude model alias. Codex roles take no model: the Luna id is
# resolved at runtime from Codex's own model cache, not pinned here.
[
  {
    name = "vikunja-specialist";
    description = "Sole owner of the Vikunja task tracker: finds, files, labels, relates, comments on and completes Vikunja tasks, verifying every write by readback. Delegate all Vikunja work here.";
    model = "haiku";
    prompt = "applications/vikunja-specialist.md";
    owns = [ "vikunja" ];
  }
  {
    name = "github-specialist";
    description = "GitHub specialist, tier 1 only: reads repos/PRs/checks, comments, reruns CI and merges on green via gh with a per-repo write token from openbao-github-creds. Repo creation, settings, rulesets and App installs are out of scope and fail closed.";
    model = "haiku";
    prompt = "auto-ai-agent/github-specialist.md";
    owns = [ ];
    tools = [
      "Bash"
      "Read"
      "Grep"
      "Glob"
    ];
  }
]
