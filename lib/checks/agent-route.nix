{ pkgs, src }:
{
  agent-route = pkgs.runCommand "check-agent-route" {
    SRC = src;
    nativeBuildInputs = with pkgs; [ bash curl jq coreutils ];
  } ''
    bash ${src}/lib/checks/scripts/agent-route-test.sh
    bash ${src}/lib/checks/scripts/zai-quota-test.sh
    touch $out
  '';
}
