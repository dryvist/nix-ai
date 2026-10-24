{ src }:
let
  lanesFile = "${src}/ansible/roles/llm_roles/files/lanes.json";
  lanes = builtins.fromJSON (builtins.readFile lanesFile);
in
if (lanes.schema_version or null) != 1 then
  throw "homelab-contracts ${lanesFile} must use schema_version = 1"
else
  lanes
