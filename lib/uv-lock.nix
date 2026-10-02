# The MLX serving stack as resolved in mlx-server/uv.lock.
#
# mlx-server/pyproject.toml pins the stack; uv.lock records each resolved
# version with the URL and sha256 of every published artifact. Renovate's
# pep621 manager edits the pin and regenerates the lock in one commit, so
# every version and hash below moves without a hand-edited row anywhere.
#
# Pure: no pkgs. lib/versions.nix imports it for versions; the derivations
# that fetch artifacts pass the records returned here to fetchurl.
let
  lock = builtins.fromTOML (builtins.readFile ../mlx-server/uv.lock);
  byName = builtins.listToAttrs (
    map (p: {
      inherit (p) name;
      value = p;
    }) lock.package
  );
  package =
    name:
    byName.${name}
      or (throw "lib/uv-lock.nix: ${name} is not in mlx-server/uv.lock. Add it to mlx-server/pyproject.toml and run `uv lock`.");

  # fetchurl arguments for one uv.lock artifact record.
  fetchArgs = artifact: {
    inherit (artifact) url;
    sha256 = builtins.substring 7 64 artifact.hash; # strip "sha256:"
  };
in
{
  inherit package;

  version = name: (package name).version;

  # The sdist of `name`.
  sdist =
    name:
    fetchArgs (
      (package name).sdist or (throw "lib/uv-lock.nix: ${name} has no sdist in mlx-server/uv.lock")
    );

  # The wheel of `name` whose filename ends in `-<suffix>.whl`, where suffix is
  # the python, abi and platform tags, e.g. "cp314-cp314-macosx_26_0_arm64" or
  # "py3-none-any". Exactly one wheel matches, or evaluation stops naming the
  # tags that were published.
  wheel =
    name: suffix:
    let
      p = package name;
      names = map (w: baseNameOf w.url) (p.wheels or [ ]);
      hits = builtins.filter (w: builtins.match ".*-${suffix}\\.whl" (baseNameOf w.url) != null) (
        p.wheels or [ ]
      );
    in
    if builtins.length hits == 1 then
      fetchArgs (builtins.head hits)
    else
      throw "lib/uv-lock.nix: ${name} ${p.version} has ${toString (builtins.length hits)} wheels matching -${suffix}.whl in mlx-server/uv.lock; published: ${builtins.concatStringsSep " " names}";
}
