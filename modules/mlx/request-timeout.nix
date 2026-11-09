# Bound the caller and pipe deadlines from the same serving envelope.
# A full queue can place a new request behind ceil(queueSize/concurrency)
# service waves; with 16-slot LRU prompt caching and bounded DropOldest
# queueing, caller request timeouts are capped at 2 hours (7200s) so a
# worst-case cold-miss queue estimate cannot hold router sockets open for 5+
# hours. The pipe gets one additional service wave after the request deadline
# so it cannot cancel the request at its own timeout boundary.
{
  contextWindowTokens,
  maxOutputTokens,
  concurrency,
  queueSize,
  prefillTokensPerSecond,
  decodeTokensPerSecond,
  maxRequestTimeoutSeconds ? 7200,
}:
let
  divCeil = a: b: (a + b - 1) / b;
  min = a: b: if a < b then a else b;
  requestSeconds =
    divCeil (contextWindowTokens - maxOutputTokens) prefillTokensPerSecond
    + divCeil maxOutputTokens decodeTokensPerSecond;
  queueWaves = divCeil queueSize concurrency;
  rawRequestTimeoutSeconds = (queueWaves + 1) * requestSeconds;
  requestTimeoutSeconds = min maxRequestTimeoutSeconds rawRequestTimeoutSeconds;
in
{
  inherit requestTimeoutSeconds;
  pipeTimeoutSeconds = requestTimeoutSeconds + requestSeconds;
}
