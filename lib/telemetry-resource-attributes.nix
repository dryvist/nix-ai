# Shared OTEL_RESOURCE_ATTRIBUTES string, used by every OTel-aware process a
# user runs (Claude Code, Codex, …) so a shared collector attributes them all
# to the same OS user and host. `enduser.id` first so a consumer-supplied one
# in userConfig.telemetry.resourceAttributes overrides it (later `//` wins);
# mapAttrsToList sorts by key, so rendering stays deterministic.
{
  lib,
  userConfig,
  username,
}:
lib.concatStringsSep "," (
  lib.mapAttrsToList (k: v: "${k}=${v}") (
    { "enduser.id" = username; } // (userConfig.telemetry.resourceAttributes or { })
  )
)
