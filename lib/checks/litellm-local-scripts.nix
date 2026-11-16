# Behavioural tests for the litellm-local fallback probe script.
#
# Separate from ./litellm-local.nix because that file asserts over the RENDERED
# config — a pure evaluation with no I/O — while this one runs the script. It
# also keeps that file under the .file-size.yml ceiling, the same
# split-rather-than-exempt pattern the rest of lib/checks uses.
#
# What it proves: the probe asks LiteLLM not to fall back (without that, a
# request addressed to a dead rung is answered by the next rung and returns
# 200, so the probe reports a chain healthy while a rung is gone), treats
# occupied max_parallel_requests slots (HTTP 429) as BUSY rather than dead,
# and still fails on real errors.
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
