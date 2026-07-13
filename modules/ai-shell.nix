# AI shell aliases wiring
#
# Appends AI-tool aliases to programs.zsh.initContent after nix-home's base
# init block. lib.mkAfter ensures these entries load last so any collisions
# with nix-home's aliases.nix win in our favor. The companion nix-home PR
# removes d-claude from that file, but mkAfter keeps us safe
# during the transitional window.

{ lib, ... }:

{
  programs.zsh.initContent = lib.mkAfter ''
    source ${./ai-aliases.zsh}
  '';
}
