# AI shell aliases wiring
#
# Appends AI-tool aliases to programs.zsh.initContent after nix-home's base
# init block. lib.mkAfter ensures these entries load last so any collisions
# with nix-home's aliases.nix win in our favor. The companion nix-home PR
# removes d-claude from that file, but mkAfter keeps us safe
# during the transitional window.

{ lib, ... }:

let
  inherit (import ../vars/ai-stack.nix) doppler;
in
{
  # Non-secret Doppler selectors, exported so the d-* aliases and any
  # hand-run `doppler run` share the single source in vars/ai-stack.nix.
  # Secret values are never exported here — see with-ai-readonly.
  programs.zsh.initContent = lib.mkAfter ''
    export AI_DOPPLER_PROJECT=${lib.escapeShellArg doppler.project}
    export AI_DOPPLER_CONFIG=${lib.escapeShellArg doppler.config}
    source ${./ai-aliases.zsh}
  '';
}
