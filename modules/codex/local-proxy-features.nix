# Limit Codex's sandbox network access to the configured local proxy.
{ config, lib }:
let
  localProxy = config.programs.litellmLocal;
  proxyAuthority = builtins.head (
    lib.strings.splitString "/" (lib.strings.removePrefix "http://" localProxy.baseUrl)
  );
  proxyHost = builtins.head (lib.strings.splitString ":" proxyAuthority);
in
lib.optionalAttrs localProxy.enable {
  network_proxy = {
    enabled = true;
    domains = {
      "${proxyHost}" = "allow";
    };
  };
}
