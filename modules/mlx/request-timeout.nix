# Bound the caller and pipe deadlines from the same serving envelope.
# A full queue can place a new request behind ceil(queueSize/concurrency)
# service waves; the pipe gets one additional service wave after the request
# deadline so it cannot cancel the request at its own timeout boundary.
{
  contextWindowTokens,
  maxOutputTokens,
  concurrency,
  queueSize,
  prefillTokensPerSecond,
  decodeTokensPerSecond,
}:
let
  divCeil = a: b: (a + b - 1) / b;
  requestSeconds =
    divCeil (contextWindowTokens - maxOutputTokens) prefillTokensPerSecond
    + divCeil maxOutputTokens decodeTokensPerSecond;
  queueWaves = divCeil queueSize concurrency;
in
{
  requestTimeoutSeconds = (queueWaves + 1) * requestSeconds;
  pipeTimeoutSeconds = (queueWaves + 2) * requestSeconds;
}
