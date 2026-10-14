{ mkHmConfig }:
{
  # Qwen Code enabled on a router-only host with no static Qwen resident.
  hmConfigQwenRouter = mkHmConfig [
    {
      programs.qwen-code.enable = true;
      services.aiStack = {
        llmEndpoint = "router";
        llmRouterEndpoint = "https://router.example.invalid/v1";
        llmEndpointTokenFile = "/tmp/test-router-token";
      };
    }
  ];

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
