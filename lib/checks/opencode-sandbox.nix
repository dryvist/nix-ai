# OpenCode sandbox regression check: the Seatbelt profile keeps its deny rules,
# the launcher keeps its standalone-clone refusal and per-run temp directory, and
# the launcher's environment allowlist names no credential variable.
# The live probes in tests/test-opencode-sandbox-escape.sh run on macOS; this pins the
# text they depend on.
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
    ''(deny network-outbound (remote ip "localhost:*"))''
    "(deny process-exec (regex #\"/sudo$\"))"
    ''(regex #"/\.git$")''
    ''/\.git[^/]*/((modules|worktrees)/[^/]+/)*(hooks|config(\.worktree)?)(/|$)''
    "(deny file-link)"
    ''(\.envrc|\.mcp\.json|opencode\.json|CLAUDE\.md|AGENTS\.md|GEMINI\.md)''
    ''(\.opencode|\.claude|\.vscode|\.cursor)''
  ];

  requiredLauncher = [
    "linked worktree"
    "outside the work root"
    ''mktemp -d "$cache_dir/tmp.XXXXXX"''
    ''trap 'rm -rf "$tmpdir"' EXIT''
  ];

  # The git common directory is inside the worktree, so no separate grant exists.
  forbiddenGrants = [ "GIT_COMMON" ];

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
  missingLauncher = builtins.filter (needle: !(lib.hasInfix needle launcher)) requiredLauncher;
  leakedGrants = builtins.filter (needle: lib.hasInfix needle (profile + launcher)) forbiddenGrants;
  leakedEnv = builtins.filter (name: lib.hasInfix name launcher) forbiddenEnv;
in
{
  opencode-sandbox-regression =
    assert lib.assertMsg (
      missingDenies == [ ]
    ) "opencode.sb lost deny rules: ${lib.concatStringsSep ", " missingDenies}";
    assert lib.assertMsg (
      missingLauncher == [ ]
    ) "scripts/launch.sh lost guards: ${lib.concatStringsSep ", " missingLauncher}";
    assert lib.assertMsg (
      leakedGrants == [ ]
    ) "a separate git grant is back: ${lib.concatStringsSep ", " leakedGrants}";
    assert lib.assertMsg (
      leakedEnv == [ ]
    ) "scripts/launch.sh names credential variables: ${lib.concatStringsSep ", " leakedEnv}";
    helpers.mkMarker "check-opencode-sandbox-regression" "OpenCode sandbox keeps its deny rules, guards, and env allowlist";
}
