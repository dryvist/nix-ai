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
  huggingfaceHub = "1.29.0";
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
  claudeFlow = "3.34.0";
  # renovate: datasource=npm depName=@googleworkspace/cli
  gwsCli = "0.22.5";
  # renovate: datasource=npm depName=@openwhispr/cli
  openwhisprCli = "0.1.2";
  # renovate: datasource=npm depName=langfuse-cli
  langfuseCli = "0.0.12";
  # oh-my-openagent Senpi edition (standalone `omo` command). Beta-channel
  # only: every published version is a prerelease and the `latest` dist-tag
  # points at a placeholder (0.0.0-beta.0), so a Renovate npm pin would track
  # the wrong channel. Bump manually against `npm view omo-ai@beta version`.
  # Deliberately carries no `renovate:` annotation — same rationale as
  # mcpSdkBound above.
  omoSenpi = "5.0.0-0.beta.17";

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

  # Upper bound for the MCP Python SDK, applied to every uvx-launched server
  # below. Those servers declare `mcp>=<x>` with no ceiling, so a fresh resolve
  # installs the 2.x SDK — which renamed the public surface (`server.fastmcp` →
  # `server.mcpserver`, `McpError` → `MCPError`) and dropped `Server.list_tools`.
  # The result is a server that dies at import and reports only
  # `CONNECTION_CLOSED`, which reads as an outage rather than a dependency break.
  # This supplies the bound upstream omitted; drop it per-server once that
  # server ships 2.x support.
  #
  # Deliberately carries no `renovate:` annotation: it is a compatibility
  # constraint, not a version pin, and there is nothing here for Renovate to
  # bump — it is removed by hand when upstream migrates.
  mcpSdkBound = "mcp<2";

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
  # 0.4.1 keeps that floor (mlx>=0.29.0, mlx-lm>=0.31.3, mlx-vlm>=0.6.5), so the
  # pins below still satisfy it. Bumping this pin ALSO requires regenerating the
  # wheel url + hash in modules/mlx/vllm-mlx-patch.nix — that derivation fetches
  # one literal PyPI wheel path, so a version-only bump fails to build.
  # renovate: datasource=pypi depName=vllm-mlx
  vllmMlx = "0.4.1";
  # renovate: datasource=pypi depName=parakeet-mlx
  parakeetMlx = "0.5.2";
  # renovate: datasource=pypi depName=mlx-vlm
  mlxVlm = "0.6.13";
  # The nix-ai#751 hold at mlx 0.31.1 is RESOLVED: vllm-mlx 0.4.0 is built
  # against mlx 0.31.2 / mlx-lm 0.31.3 (it requires mlx-lm>=0.31.3), and the
  # cross-thread stream crash ("There is no Stream(gpu, N) in current thread")
  # no longer reproduces — validated with three concurrent completions against
  # a 30B-class 4-bit MoE under continuous batching + paged KV cache: zero
  # errors. Keep mlx and mlx-lm pinned together; they move in lockstep.
  #
  # 0.31.2 was previously held as "the last release of the prior minor, never a
  # #.#.0" after instability on a freshly-bumped minor. That policy is retired:
  # mlx ships minors rarely — 0.31.0 in February, 0.31.1 in March, 0.31.2 in
  # April, 0.32.0 in July — so skipping a .0 costs months of fixes rather than
  # days. Track current instead. mlx-lm 0.31.3 declares mlx>=0.31.2, so 0.32.0
  # satisfies it.
  #
  # mlx-server/pyproject.toml must track this value; it is a dev environment no
  # build consumes, so drift there is invisible.
  # renovate: datasource=pypi depName=mlx
  mlx = "0.32.2";
  # renovate: datasource=pypi depName=mlx-lm
  mlxLm = "0.31.3";
  # renovate.json5 blocks the exact 5.13.0 build via allowedVersions — that
  # release breaks mlx-lm at import (register() calls key.__module__ on the
  # string key mlx-lm passes), taking every worker down. The rule there carries
  # the reproduction detail.
  # renovate: datasource=pypi depName=transformers
  transformers = "5.16.1";
  # renovate: datasource=pypi depName=lm-eval
  lmEval = "0.4.12";

  # AI tools (pypi)
  # renovate: datasource=pypi depName=browser-use
  browserUse = "0.13.7";
  # The loopback proxy (modules/litellm-local). Runs from uvx rather than
  # nixpkgs so it tracks the upstream release train; nixpkgs lags by months
  # and builds it from source with a large test closure.
  # renovate: datasource=pypi depName=litellm
  litellm = "1.98.0";

  # Fabric Go CLI (github-releases)
  # The flake input fabric-src is ALSO tracked by Renovate's nix manager and
  # must be bumped to the same tag. vendorHash only validates the fetched Go
  # source tree — it does NOT detect label drift between this pin and the
  # fabric-src input. The fabric-version-sync regression check in
  # lib/checks/fabric.nix compares the two and fails on drift.
  # renovate: datasource=github-releases depName=danielmiessler/fabric
  fabric = "1.4.470";
}
