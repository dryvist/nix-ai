# Claude Code — directories Claude Code is allowed to access without per-prompt approval.
#
# Imported as a plain list by claude-config.nix into
# `programs.claude.settings.additionalDirectories`. Keeping this in its own
# file means adding a new trusted path is a one-line PR with no surrounding
# config noise. Personal paths belong in `userConfig.extraTrustedPaths`
# (maintainer profile), which claude-config.nix appends to this base set.
[
  "~/.claude/"
  "~/.config/direnv/"
  "~/.config/fabric/"
  "~/.config/gh/"
  "~/.config/git/"
  "~/.config/mlx/"
  "~/.config/nix/"
  "/tmp/"
]
