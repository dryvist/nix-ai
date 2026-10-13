# Limit Codex's sandbox network access to the local proxy and required services.
{ config, lib }:
let
  cfg = config.programs.codex;
  localProxy = config.programs.litellmLocal;
  proxyAuthority = builtins.head (
    lib.strings.splitString "/" (lib.strings.removePrefix "http://" localProxy.baseUrl)
  );
  proxyHost = builtins.head (lib.strings.splitString ":" proxyAuthority);
  allowedDomains = {
    "${proxyHost}" = "allow";
    "api.doppler.com" = "allow";
    "cli.doppler.com" = "allow";
    "api.github.com" = "allow";
    "github.com" = "allow";
  }
  // lib.genAttrs cfg.networkProxyDomains (_: "allow");
in
lib.optionalAttrs localProxy.enable {
  network_proxy = {
    enabled = true;
    domains = allowedDomains;
  };
}
