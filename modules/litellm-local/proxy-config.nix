# The rendered LiteLLM configuration for the local proxy.
#
# Split out of ./default.nix to stay under the .file-size.yml ceiling, the same
# reason ./fallback-tier.nix is its own file. The split is by responsibility:
# this file decides WHAT the proxy serves and how each group authenticates,
# ./commands.nix builds the executables, and default.nix wires the module.
#
# The safety property lives here, so read it here: `claude-*` is the only group
# that receives the calling client's forwarded credentials, and the scoped
# `model_group_settings.forward_client_headers_to_llm_api` list is the only
# thing keeping that credential off the router leg. `lib/checks/litellm-local.nix`
# asserts the list stays exactly `[ "claude-*" ]`.
{
  lib,
  fallbackTier,
  telemetryTracesEndpoint,
}:
# `os.environ/NAME` is LiteLLM's own indirection: the literal string is what
# goes in the config file, and LiteLLM resolves it from the process
# environment at load time. That is what keeps the router bearer out of the
# store.
{
  model_list = [
    {
      model_name = "claude-*";
      # No api_key, deliberately: this deployment is reached with the OAuth
      # bearer the calling client already holds, forwarded by the scoped rule
      # below. An api_key here would override that bearer and bill the wrong
      # account.
      #
      # LiteLLM only treats a client bearer as forwardable OAuth when it
      # carries the `sk-ant-oat` prefix (see its anthropic common_utils
      # optionally_handle_anthropic_oauth). A client sending any other token
      # shape therefore gets no credential on this leg rather than the wrong
      # one — the failure is a 401, not a silent mis-auth.
      #
      # `anthropic/claude-*`, not `anthropic/*`: the wildcard substitutes only
      # the part the pattern matched, so `anthropic/*` turned a request for
      # `claude-opus-5` into an upstream request for `opus-5`, which Anthropic
      # rejects as an unknown model.
      litellm_params.model = "anthropic/claude-*";
    }
    {
      model_name = "*";
      litellm_params = {
        model = "openai/*";
        api_base = "os.environ/LLM_ROUTER_URL";
        api_key = "os.environ/OPENAI_API_KEY";
      };
    }
  ]
  # Named tier groups come after the wildcards deliberately: an explicit
  # model_name always wins over `*`, so ordering here is documentation, not
  # routing. Naming them at all is the point — `*` would resolve
  # `subagent-free` upstream, where the alias may not exist.
  ++ fallbackTier.modelList;

  litellm_settings = {
    # Clients disagree about which sampling params they send; dropping the
    # ones a given backend rejects keeps a role swap from breaking a client.
    drop_params = true;
    model_group_settings.forward_client_headers_to_llm_api = [ "claude-*" ];

    # Retry a transient upstream failure before declaring the group down.
    # This is the cheap half of "never let it die": most 5xx and connection
    # resets clear on a retry, and only a persistent failure should spend a
    # fallback.
    num_retries = 3;

    # The cost-ordered chain. `[{group: [fallback, ...]}]` is LiteLLM's own
    # shape (proxy_server_config.yaml), and the same shape the upstream
    # router already reports back in its error payloads.
    #
    # Scoped to the tier groups on purpose — there is deliberately NO
    # `default_fallbacks` here. A blanket default would also catch
    # `claude-*`, silently answering a main session from a free model when
    # Anthropic rate-limits. Losing the request is recoverable; not noticing
    # the model changed underneath a long session is not. The main tier gets
    # retries and a context-window fallback, never a silent quality swap.
    inherit (fallbackTier) fallbacks;

    # A context-window overflow is unambiguous — the request cannot succeed
    # as sent, and a larger window is strictly better rather than a
    # downgrade. That makes it the one case where routing the main tier
    # elsewhere is safe.
    # Target is the tier's OWN entry point, never a literal: the head group
    # is named once in fallback-tier.nix and a refresh reorders what sits
    # behind it. A hardcoded name here ("subagent-cheap") was not an emitted
    # model_list group at all, so it failed the explicit-group check.
    context_window_fallbacks = [ { "claude-*" = [ fallbackTier.entryPoint ]; } ];
  }
  # Every non-Anthropic call this host makes traverses this proxy, so with no
  # callback the entire local fabric is an observability blind spot.
  #
  # `otel`, NOT `langfuse` — a deliberate match with the shared router rather
  # than a second mechanism. LiteLLM's `langfuse` callback needs the v2 SDK
  # and errors on init against the v3 that pip resolves today; the collector
  # already fans traces out to Langfuse, so one emitter on one path reaches
  # the same sink with nothing extra to keep in step. It also means this
  # proxy needs no Langfuse credential of its own.
  #
  # Only ever set when there is somewhere to send them: an OTLP exporter with
  # no endpoint falls back to a conventional loopback address and exports
  # into a black hole, which is exactly the failure this repo already fixed
  # once for Claude Code. No endpoint, no callback.
  // lib.optionalAttrs (telemetryTracesEndpoint != null) { callbacks = [ "otel" ]; };
}
