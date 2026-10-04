# Catalog-derived concurrency ceiling for the largest selected model shape.
{
  lib,
  calibration,
  gib,
  perTokenKvBytes,
}:
{
  budgetGb,
  peakWeightGb,
  peakWindowTokens,
  peakKv,
}:
let
  headroomBytes = (budgetGb - peakWeightGb) * gib;
  perStreamBytes = peakWindowTokens * (perTokenKvBytes peakKv);
  memoryFit = if perStreamBytes <= 0 then 1 else lib.max 1 (headroomBytes / perStreamBytes);
in
lib.min calibration.operatorConcurrencyCap memoryFit
