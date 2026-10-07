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

  # The install spec passed to uvx. Registry packages stay pinned by version;
  # VCS packages use the exact commit recorded by uv.lock.
  installSpec =
    name:
    let
      p = package name;
      source = p.source or { };
      gitRef =
        if source ? git then
          builtins.match "^(https?://[^?]+)\\?rev=([0-9a-f]{40})#([0-9a-f]{40})$" source.git
        else
          null;
    in
    if source ? git then
      if gitRef == null then
        throw "lib/uv-lock.nix: ${name} has an unsupported VCS source in mlx-server/uv.lock: ${source.git}"
      else
        "git+${builtins.elemAt gitRef 0}@${builtins.elemAt gitRef 1}"
    else
      "${name}==${p.version}";

  # The sdist of `name`.
  sdist =
    name:
    fetchArgs (
      (package name).sdist or (throw "lib/uv-lock.nix: ${name} has no sdist in mlx-server/uv.lock")
    );

  # The wheel of `name` installable on a host: interpreter tag `cpTag` (e.g.
  # "cp314"), the stable ABI, or pure python; platform tag matching the regex
  # `platform`, or "any". When several qualify (one per OS deployment target)
  # the last listed, the newest target, wins.
  hostWheel =
    name:
    { cpTag, platform }:
    let
      p = package name;
      hits = builtins.filter (
        w:
        builtins.match ".*-(${cpTag}-${cpTag}|cp3[0-9]+-abi3|py3-none)-(${platform}|any)\\.whl" (
          baseNameOf w.url
        ) != null
      ) (p.wheels or [ ]);
    in
    if hits == [ ] then
      throw "lib/uv-lock.nix: ${name} ${p.version} has no ${cpTag} wheel for platform ${platform} in mlx-server/uv.lock; published: ${
        builtins.concatStringsSep " " (map (w: baseNameOf w.url) (p.wheels or [ ]))
      }"
    else
      fetchArgs (builtins.elemAt hits (builtins.length hits - 1));

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
