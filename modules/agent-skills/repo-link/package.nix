# agent-skill-groups — per-repository skill-tree linker driven by AGENTS.md.
{
  writeShellApplication,
  jq,
  git,
  coreutils,
  findutils,
  gawk,
  gnused,
  gnugrep,
}:
writeShellApplication {
  name = "agent-skill-groups";
  runtimeInputs = [
    jq
    git
    coreutils
    findutils
    gawk
    gnused
    gnugrep
  ];
  text = builtins.readFile ./agent-skill-groups.sh;
}
