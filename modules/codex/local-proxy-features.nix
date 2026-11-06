# Limit Codex's sandbox network access to the local proxy and required services.
{ config, lib }:
let
  sandboxDefaults = import ./sandbox-defaults.nix;
  cfg = config.programs.codex;
  localProxy = config.programs.litellmLocal;
  proxyAuthority = builtins.head (
    lib.strings.splitString "/" (lib.strings.removePrefix "http://" localProxy.baseUrl)
  );
  proxyHost = builtins.head (lib.strings.splitString ":" proxyAuthority);
  allowedDomains = lib.genAttrs (
    [ proxyHost ] ++ sandboxDefaults.networkProxyDomains ++ cfg.networkProxyDomains
  ) (_: "allow");
in
lib.optionalAttrs localProxy.enable {
  network_proxy = {
    enabled = true;
    domains = allowedDomains;
  };
}
