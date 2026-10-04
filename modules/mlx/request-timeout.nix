# Bound caller timeouts from the same serving envelope used by the worker.
# A full queue can place a new request behind ceil(queueSize/concurrency)
# service waves; add the request's own worst-case prefill and decode time.
{ lib }:
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
(queueWaves + 1) * requestSeconds
