{ pkgs, lib }:
{
  qwen,
  home,
  workRoot,
  localPorts ? [ ],
}:
import ../opencode/sandbox.nix { inherit pkgs lib; } {
  package = qwen;
  inherit home workRoot localPorts;
  binaryName = "qwen";
  # Settings and deployed skills are read-only; the rest of ~/.qwen (credentials
  # included) stays denied by default.
  readRules = [
    {
      kind = "literal";
      path = ".qwen/settings.json";
    }
    {
      kind = "subpath";
      path = ".qwen/skills";
    }
  ];
  statePaths = [
    ".qwen/history"
    ".qwen/file-history"
    ".qwen/tmp"
  ];
  projectConfigFileRegex = "settings\\.json";
  projectConfigDirRegex = "\\.qwen";
  appWriteExceptionRule = "";
  # The router bearer and base URL are the only caller-shell values it receives.
  inheritedEnv = [
    "OPENAI_API_KEY"
    "OPENAI_BASE_URL"
  ];
}
