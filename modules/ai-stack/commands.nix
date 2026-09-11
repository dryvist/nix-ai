# Executable wrapper for the ai-stack drift check.
#
# Split out of ./default.nix to stay under the .file-size.yml ceiling — the
# same split-rather-than-exempt pattern modules/litellm-local uses for its own
# commands.nix, and for the same reason: an executable belongs in a file
# grouped by "produces something runnable", not folded into the module that
# defines the registry it checks.
{
  pkgs,
  lib,
  aiStack,
}:
let
  # Known at eval time, not at exec time: the option is either set or it
  # isn't, so the choice belongs here rather than behind a runtime shell
  # guard. Absent, the wrapper sets nothing — the script's own header notes
  # that an unset LLM_ROUTER_TOKEN_FILE degrades to "router UNREACHABLE",
  # which is correct behaviour for a host with no router configured. Forcing
  # the option to be set here would turn that degrade into a hard build
  # error for a host that has no router to check against.
  tokenFile = aiStack.llmEndpointTokenFile;
in
{
  ai-stack-drift-check = pkgs.writeShellApplication {
    name = "ai-stack-drift-check";
    # coreutils for `mktemp`/`rm` (the script's scratch dir), same as
    # litellm-fallback-watch adds it for the same reason its sibling probe
    # does not: writeShellApplication only puts runtimeInputs on PATH, and a
    # launchd agent's PATH cannot be assumed to already carry them.
    runtimeInputs = [
      pkgs.curl
      pkgs.python3
      pkgs.coreutils
    ];
    text =
      if tokenFile != null then
        ''
          LLM_ROUTER_TOKEN_FILE=${lib.escapeShellArg tokenFile} \
            exec ${./../scripts/ai-stack-drift-check.sh} "$@"
        ''
      else
        ''
          exec ${./../scripts/ai-stack-drift-check.sh} "$@"
        '';
  };
}
