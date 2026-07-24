# Package version pins — single source of truth for cross-module shared deps.
#
# Each pin entry (below) must have a `# renovate:` annotation immediately above
# it so the org-wide customManager regex tracks it (datasource= depName= on one
# line).
{

  # HuggingFace stack
  # >=1.21.0 required: adds click>=8.4.0 as a direct dep and caps typer<0.26.0.
  # Older pins left typer unbounded (>=0.20.0), floating to 0.26.x which vendored
  # click and dropped the external dep the hf CLI imports → ModuleNotFoundError.
  # renovate: datasource=pypi depName=huggingface-hub
  huggingfaceHub = "1.24.0";
  # renovate: datasource=pypi depName=huggingface-mcp-server
  hfMcpServer = "0.1.0";

  # AI CLI tools (npm)
  # renovate: datasource=npm depName=@felixgeelhaar/cclint
  cclint = "0.15.1";
  # renovate: datasource=npm depName=@githubnext/github-copilot-cli
  ghCopilot = "0.1.36";
  # renovate: datasource=npm depName=chatgpt-cli
  chatgptCli = "3.3.0";
  # renovate: datasource=npm depName=claude-flow
  claudeFlow = "3.25.2";
  # renovate: datasource=npm depName=@googleworkspace/cli
  gwsCli = "0.22.5";

  # MCP servers (npm)
  # renovate: datasource=npm depName=@upstash/context7-mcp
  context7Mcp = "3.2.3";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-everything
  mcpEverything = "2026.7.4";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-filesystem
  mcpFilesystem = "2026.7.4";
  # renovate: datasource=npm depName=@modelcontextprotocol/server-memory
  mcpMemory = "2026.7.4";
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
  # renovate: datasource=npm depName=mcp-server-apple-events
  mcpAppleEvents = "1.4.0";
  # renovate: datasource=npm depName=@democratize-technology/vikunja-mcp
  vikunjaMcp = "0.2.0";

  # MCP servers (pypi)
  # renovate: datasource=pypi depName=mcp-server-time
  mcpServerTime = "2026.6.4";
  # renovate: datasource=pypi depName=fabric-mcp
  fabricMcp = "1.2.1";
  # renovate: datasource=pypi depName=google-workspace-mcp
  gwsMcp = "2.0.8";
  # renovate: datasource=pypi depName=unifi-mcp-server
  unifiMcpServer = "0.2.5";

  # MCP servers (uvx from git — not published to PyPI or npm)
  # Consumed as git+https://github.com/basher83/zammad-mcp.git@v<version>; the
  # upstream tag is v-prefixed, this pin stays bare like fabric below.
  # renovate: datasource=github-tags depName=basher83/Zammad-MCP
  zammadMcp = "1.1.0";

  # MLX inference stack (pypi)
  # 0.4.0 adds GPT-OSS/harmony prompt rendering for tool calls (required to
  # serve gpt-oss models with working tool calling) and requires
  # mlx-lm>=0.31.3, which forces the mlx/mlx-lm pins below forward together.
  # renovate: datasource=pypi depName=vllm-mlx
  vllmMlx = "0.4.0";
  # renovate: datasource=pypi depName=parakeet-mlx
  parakeetMlx = "0.5.2";
  # renovate: datasource=pypi depName=mlx-vlm
  mlxVlm = "0.6.7";
  # The nix-ai#751 hold at mlx 0.31.1 is RESOLVED: vllm-mlx 0.4.0 is built
  # against mlx 0.31.2 / mlx-lm 0.31.3 (it requires mlx-lm>=0.31.3), and the
  # cross-thread stream crash ("There is no Stream(gpu, N) in current thread")
  # no longer reproduces — validated 2026-07-02 on jevans-mbp with three
  # concurrent completions against Qwen3-30B-A3B-Instruct-2507-4bit under
  # continuous batching + paged KV cache: zero errors. Keep mlx and mlx-lm
  # pinned as a pair; they move in lockstep. Pinned back to 0.31.2 (last
  # release of the prior minor — never ride a #.#.0) 2026-07-23 after serving
  # instability on jevans-ms; mlx-lm 0.31.3 declares mlx>=0.31.2, so this
  # stays compatible.
  # renovate: datasource=pypi depName=mlx
  mlx = "0.31.2";
  # renovate: datasource=pypi depName=mlx-lm
  mlxLm = "0.31.3";
  # renovate.json5 blocks the exact 5.13.0 build via allowedVersions (see
  # Zammad ticket 130 for the 2026-07-04 outage history behind that block).
  # renovate: datasource=pypi depName=transformers
  transformers = "5.14.1";
  # renovate: datasource=pypi depName=lm-eval
  lmEval = "0.4.12";

  # AI tools (pypi)
  # renovate: datasource=pypi depName=browser-use
  browserUse = "0.13.6";

  # Fabric Go CLI (github-releases)
  # The flake input fabric-src is ALSO tracked by Renovate's nix manager and
  # must be bumped to the same tag. vendorHash only validates the fetched Go
  # source tree — it does NOT detect label drift between this pin and the
  # fabric-src input. The fabric-version-sync regression check in
  # lib/checks/fabric.nix compares the two and fails on drift.
  # renovate: datasource=github-releases depName=danielmiessler/fabric
  fabric = "1.4.455";
}
