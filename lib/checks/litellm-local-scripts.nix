# Behavioural tests for the two shipped litellm-local shell scripts.
#
# Separate from ./litellm-local.nix because that file asserts over the RENDERED
# config — a pure evaluation with no I/O — while this one runs the scripts. It
# also keeps that file under the .file-size.yml ceiling, the same
# split-rather-than-exempt pattern the rest of lib/checks uses.
#
# What it proves: the probe asks LiteLLM not to fall back (without that, a
# request addressed to a dead rung is answered by the next rung and returns
# 200, so the probe reports a chain healthy while a rung is gone), and the
# watcher's state-file reader always yields an integer (a state file holding
# `08` aborted the whole watcher on invalid octal, freezing the streak so it
# could never page).
{
  pkgs,
  src,
}:
{
  litellm-fallback-scripts = pkgs.runCommand "check-litellm-fallback-scripts" {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.python3
    ];
  } "bash ${src}/tests/test-litellm-fallback-scripts.sh && touch $out";
}
