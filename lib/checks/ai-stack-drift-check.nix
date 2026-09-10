# Behavioural test for the ai-stack drift check script.
#
# Same split as lib/checks/litellm-local-scripts.nix: a script that reaches
# real endpoints belongs in its own runCommand check, not folded into a pure
# evaluation check, and keeps that file under the .file-size.yml ceiling too.
{
  pkgs,
  src,
}:
{
  ai-stack-drift-check = pkgs.runCommand "check-ai-stack-drift-check" {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.python3
    ];
  } "bash ${src}/tests/test-ai-stack-drift-check.sh && touch $out";
}
