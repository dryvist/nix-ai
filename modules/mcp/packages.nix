# Python MCP servers as Nix derivations, replacing their `uvx` invocations.
#
# WHY
#
# A uvx-launched MCP server holds a SHARED LOCK on ~/.cache/uv/.lock for its
# entire lifetime. These servers are long-lived — one per agent session, and
# this workstation runs many concurrently — so an exclusive lock is never
# available and `uv cache prune` times out and EXITS 0 HAVING FREED NOTHING.
# That is how the cache reached 328 GB unnoticed: not that nobody pruned, but
# that pruning could not succeed and reported success anyway.
#
# uvx also mints a fresh venv per resolution and never evicts one, so each
# version bump strands the previous copy forever.
#
# Moving these to the store removes the lock holders and puts the packages
# under the GC that already runs weekly.
#
# WHY WHEELS
#
# Every one of these publishes a pure-python `py3-none-any` wheel, so there is
# nothing to compile and one hash covers every platform. Their dependencies all
# exist in nixpkgs; only `modelcontextprotocol` is missing, and it is built
# here for the same reason.
#
# The version pins stay in lib/versions.nix so the org-wide Renovate
# customManager keeps tracking them. A bump there without a matching hash here
# fails the build loudly rather than silently resolving something else.
{ pkgs }:
let
  versions = import ../../lib/versions.nix;
  py = pkgs.python3Packages;

  # Hashes for the py3-none-any wheels, keyed by the version in versions.nix.
  # Regenerate with `nix-prefetch-url` (or read PyPI's JSON) when bumping.
  hashes = {
    modelcontextprotocol."1.0.1" = "sha256-py2wHSblDtTak178rtwVG4nf+T4abWuRYW20xEPKLv0=";
    fabric-mcp."1.2.1" = "sha256-PNJsfq7ipdQIxIDHuzOFsq5bPzrAXt4vqbYaC0+IEN0=";
    huggingface-mcp-server."0.1.0" = "sha256-HpMuEGDX4A5KQiU8P7RCmePnxDBb11uj3fnWYOzv2Ak=";
  };

  hashFor =
    pname: version:
    hashes.${pname}.${version}
      or (throw "mcp/packages.nix: no wheel hash for ${pname} ${version}. Add it to `hashes` (the py3-none-any wheel on PyPI).");

  # PyPI serves wheel FILES under the underscored form of the project name,
  # while the project itself is hyphenated. fetchPypi uses `pname` for both the
  # URL directory and the filename, so it must get the underscored form or the
  # fetch 404s.
  wheelName = pname: pkgs.lib.replaceStrings [ "-" ] [ "_" ] pname;

  # A pure-python wheel from PyPI, installed into the store.
  wheelApp =
    {
      pname,
      version,
      deps,
      # These packages declare upper bounds that nixpkgs' newer versions trip
      # (fabric-mcp pins fastmcp<3.3, nixpkgs ships 3.3.x). The runtime-deps
      # check enforces the metadata, not actual behaviour, so it is disabled
      # and the servers are verified by loading in a real session instead.
      importCheck ? [ ],
    }:
    py.buildPythonApplication {
      inherit pname version;
      format = "wheel";
      src = py.fetchPypi {
        pname = wheelName pname;
        inherit version;
        format = "wheel";
        dist = "py3";
        python = "py3";
        abi = "none";
        platform = "any";
        hash = hashFor pname version;
      };
      propagatedBuildInputs = deps;
      dontCheckRuntimeDeps = true;
      pythonImportsCheck = importCheck;
    };

  # Not in nixpkgs; a dependency of fabric-mcp rather than a server itself.
  modelcontextprotocol = py.buildPythonPackage {
    pname = "modelcontextprotocol";
    version = "1.0.1";
    format = "wheel";
    src = py.fetchPypi {
      pname = wheelName "modelcontextprotocol";
      version = "1.0.1";
      format = "wheel";
      dist = "py3";
      python = "py3";
      abi = "none";
      platform = "any";
      hash = hashFor "modelcontextprotocol" "1.0.1";
    };
    propagatedBuildInputs = with py; [
      click
      jinja2
      loguru
      mcp
      posthog
      rich
    ];
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ ];
  };
in
{
  fabric-mcp = wheelApp {
    pname = "fabric-mcp";
    version = versions.fabricMcp;
    deps =
      (with py; [
        click
        fastmcp
        httpx
        httpx-retries
        httpx-sse
        python-dotenv
        rich
      ])
      ++ [ modelcontextprotocol ];
  };

  huggingface-mcp-server = wheelApp {
    pname = "huggingface-mcp-server";
    version = versions.hfMcpServer;
    deps = with py; [
      huggingface-hub
      mcp
    ];
  };
}
