# The scheduled launchd agent that actually runs the drift check.
#
# Split out of ./default.nix to stay under the .file-size.yml ceiling, and to
# follow the per-module launchd.nix pattern already used by litellm-local,
# fabric and mlx.
#
# WHY THIS AGENT EXISTS AT ALL: modules/scripts/ai-stack-drift-check.sh was the
# only file in modules/scripts with zero references anywhere in this repo —
# no nix file built it, nothing scheduled it, no flake check ran it. A
# converged host can carry a registry whose role names no endpoint can
# address, and with nothing running the check the machine has no opinion
# about it: not green, not red, just silence indistinguishable from health.
# This agent is what turns that silence into either a clean run in the log or
# a signal an operator can act on.
#
# `logDir` is supplied by the caller rather than computed here because
# default.nix must create it during activation — launchd does not create the
# parent of StandardOutPath, and a job whose log directory is missing fails to
# spawn silently. That would leave this check wired but never running, which is
# the exact failure the agent exists to end. One definition, two uses.
{
  config,
  driftCheck,
  logDir,
}:
{
  ai-stack-drift-check = {
    enable = true;
    config = {
      Label = "dev.ai-stack-drift-check";
      ProgramArguments = [ "${driftCheck}/bin/ai-stack-drift-check" ];
      # Not RunAtLoad: the registry only changes when a converge runs, so a
      # check tied to login timing adds runs without adding information — the
      # StartInterval below is the only cadence this needs.
      RunAtLoad = false;
      StartInterval = 3600;
      ProcessType = "Background";
      EnvironmentVariables = {
        # launchd agents get no shell init, so HOME must be set explicitly —
        # the script's registry default (~/.config/ai-stack/registry.json)
        # resolves through it.
        HOME = config.home.homeDirectory;
      };
      StandardOutPath = "${logDir}/drift-check.log";
      StandardErrorPath = "${logDir}/drift-check.error.log";
    };
  };
}
