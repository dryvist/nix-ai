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
  huggingfaceHub = "1.21.0";
  # renovate: datasource=pypi depName=huggingface-mcp-server
  hfMcpServer = "0.1.0";

  # AI CLI tools (npm)
  # renovate: datasource=npm depName=@felixgeelhaar/cclint
  cclint = "0.14.0";
  # renovate: datasource=npm depName=@githubnext/github-copilot-cli
  ghCopilot = "0.1.36";
  # renovate: datasource=npm depName=chatgpt-cli
  chatgptCli = "3.3.0";
  # renovate: datasource=npm depName=claude-flow
  claudeFlow = "3.6.30";
  # renovate: datasource=npm depName=@googleworkspace/cli
  gwsCli = "0.22.5";

  # MCP servers (npm)
  # renovate: datasource=npm depName=@upstash/context7-mcp
  context7Mcp = "3.1.0";
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
  # renovate: datasource=npm depName=mcp-server-apple-events
  mcpAppleEvents = "1.4.0";

  # MCP servers (pypi)
  # renovate: datasource=pypi depName=mcp-server-time
  mcpServerTime = "2026.1.26";
  # renovate: datasource=pypi depName=fabric-mcp
  fabricMcp = "1.2.1";
  # renovate: datasource=pypi depName=google-workspace-mcp
  gwsMcp = "2.0.1";
  # renovate: datasource=pypi depName=unifi-mcp-server
  unifiMcpServer = "0.2.5";

  # MLX inference stack (pypi)
  # 0.4.0 adds GPT-OSS/harmony prompt rendering for tool calls (required to
  # serve gpt-oss models with working tool calling) and requires
  # mlx-lm>=0.31.3, which forces the mlx/mlx-lm pins below forward together.
  #
  # ON EVERY BUMP, CHECK: does `vllm-mlx serve --models-config` now support a
  # dynamic HF-cache mode (registry auto-populated from HF_HOME instead of a
  # hand-listed YAML)? Its multi-model manager already has memory_budget_gb +
  # contention_policy (wait_then_preempt) — exactly the memory-safe loading
  # the dynamic tier (programs.mlx.dynamicTier, currently mlx_lm.server)
  # lacks. The moment upstream can treat the cache as the model source, swap
  # the dynamic tier's backend to it: zero-config exposure AND budget-aware
  # graceful refusal/preemption, one launchd arg change.
  # renovate: datasource=pypi depName=vllm-mlx
  vllmMlx = "0.4.0";
  # renovate: datasource=pypi depName=parakeet-mlx
  parakeetMlx = "0.5.1";
  # renovate: datasource=pypi depName=mlx-vlm
  mlxVlm = "0.5.0";
  # The nix-ai#751 hold at mlx 0.31.1 is RESOLVED: vllm-mlx 0.4.0 is built
  # against mlx 0.31.2 / mlx-lm 0.31.3 (it requires mlx-lm>=0.31.3), and the
  # cross-thread stream crash ("There is no Stream(gpu, N) in current thread")
  # no longer reproduces — validated 2026-07-02 on jevans-mbp with three
  # concurrent completions against Qwen3-30B-A3B-Instruct-2507-4bit under
  # continuous batching + paged KV cache: zero errors. Keep mlx and mlx-lm
  # pinned as a pair; they move in lockstep.
  # renovate: datasource=pypi depName=mlx
  mlx = "0.31.2";
  # renovate: datasource=pypi depName=mlx-lm
  mlxLm = "0.31.3";
  # transformers 5.13.0 (released 2026-07-04) broke mlx-lm 0.31.3's import:
  # AutoTokenizer.register("NewlineTokenizer", ...) passes a string key and
  # 5.13.0's register() calls key.__module__ on it -> AttributeError at
  # module import, killing every vllm-mlx worker on both hosts (fleet-wide
  # serving outage, 2026-07-04). Pin until mlx-lm registers a class (or
  # transformers restores string keys); bump together with mlxLm.
  # renovate: datasource=pypi depName=transformers
  transformers = "5.12.0";
  # renovate: datasource=pypi depName=lm-eval
  lmEval = "0.4.11";

  # AI tools (pypi)
  # renovate: datasource=pypi depName=browser-use
  browserUse = "0.12.6";

  # Fabric Go CLI (github-releases)
  # The flake input fabric-src is ALSO tracked by Renovate's nix manager and
  # must be bumped to the same tag. vendorHash only validates the fetched Go
  # source tree — it does NOT detect label drift between this pin and the
  # fabric-src input. The fabric-version-sync regression check in
  # lib/checks/fabric.nix compares the two and fails on drift.
  # renovate: datasource=github-releases depName=danielmiessler/fabric
  fabric = "1.4.452";
}
