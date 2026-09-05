# One-owner-per-CLI regression tests.
#
# Three AI CLIs were installed twice on the workstation: a Homebrew cask won
# PATH while Nix built a second, shadowed binary that never ran. The modules
# now name a single owner per platform — Homebrew on darwin for the two CLIs
# that ship several releases a week, llm-agents.nix everywhere else — and these
# checks pin that arrangement.
#
# WHAT THIS FILE CAN AND CANNOT SEE. The suite is scoped to x86_64-linux
# (flake.nix), so every assertion below evaluates the LINUX branch of each
# `if pkgs.stdenv.hostPlatform.isDarwin` conditional. The darwin branch — the
# one that actually removes a binary — is invisible here and is asserted in
# nix-darwin, which evaluates the real host.
#
# These prove the SOURCE, not the freshness. Nix evaluation is pure and has no
# clock, so "is this build recent" cannot be asserted here; that is the weekly
# relock's job.
{ pkgs, hmConfig }:
let
  helpers = import ./helpers.nix { inherit pkgs; };

  # The release channel's builds. Referenced only to assert the modules are NOT
  # using them. nixpkgs 26.05 freezes codex at 0.146.0, opencode at 1.15.10 and
  # qwen-code at 0.16.0, all well behind upstream, and a fall-back is silent:
  # evaluation stays green and the profile just ships an old agent CLI.
  releaseChannelCodex = pkgs.codex;
  releaseChannelOpencode = pkgs.opencode;
  releaseChannelQwenCode = pkgs.qwen-code;

  packageOf =
    pname:
    let
      matches = builtins.filter (
        p: builtins.hasAttr "pname" p && p.pname == pname
      ) hmConfig.config.home.packages;
    in
    if matches == [ ] then null else builtins.head matches;

  installedCodex = packageOf "codex";
  installedOpencode = packageOf "opencode";
  installedQwenCode = packageOf "qwen-code";
in
{
  # Codex and opencode must come from llm-agents.nix on Linux, not from the
  # frozen release channel. Compared by drvPath against `pkgs.X`, the same
  # inversion cursor-ownership-regression uses, so a silent fall-back is red.
  cli-source-regression = helpers.mkDefaultsRegression {
    label = "AI CLI source";
    checkName = "check-cli-source-regression";
    checks = [
      {
        name = "codex is installed on the Linux branch";
        actual = installedCodex != null;
        expected = true;
      }
      {
        name = "codex is not the frozen release-channel build";
        actual = installedCodex.drvPath == releaseChannelCodex.drvPath;
        expected = false;
      }
      {
        name = "opencode is installed on the Linux branch";
        actual = installedOpencode != null;
        expected = true;
      }
      {
        name = "opencode is not the frozen release-channel build";
        actual = installedOpencode.drvPath == releaseChannelOpencode.drvPath;
        expected = false;
      }
      {
        name = "qwen-code is installed";
        actual = installedQwenCode != null;
        expected = true;
      }
      {
        name = "qwen-code is not the frozen release-channel build";
        actual = installedQwenCode.drvPath == releaseChannelQwenCode.drvPath;
        expected = false;
      }
    ];
  };

  # Skipping the binary must never skip the configuration.
  #
  # On darwin both modules set `package = null` so Homebrew owns the binary.
  # The failure mode this guards is a later edit that reaches for `enable`
  # instead — which would drop every settings file, MCP server and permission
  # set along with the binary, leaving a brew-installed CLI with no config at
  # all. `enable` stays true on both platforms; only `package` varies.
  #
  # The option paths are `programs.claude` and `programs.codex`. There is no
  # `programs.claudeCode`, and a check keyed on a nonexistent option is an
  # evaluation error rather than a red check.
  cli-config-survives-null-package = helpers.mkDefaultsRegression {
    label = "AI CLI config ownership";
    checkName = "check-cli-config-survives-null-package";
    checks = [
      {
        name = "programs.claude.enable stays true";
        actual = hmConfig.config.programs.claude.enable;
        expected = true;
      }
      {
        name = "programs.codex.enable stays true";
        actual = hmConfig.config.programs.codex.enable;
        expected = true;
      }
      {
        # Rendered from programs.claude.apiKeyHelper, so it is present only
        # while the module is still configuring Claude Code.
        name = "claude config is still rendered";
        actual = builtins.elem ".local/bin/claude-api-key-helper" (
          builtins.attrNames hmConfig.config.home.file
        );
        expected = true;
      }
      {
        name = "claude rule delivery still happens";
        actual = builtins.elem ".claude/rules/soul.md" (builtins.attrNames hmConfig.config.home.file);
        expected = true;
      }
      {
        name = "codex config.toml activation still exists";
        actual = hmConfig.config.home.activation ? codexConfigMerge;
        expected = true;
      }
    ];
  };
}
