# Shared scaffolding for the regression checks.
#
# Every check group repeats the same three shapes: a trivially-building
# success marker (echo + touch $out), an "option set contains every expected
# attr" guard, and a "list of {name, actual, expected} all hold" guard. These
# helpers centralize that boilerplate so the individual check files carry only
# the data (expected option names, expected default values) they are pinning.
#
# Each helper evaluates its assertions before returning the marker derivation,
# so option/default drift fails `nix flake check` at eval time — same timing
# as the inline `assert … ; pkgs.runCommand …` form it replaces.
{ pkgs }:
let
  inherit (builtins)
    attrNames
    elem
    filter
    toJSON
    length
    concatStringsSep
    map
    ;

  # Success marker: echo a message, touch $out.
  mkMarker =
    name: message:
    pkgs.runCommand name { } ''
      echo ${pkgs.lib.escapeShellArg message}
      touch $out
    '';
in
{
  inherit mkMarker;

  # Guard: `cfg` must contain every attr name in `expectedOptions`.
  mkOptionsRegression =
    {
      label,
      checkName,
      cfg,
      expectedOptions,
    }:
    let
      missing = filter (o: !(elem o (attrNames cfg))) expectedOptions;
    in
    assert missing == [ ] || throw "Missing ${label} options: ${toJSON missing}";
    mkMarker checkName "${label} option regression: ${toString (length expectedOptions)} options verified";

  # Guard: every `{ name, actual, expected }` in `checks` must have actual == expected.
  mkDefaultsRegression =
    {
      label,
      checkName,
      checks,
    }:
    let
      failures = filter (c: c.actual != c.expected) checks;
      failureMsg = concatStringsSep "\n" (
        map (c: "  ${c.name}: expected ${toJSON c.expected}, got ${toJSON c.actual}") failures
      );
    in
    assert failures == [ ] || throw "${label} default value regression:\n${failureMsg}";
    mkMarker checkName "${label} defaults regression: ${toString (length checks)} critical defaults verified";
}
