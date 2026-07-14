# GitHub Copilot CLI User-Prompted Commands (ASK List - REFERENCE ONLY)
#
# IMPORTANT: Copilot CLI does NOT have an "ask" mode in config.json. Tool
# permissions are controlled entirely via --allow-tool / --deny-tool CLI flags.
# This file exists ONLY for reference to keep sync with Claude and Gemini.
#
# FILE STRUCTURE:
# - copilot-permissions-allow.nix - Trusted directories (config.json)
# - copilot-permissions-ask.nix (this file) - Commands that would require confirmation (reference only)
# - copilot-permissions-deny.nix - Recommended --deny-tool flags
#
# NOTE: These permission lists are kept in sync across Claude, Gemini, and Copilot.
# Currently each AI has separate files. Future improvement: DRY refactor to share
# common command lists across all AI tools.
#
# The commands below are the same ones in Claude's askList. They are commented
# out because Copilot doesn't use config-based tool permissions - it's purely
# for documentation and to maintain parity across AI tool configurations.
#
# WARNING: Since Copilot CLI doesn't support config-based "ask" mode, you must
# use --deny-tool flags to block dangerous operations, or simply rely on
# Copilot's default behavior of prompting for approval.

_:

{
  # This file is not imported anywhere - it exists for reference only.
  # The commands below match Claude's askList for consistency.

  # === COMMANDS THAT WOULD REQUIRE CONFIRMATION (if Copilot supported it) ===
  #
  # systemScriptCommands = [
  #   "shell(osascript)"
  #   "shell(osascript -e)"
  # ];
  #
  # systemInfoDisclosureCommands = [
  #   "shell(system_profiler)"
  #   "shell(log show)"
  # ];
  #
  # macosConfigCommands = [
  #   "shell(defaults read)"
  # ];
  #
  # gitDestructiveOperations = [
  #   "shell(git reset)"
  # ];
  #
  # securityOperations = [
  #   "shell(gpg)"
  #   "shell(chown)"
  # ];
  #
  # dangerousFileOperations = [
  #   "shell(chmod)"
  #   "shell(rm)"
  #   "shell(rmdir)"
  #   "shell(cp)"
  #   "shell(mv)"
  #   "shell(sed -i)"
  #   "shell(sed --in-place)"
  # ];
  #
  # dockerPrivilegedOperations = [
  #   "shell(docker exec)"
  #   "shell(docker run)"
  # ];
  #
  # kubernetesDestructiveOperations = [
  #   "shell(kubectl apply)"
  #   "shell(kubectl create)"
  #   "shell(kubectl delete)"
  #   "shell(kubectl set)"
  #   "shell(kubectl patch)"
  #   "shell(helm install)"
  #   "shell(helm upgrade)"
  #   "shell(helm uninstall)"
  # ];
  #
  # awsDestructiveOperations = [
  #   "shell(aws s3 cp)"
  #   "shell(aws s3 sync)"
  #   "shell(aws s3 rm)"
  #   "shell(aws ec2 run-instances)"
  #   "shell(aws ec2 terminate-instances)"
  #   "shell(aws lambda invoke)"
  #   "shell(aws cloudformation delete-stack)"
  # ];
  #
  # opentofuDestructiveOperations = [
  #   "shell(tofu apply)"
  #   "shell(tofu destroy)"
  # ];
  #
  # packageExecutionCommands = [
  #   "shell(npx)"
  # ];
  #
  # databaseModificationCommands = [
  #   "shell(sqlite3)"
  #   "shell(mongosh)"
  # ];
}
