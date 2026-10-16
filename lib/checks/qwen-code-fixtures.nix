{ mkHmConfig }:
let
  routerConfig =
    qwenCodeOptions:
    mkHmConfig [
      {
        programs.qwen-code = {
          enable = true;
        }
        // qwenCodeOptions;
        services.aiStack = {
          llmEndpoint = "router";
          llmRouterEndpoint = "https://router.example.invalid/v1";
          llmEndpointTokenFile = "/tmp/test-router-token";
        };
      }
    ];
in
{
  # Qwen Code enabled on a router-only host with no static Qwen resident.
  hmConfigQwenRouter = routerConfig { };
  hmConfigQwenExcludeToolsEmpty = routerConfig { excludeTools = [ ]; };
  hmConfigQwenExcludeToolsCustom = routerConfig {
    excludeTools = [
      "custom_tool"
      "custom_tool"
      "Bash(diskutil eraseDisk *)"
    ];
  };

  hmConfigQwenMissingResident = mkHmConfig [
    {
      programs.qwen-code = {
        enable = true;
        model = "qwen38-27b";
      };
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];
}
