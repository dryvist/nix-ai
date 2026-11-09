# Shared sandbox defaults for module rendering and regression checks.
{
  writableRoots =
    {
      lib,
      homeDirectory,
      isDarwin,
    }:
    [
      "${homeDirectory}/.codex"
      "/Volumes/git"
      "${homeDirectory}/.cache"
    ]
    ++ lib.optional isDarwin "${homeDirectory}/Library/Application Support/git-town";

  networkProxyDomains = [
    "api.github.com"
    "github.com"
    "pypi.org"
    "files.pythonhosted.org"
    "registry.npmjs.org"
    "raw.githubusercontent.com"
    "codeload.github.com"
    "objects.githubusercontent.com"
    "semgrep.dev"
  ];
}
