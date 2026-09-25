# FluidAudio CLI — offline speaker diarization and speech-to-text CLI
# (https://github.com/FluidInference/FluidAudio, Apache-2.0).
#
# Swift/CoreML, Apple Silicon only. Upstream ships no binary release and no
# nixpkgs derivation, and building it inside a sandboxed Nix derivation is not
# viable: `swift build` for this product downloads an ~87 MB xcframework
# binary target straight from GitHub releases mid-build, which a Nix build
# sandbox has no network access to reach. So this installs at home-manager
# activation time instead, outside the sandbox, using the Xcode toolchain's
# own `swift`.
#
# Idempotent: activation compares the currently linked tag against the pin in
# lib/versions.nix and only rebuilds on a mismatch. A failed fetch or build
# warns and leaves the previous working binary in place rather than failing
# the whole `home-manager switch`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.fluidaudio;
  versions = import ../lib/versions.nix;
  tag = "v${versions.fluidAudio}";
  homeDir = config.home.homeDirectory;

  installScript = pkgs.writeShellApplication {
    name = "fluidaudio-cli-install";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
    ];
    text = ''
      TAG="${tag}"
      INSTALL_ROOT="${homeDir}/.local/share/fluidaudio"
      BIN_DIR="${homeDir}/.local/bin"
      BIN_LINK="$BIN_DIR/fluidaudiocli"
      TARGET_DIR="$INSTALL_ROOT/$TAG"
      TARGET_BIN="$TARGET_DIR/fluidaudiocli"
      LOG_FILE="$INSTALL_ROOT/last-build.log"

      current_tag=""
      if [ -L "$BIN_LINK" ]; then
        current_target=$(readlink "$BIN_LINK")
        current_tag=$(basename "$(dirname "$current_target")")
      fi

      if [ "$current_tag" = "$TAG" ] && [ -x "$TARGET_BIN" ]; then
        exit 0
      fi

      if ! command -v swift >/dev/null 2>&1; then
        echo "fluidaudio: no swift toolchain on PATH (install Xcode Command Line Tools); skipping $TAG build" >&2
        exit 0
      fi

      mkdir -p "$INSTALL_ROOT"
      work_dir=$(mktemp -d)
      trap 'rm -rf "$work_dir"' EXIT

      echo "fluidaudio: building $TAG (this can take a couple of minutes and needs network access)" >&2

      if ! git clone --quiet --depth 1 --branch "$TAG" \
        https://github.com/FluidInference/FluidAudio.git "$work_dir/src" >"$LOG_FILE" 2>&1; then
        echo "fluidaudio: failed to fetch $TAG; keeping existing install. Log: $LOG_FILE" >&2
        exit 0
      fi

      if ! (cd "$work_dir/src" && swift build -c release --product fluidaudiocli) >>"$LOG_FILE" 2>&1; then
        echo "fluidaudio: build failed for $TAG; keeping existing install. Log: $LOG_FILE" >&2
        exit 0
      fi

      built_bin="$work_dir/src/.build/release/fluidaudiocli"
      if [ ! -x "$built_bin" ]; then
        echo "fluidaudio: build for $TAG produced no binary; keeping existing install. Log: $LOG_FILE" >&2
        exit 0
      fi

      mkdir -p "$TARGET_DIR" "$BIN_DIR"
      cp "$built_bin" "$TARGET_BIN"
      ln -sfn "$TARGET_BIN" "$BIN_LINK"
      echo "fluidaudio: installed $TAG -> $TARGET_BIN"
    '';
  };
in
{
  options.programs.fluidaudio = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to build and install the FluidAudio CLI (`fluidaudiocli`) —
        an offline speaker diarization and speech-to-text CLI — from the
        pinned release tag in lib/versions.nix. Darwin-only: FluidAudio is a
        Swift/CoreML package built for Apple Silicon.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.fluidaudio.enable requires Darwin (Swift/CoreML, Apple Silicon only).";
      }
    ];

    home.activation.fluidaudioCli = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${lib.getExe installScript}
    '';
  };
}
