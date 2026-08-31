# Claude Code tier-name checks for the local LiteLLM proxy.
#
# Split out of ./litellm-local.nix to stay under the repo's 12KB file-size
# error ceiling, the same reason ./litellm-local-fallbacks.nix and
# ./litellm-local-keys.nix are separate. The split is by responsibility: this
# file answers "can every model name Claude Code is pointed at resolve without
# the `*` wildcard, and does it carry the context window a subagent needs".
{
  lib,
  claudeEnv,
  rendered,
  routerUrl,
  tokenFilePath,
}:
rec {
  # Every model name Claude Code is pointed at must be one the proxy can resolve
  # WITHOUT the `*` wildcard — either an Anthropic capability alias / model id
  # that lands in the `claude-*` group, or an explicit `model_name` in the
  # model_list. Naming an upstream ROLE is what caused the outage: the router
  # served no `subagent` group, so the request fell through `*` and 404'd on
  # every subagent spawn. `*` must never be what makes a Claude Code tier work.
  explicitGroups = map (d: d.model_name) rendered.model_list;
  claudeTierNames = lib.filter (n: n != null) [
    (claudeEnv.CLAUDE_CODE_SUBAGENT_MODEL or null)
    (claudeEnv.ANTHROPIC_MODEL or null)
  ];
  #
  # A bare capability alias is NOT accepted, and that is the point. `opus`,
  # `sonnet` and `haiku` used to be allowed here on the belief that the harness
  # expands them before the request leaves. It does not: a `sonnet[1m]` request
  # was observed reaching the proxy verbatim, missing `claude-*`, falling
  # through `*` and egressing to a third-party provider. An alias that looks
  # Claude-shaped but routes to the router is worse than a name that fails,
  # because the session keeps working and only the destination changed.
  claudeTierNamesResolveLocally = lib.all (
    n: lib.hasPrefix "claude" n || lib.elem n explicitGroups
  ) claudeTierNames;

  # Every tier name that DOES reach Anthropic must carry the 1M-context suffix.
  # A subagent here routinely carries more than a 200k window holds, so a
  # 200k-window id is a truncation waiting to happen — and truncation returns a
  # confident wrong answer rather than an error.
  claudeTierNamesAre1m = lib.all (
    n: !(lib.hasPrefix "claude" n) || lib.hasSuffix "[1m]" n
  ) claudeTierNames;

  # THE LEAK GATE. `*` must not be reachable by anything Claude-shaped.
  #
  # LiteLLM resolves an exact `model_name` first and only then the `*` group,
  # so a Claude-shaped name that is neither a `claude-*` match nor an explicit
  # group silently becomes router egress. Enumerating the shapes the harness
  # actually emits is the only way to catch it before a request does: a bare
  # alias, and an alias carrying the `[1m]` suffix.
  claudeShapedNames =
    lib.concatMap
      (a: [
        a
        "${a}[1m]"
      ])
      [
        "opus"
        "sonnet"
        "haiku"
        "fable"
      ];
  claudeShapedNamesCannotReachWildcard = lib.all (
    n: !(lib.elem n claudeTierNames) || lib.elem n explicitGroups
  ) claudeShapedNames;

  # The haiku tier stays on Anthropic: Claude Code's background requests carry
  # its full system prompt (~36k tokens), which the `cheap` role's 32k-window
  # local target cannot hold, so an override fails every background call.
  claudeHaikuUntouched = !(claudeEnv ? ANTHROPIC_DEFAULT_HAIKU_MODEL);

  # The header is what makes LiteLLM forward the OAuth bearer instead of
  # treating it as the proxy credential. It must be in settings.json (every
  # surface) and it must be the constant marker, never a key.
  # Discovery would list the two wildcard groups as picker rows.
  claudeNoDiscovery = !(claudeEnv ? CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY);

  # The private-workspace guard asks the upstream router what a role resolves
  # to; it must find the address and the bearer file PATH from settings.json,
  # since a GUI-launched session never runs shell init.
  claudeGetsRouterAddress = claudeEnv.LLM_ROUTER_URL == routerUrl;
  claudeGetsTokenPathOnly = claudeEnv.LLM_ROUTER_TOKEN_FILE == tokenFilePath;
}
