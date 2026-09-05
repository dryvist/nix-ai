# `agent-context-baseline` — what a session costs before it does any work.
#
# Reads the first `usage` block of each recent transcript under
# ~/.claude/projects and reports it per repository. That block is the session's
# startup cost: system prompt, instruction chain, skill and agent listings, MCP
# tool names.
#
# Deliberately not a collector, a gauge or a service. The transcripts are
# already on disk, so the measurement needs nothing running — which is what
# makes it usable from any session, in any repo, at any time.
#
# Budget and the reasoning behind it: docs/architecture/agent-context-architecture.md.
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "agent-context-baseline";
      runtimeInputs = [
        pkgs.jq
        pkgs.python3
      ];
      text = ''
        exec ${./scripts/agent-context-baseline.sh} "$@"
      '';
    })
  ];
}
