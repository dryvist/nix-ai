#
# MLX Module — how launchd agents are launched (estate-wide convention)
#
# One option, applied to every agent in this module whose payload is a shell
# script. It exists because of how macOS grants network access, and getting it
# wrong is silent.
#
{ lib, ... }:
{
  options.programs.mlx = {
    appleInterpreter = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/bin/bash";
      description = ''
        Interpreter every shell-script launchd agent in this module is launched
        with. null falls back to each script's own Nix shebang.

        THE CONVENTION, estate-wide: a launchd agent whose payload is a shell
        script is launched as `<interpreter> <script>`, never via the script's
        own Nix shebang.

        WHY. macOS keys a TCC privacy grant to a binary's CODE-SIGNING IDENTITY,
        and a Nix binary's identity IS its content hash:

          nix bash:    designated => cdhash H"51837d11..."
          Apple bash:  designated => identifier "com.apple.bash" and anchor apple

        Every nixpkgs bump therefore mints an executable macOS has never seen,
        and every grant made against the previous one is inert. Store paths are
        content-addressed too, so there is not even a stable path to attach a
        grant to. Apple's binaries key on identifier + authority, independent of
        content — which is why their permissions survive OS updates and ours did
        not.

        NO WRAPPER LAUNDERS THIS. Measured 2026-07-25: a Nix binary launched by a
        PERMITTED Apple parent is still denied, because a Nix binary anywhere in
        the chain becomes the responsible process for everything beneath it.
        That is also why Apple's own /sbin/ping is denied when its parent is a
        Nix bash. Only removing the Nix interpreter from the chain works.

        WHAT IT FIXED. The two-Mac cluster could not self-form for weeks: the
        link watcher's probe was denied and macOS reported "No route to host",
        indistinguishable from a pulled cable. After this change, with NOTHING
        granted to anything, the watcher log read:

          probe to <peer> has failed 380 consecutive tick(s) while down
          cluster-link: down -> up (coordinator)

        REQUIREMENTS, both cheap and both checked rather than assumed:
          - the script is self-contained (helpers concatenated at build time,
            no runtime `source`), so there is one file to launch;
          - it parses under the bash 3.2 Apple ships — no `declare -A`, no
            mapfile/readarray, no ''${var^^} / ''${var,,}.

        DOES NOT APPLY to an agent that execs a non-Apple binary which itself
        does the network work (a Python interpreter, a Go daemon). That binary
        becomes its own responsible process and needs a stable code-signing
        identity instead — see dryvist/nix-darwin's programs.mlxClusterSigning.

        Set to null only if a script genuinely needs bash 5 — and then fix the
        script, because this is what keeps these agents working across rebuilds.
      '';
    };
  };
}
