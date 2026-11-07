{ mkHmConfig }:
{
  hmConfigSessionArchive = mkHmConfig [
    {
      programs.sessionArchive = {
        enable = true;
        endpoint = "https://example.invalid";
      };
    }
  ];
  hmConfigSessionArchiveSessionEnd = mkHmConfig [
    {
      programs.sessionArchive = {
        enable = true;
        endpoint = "https://example.invalid";
        trigger = "session-end";
        credentialCommand = [
          "test-credential"
          "run"
          "--"
        ];
      };
    }
  ];
}
