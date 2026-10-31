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
    # Qwen Code reads this file at start and writes it only when absent.
    {
      kind = "literal";
      path = ".qwen/output-language.md";
    }
  ];
  statePaths = [
    ".qwen/history"
    ".qwen/file-history"
    ".qwen/tmp"
  ];
  projectConfigFileRegex = "settings\\.json";
  projectConfigDirRegex = "\\.qwen";
  # The profile denies every write under a `.qwen` directory after the state
  # allows, so the state paths and the language file are re-allowed here.
  appWriteExceptionRule = ''
    (allow file-write*
      (subpath "${home}/.qwen/history")
      (subpath "${home}/.qwen/file-history")
      (subpath "${home}/.qwen/tmp")
      (literal "${home}/.qwen/output-language.md"))'';
  # Forward the router configuration and the facade bridge key.
  inheritedEnv = [
    "OPENAI_API_KEY"
    "OPENAI_BASE_URL"
    "AGENT_FACADE_KEY"
  ];
}
