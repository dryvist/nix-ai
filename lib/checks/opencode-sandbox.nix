# OpenCode sandbox regression check: the Seatbelt profile keeps its deny rules,
# and the launcher's environment allowlist names no credential variable.
# The live matrix runs outside Nix; this pins the text the matrix depends on.
{ pkgs }:
let
  inherit (pkgs) lib;
  helpers = import ./helpers.nix { inherit pkgs; };

  profile = builtins.readFile ../../modules/opencode/opencode.sb;
  launcher = builtins.readFile ../../modules/opencode/scripts/launch.sh;

  requiredDenies = [
    ''(global-name "com.apple.SecurityServer")''
    ''(global-name "com.apple.launchservicesd")''
    "(deny lsopen)"
    "(deny appleevent-send)"
    "(deny job-creation)"
    "(deny network-outbound (remote unix-socket))"
    "(deny process-exec (regex #\"/sudo$\"))"
    ".git/(hooks|config)"
    "(\\.envrc|\\.mcp\\.json|opencode\\.json)"
    "(\\.opencode|\\.claude|\\.vscode)"
  ];

  forbiddenEnv = [
    "DOPPLER_"
    "BAO_"
    "VAULT_"
    "OPENBAO_"
    "SSH_AUTH_SOCK"
    "GH_TOKEN"
    "GITHUB_TOKEN"
    "AWS_"
    "ANTHROPIC_API_KEY"
  ];

  missingDenies = builtins.filter (needle: !(lib.hasInfix needle profile)) requiredDenies;
  leakedEnv = builtins.filter (name: lib.hasInfix name launcher) forbiddenEnv;
in
{
  opencode-sandbox-regression =
    assert lib.assertMsg (
      missingDenies == [ ]
    ) "opencode.sb lost deny rules: ${lib.concatStringsSep ", " missingDenies}";
    assert lib.assertMsg (
      leakedEnv == [ ]
    ) "scripts/launch.sh names credential variables: ${lib.concatStringsSep ", " leakedEnv}";
    helpers.mkMarker "check-opencode-sandbox-regression" "OpenCode sandbox keeps its deny rules and env allowlist";
}
