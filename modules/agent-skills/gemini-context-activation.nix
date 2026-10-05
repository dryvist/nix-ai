{ lib, homeDir }:

lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
  context_file="${homeDir}/.gemini/GEMINI.md"
  local_file="${homeDir}/.gemini/GEMINI.local.md"
  $DRY_RUN_CMD mkdir -p "${homeDir}/.gemini"
  if [ -f "$context_file" ] && [ ! -L "$context_file" ]; then
    if [ -e "$local_file" ]; then
      echo "Cannot preserve Gemini context: $local_file already exists" >&2
      exit 1
    fi
    $DRY_RUN_CMD mv "$context_file" "$local_file"
  fi
  if [ ! -e "$local_file" ]; then
    $DRY_RUN_CMD touch "$local_file"
  fi
''
