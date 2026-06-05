# Routines: Scheduled AI Routine Tasks via launchd
#
# Creates macOS launchd agents that run AI CLI tools (Gemini, Claude) on a
# schedule with a configured prompt. Each task:
#   - Deploys its prompt to ~/.routines/prompts/<name>.md
#   - Creates a launchd agent: com.routines.<name>
#   - Logs stdout to ~/.routines/logs/<name>.log
#   - Logs stderr to ~/.routines/logs/<name>.err
#
# Options defined in: ./options.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.routines;
  homeDir = config.home.homeDirectory;
  logDir = "${homeDir}/${cfg.logDir}";
  promptsDir = "${homeDir}/${cfg.promptsDir}";

  # Convert {hour, minute} attrset to launchd StartCalendarInterval entry
  mkCalendarInterval = time: {
    Hour = time.hour;
    Minute = time.minute;
  };

  enabledTasks = lib.filterAttrs (_: task: task.enabled) cfg.tasks;

  # Build the run command for a task based on its AI tool
  mkRunCommand =
    name: task:
    let
      promptFile = "${promptsDir}/${name}.md";
      modelFlag = lib.optionalString (task.model != null) "--model ${lib.escapeShellArg task.model}";
    in
    if task.aiTool == "antigravity-cli" then
      "agy -p \"$(cat '${promptFile}')\" ${modelFlag}"
    else
      # Claude: use --print flag for non-interactive output
      "claude --print ${modelFlag} < '${promptFile}'";

  # Generate a runner script for a task
  # Runner scripts live in the Nix store (not ~/.routines); the launchd agent
  # references them by their store path via ProgramArguments.
  mkRunnerScript =
    name: task:
    let
      logFile = "${logDir}/${name}.log";
      errFile = "${logDir}/${name}.err";
      runCmd = mkRunCommand name task;
    in
    pkgs.writeShellScript "routine-${name}" ''
      set -uo pipefail

      mkdir -p '${logDir}'

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] ${name}: $2" >> '${logFile}'
      }

      log "START" "routine triggered"

      EXIT_CODE=0
      ${runCmd} >> '${logFile}' 2>> '${errFile}' || EXIT_CODE=$?

      if [[ $EXIT_CODE -eq 0 ]]; then
        log "END" "completed successfully"
      else
        log "END" "failed with exit code $EXIT_CODE"
      fi

      exit $EXIT_CODE
    '';

in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: task: {
      assertion = task.schedule.times != [ ];
      message = "programs.routines.tasks.${name} must set schedule.times when enabled";
    }) enabledTasks;

    home.file =
      # Deploy prompt files
      lib.mapAttrs' (
        name: task:
        lib.nameValuePair "${cfg.promptsDir}/${name}.md" {
          text = task.prompt;
        }
      ) enabledTasks;

    # Create launchd agents for each enabled task
    launchd.agents = lib.mapAttrs' (
      name: task:
      lib.nameValuePair "com.routines.${name}" {
        enable = true;
        config = {
          Label = "com.routines.${name}";
          # Inherit Full Disk Access from Ghostty via TCC association
          AssociatedBundleIdentifiers = [ "com.mitchellh.ghostty" ];
          ProgramArguments = [ "${mkRunnerScript name task}" ];
          StartCalendarInterval = map mkCalendarInterval task.schedule.times;
          WorkingDirectory = task.workingDirectory;
          EnvironmentVariables = {
            HOME = homeDir;
            # gh CLI auth via config directory (token in ~/.config/gh/hosts.yml)
            GH_CONFIG_DIR = "${homeDir}/.config/gh";
            # SSH batch mode: accept-new allows first connection to known CI hosts
            # without interactive prompts while still rejecting changed keys
            GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new";
            # Full PATH: per-user Nix profile + Homebrew (Apple Silicon) + system paths
            PATH = "${config.home.profileDirectory}/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          };
        };
      }
    ) enabledTasks;
  };
}
