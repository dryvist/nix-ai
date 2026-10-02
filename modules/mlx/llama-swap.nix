# llama-swap at the release pinned in lib/versions.nix (llamaSwap).
#
# nixpkgs-unstable's derivation, rebuilt from that tag: its build recipe and
# tests are reused and only the version, the Go toolchain, the UI directory and the three
# fixed-output hashes move. After a Renovate bump of the pin,
# fix-renovate-hashes.yml rewrites the hashes below with nix-update; the
# llama-swap-pin check fails if the package the module runs is not the pinned
# release, and the llama-swap-build check builds it.
# pkgs is nixpkgs-unstable, the set llama-swap's recipe comes from.
{ pkgs, version }:
# Upstream tracks the newest Go release; build with nixpkgs' newest toolchain
# rather than the default one, which can trail it.
(pkgs.llama-swap.override { buildGoModule = pkgs.buildGoLatestModule; }).overrideAttrs (
  finalAttrs: old: {
    version = builtins.replaceStrings [ "v" ] [ "" ] version;
    # The tag already follows finalAttrs.version; only the hash changes.
    src = old.src.override {
      hash = "sha256-cgVc4emWipvpV05H6L74RxKBJSJGMSM/ly23T/85+1s=";
    };
    # A newer test also writes a #!/bin/bash helper, which the Linux sandbox
    # lacks; point it at bash the same way the recipe already does for its own.
    postPatch = old.postPatch + ''
      substituteInPlace cmd/vllm-wrapper/main_test.go \
        --replace-fail "#!/bin/bash" "#!${pkgs.lib.getExe pkgs.bash}"
    '';
    vendorHash = "sha256-yelob7FlaGymASUP0DAUkALQm5vnXZnN5ThbnSkH2Ak=";
    passthru = old.passthru // {
      # Upstream moved the UI from ui-svelte/ to ui/.
      ui = old.passthru.ui.overrideAttrs (uiOld: {
        sourceRoot = "${finalAttrs.src.name}/ui";
        npmDeps = uiOld.npmDeps.overrideAttrs {
          sourceRoot = "${finalAttrs.src.name}/ui";
          outputHash = "sha256-lmhRJ8275PIQ+7vHdr9aZ31lYeXUkXrWnlvuwOadjRQ=";
        };
      });
    };
  }
)
