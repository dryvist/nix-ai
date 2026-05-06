# NixOS version tracking
# Used by GitHub Actions workflows for version monitoring
#
# stableVersion: Latest stable NixOS release branch
# Format: "YY.MM" (e.g., "24.05" for May 2024 release, "25.11" for November 2025)
#
# Note: This repo uses nixpkgs-unstable in flake.nix for cutting-edge packages.
# This field tracks the latest stable release for informational purposes only.
#
# Used by:
# - .github/workflows/nixos-release-check.yml - automated update notifications
# - .github/workflows/ci-eol-check.yml - end-of-life validation
{
  stableVersion = "25.11";

  # Package version pins — single source of truth for cross-module shared deps.
  # Each pin entry (below) must have a `# renovate:` annotation immediately above
  # it so the org-wide customManager regex tracks it (datasource= depName= on one
  # line). `stableVersion` above is informational and not tracked by Renovate.

  # HuggingFace stack
  # renovate: datasource=pypi depName=huggingface-hub
  huggingfaceHub = "1.13.0";
  # renovate: datasource=pypi depName=huggingface-mcp-server
  hfMcpServer = "0.1.0";

  # AI CLI tools (npm)
  # renovate: datasource=npm depName=@felixgeelhaar/cclint
  cclint = "0.12.1";
  # renovate: datasource=npm depName=@githubnext/github-copilot-cli
  ghCopilot = "0.1.36";
  # renovate: datasource=npm depName=chatgpt-cli
  chatgptCli = "3.3.0";
  # renovate: datasource=npm depName=claude-flow
  claudeFlow = "3.6.12";
  # renovate: datasource=npm depName=@googleworkspace/cli
  gwsCli = "0.22.5";

  # MCP servers (npm)
  # renovate: datasource=npm depName=@modelcontextprotocol/server-everything
  mcpEverything = "2026.1.26";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-filesystem
  mcpFilesystem = "2026.1.14";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-memory
  mcpMemory = "2026.1.26";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-aws-kb-retrieval
  mcpAws = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-postgres
  mcpPostgres = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-brave-search
  mcpBraveSearch = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-google-maps
  mcpGoogleMaps = "0.6.2";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-puppeteer
  mcpPuppeteer = "2025.5.12";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-slack
  mcpSlack = "2025.4.25";

  # MCP servers (pypi)
  # renovate: datasource=pypi depName=mcp-server-time
  mcpServerTime = "2026.1.26";
  # renovate: datasource=pypi depName=pal-mcp-server
  palMcpServer = "9.8.2";
  # renovate: datasource=pypi depName=fabric-mcp
  fabricMcp = "1.1.0";
  # renovate: datasource=pypi depName=google-workspace-mcp
  gwsMcp = "2.0.1";

  # MLX inference stack (pypi)
  # renovate: datasource=pypi depName=vllm-mlx
  vllmMlx = "0.2.9";
  # renovate: datasource=pypi depName=parakeet-mlx
  parakeetMlx = "0.5.1";
  # renovate: datasource=pypi depName=mlx-vlm
  mlxVlm = "0.4.4";
  # renovate: datasource=pypi depName=mlx-lm
  mlxLm = "0.31.3";
  # renovate: datasource=pypi depName=lm-eval
  lmEval = "0.4.11";

  # AI tools (pypi)
  # renovate: datasource=pypi depName=open-webui
  openWebui = "0.9.2";
  # renovate: datasource=pypi depName=browser-use
  browserUse = "0.12.6";

  # Fabric Go CLI (github-releases)
  # The flake input fabric-src is ALSO tracked by Renovate's nix manager and
  # must be bumped to the same tag. vendorHash only validates the fetched Go
  # source tree — it does NOT detect label drift between this pin and the
  # fabric-src input. The fabric-version-sync regression check in
  # lib/checks/fabric.nix (and scripts/check-fabric-version-sync.sh for
  # pre-commit / manual runs) compares the two and fails on drift.
  # renovate: datasource=github-releases depName=danielmiessler/fabric
  fabric = "1.4.444";
}
