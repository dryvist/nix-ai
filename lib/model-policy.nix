# Pure policy admission for every role-map and local catalog model.
{
  src,
  roleMap,
  mlxCatalog,
  policy ?
    let
      file = "${toString src}/ansible/roles/llm_model_catalog/files/model-policy.json";
    in
    if builtins.pathExists file then builtins.fromJSON (builtins.readFile file) else null,
}:
let
  inherit (builtins)
    all
    attrValues
    concatLists
    div
    elemAt
    filter
    foldl'
    genList
    head
    isString
    length
    match
    ;
  nonempty = value: isString value && match ".*[^[:space:]].*" value != null;
  decimal =
    value:
    foldl' (n: digit: n * 10 + builtins.fromJSON digit) 0 (
      genList (i: builtins.substring i 1 value) (builtins.stringLength value)
    );
  leap = year: div year 4 * 4 == year && (div year 100 * 100 != year || div year 400 * 400 == year);
  # Gregorian ordinal days, including calendar validation and leap centuries.
  dayNumber =
    date:
    let
      parts = if isString date then match "([0-9]{4})-([0-9]{2})-([0-9]{2})" date else null;
      year = decimal (elemAt parts 0);
      month = decimal (elemAt parts 1);
      day = decimal (elemAt parts 2);
      months = [
        31
        (if leap year then 29 else 28)
        31
        30
        31
        30
        31
        31
        30
        31
        30
        31
      ];
      priorYear = year - 1;
    in
    if
      parts == null || year < 1 || month < 1 || month > 12 || day < 1 || day > elemAt months (month - 1)
    then
      throw "model policy: expected a valid YYYY-MM-DD date"
    else
      365 * priorYear + div priorYear 4 - div priorYear 100
      + div priorYear 400
      + foldl' (sum: days: sum + days) 0 (genList (i: elemAt months i) (month - 1))
      + day;
  asOf = dayNumber (policy.as_of or null);
  ids =
    map (model: model.id) (attrValues roleMap.models)
    ++ map (model: model.model) (attrValues mlxCatalog);
  errorsFor =
    id:
    let
      records = filter (model: model.id == id) policy.models;
      model = head records;
      upstream = model.upstream_id or null;
      created = model.upstream_created or null;
      age = asOf - dayNumber created;
      denied = builtins.any (entry: entry.id == id || entry.id == upstream) policy.deny;
      unambiguous = all (
        entry: (entry.upstream_id or null) != upstream || (entry.upstream_created or null) == created
      ) policy.models;
    in
    if length records != 1 then
      [ "model policy: `${id}` must have exactly one models record" ]
    else if denied then
      [ "model policy: `${id}` or its upstream is denied" ]
    else if !nonempty upstream || !nonempty (model.dossier or null) || !unambiguous then
      [ "model policy: `${id}` requires an upstream, dossier and unambiguous upstream date" ]
    else if age < 0 || age > policy.max_age_days then
      [ "model policy: `${id}` upstream date is outside max_age_days of as_of" ]
    else
      [ ];
in
# The policy becomes mandatory when the contracts input first supplies it.
# No fixture substitutes for an absent production policy during the input bump.
if policy == null then
  if
    builtins.pathExists "${toString src}/ansible/roles/llm_model_catalog/files/model-policy.json"
  then
    throw "model policy: expected a version 1 policy object"
  else
    [ ]
else if
  (policy.version or null) != 1 || !builtins.isInt policy.max_age_days || policy.max_age_days < 0
then
  throw "model policy: expected version 1 and a nonnegative integer max_age_days"
else
  builtins.deepSeq asOf (concatLists (map errorsFor ids))
