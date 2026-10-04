{
  pkgs,
  src,
  mkHmConfig,
  mkHmConfigDarwin,
  agentNofile,
}:
let
  limitsFor =
    mkConfig: nofile:
    let
      hm = mkConfig [ { _module.args.agentNofile = pkgs.lib.mkForce nofile; } ];
      installed = builtins.head (
        builtins.filter (p: p.name == "agent-cli-launchers") hm.config.home.packages
      );
      wrappers = installed.launchers;
    in
    assert builtins.length wrappers == 3;
    assert builtins.all (
      wrapper: pkgs.lib.hasInfix "ulimit -S -n ${toString nofile} || exit 1" wrapper.text
    ) wrappers;
    assert builtins.all (
      wrapper: pkgs.lib.hasInfix "ulimit -H -n ${toString nofile} || exit 1" wrapper.text
    ) wrappers;
    assert builtins.elem "${installed}/bin" hm.config.home.sessionPath;
    assert pkgs.lib.hasInfix
      "export PATH=${pkgs.lib.escapeShellArg (builtins.unsafeDiscardStringContext "${installed}/bin")}:\"$PATH\""
      hm.config.programs.zsh.initContent;
    true;
in
{
  agent-nofile =
    assert limitsFor mkHmConfig agentNofile;
    assert limitsFor mkHmConfig (agentNofile + 1);
    assert limitsFor mkHmConfigDarwin agentNofile;
    assert limitsFor mkHmConfigDarwin (agentNofile + 1);
    pkgs.runCommand "check-agent-nofile-launchers" { } ''
      touch "$out"
    '';
  agent-nofile-no-literals = pkgs.runCommand "check-agent-nofile-no-literals" { } ''
    if grep -nE '(agentNofile|nofile|ulimit).*[0-9]' ${src}/modules/agent-launchers.nix; then
      echo "consumer defines a numeric file limit" >&2
      exit 1
    fi
    touch "$out"
  '';
}
