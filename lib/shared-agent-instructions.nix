{ lib, instructions }:

let
  operatingCore = builtins.readFile "${instructions}/agentsmd/rules/operating-core.md";
  monitoringRule = builtins.filter (
    line: lib.hasInfix "Check system state with monitoring first;" line
  ) (lib.splitString "\n" operatingCore);
in
assert builtins.length monitoringRule == 1;
builtins.readFile "${instructions}/AGENTS.md" + "\n" + builtins.head monitoringRule + "\n"
