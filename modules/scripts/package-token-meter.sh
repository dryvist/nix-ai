#!/usr/bin/env bash
set -euo pipefail

src=$1
dest=$2
manifest="$src/runtime-manifest.txt"

PYTHONPATH="$src" python3 -m token_meter.packaging manifest "$manifest"
mkdir -p "$dest"

while read -r kind relative_path _; do
  [[ -z "$kind" || "$kind" == \#* ]] && continue
  source_path="$src/$relative_path"
  install_path="$dest/$relative_path"

  case "$kind" in
    required | optional)
      [[ -e "$source_path" ]] || [[ "$kind" == optional ]] || {
        echo "token-meter: required runtime path is missing: $relative_path" >&2
        exit 1
      }
      [[ -e "$source_path" ]] || continue
      mkdir -p "$(dirname "$install_path")"
      cp -R "$source_path" "$install_path"
      ;;
    python-tree)
      find "$source_path" -type f -name '*.py' -print0 \
        | while IFS= read -r -d '' package_file; do
          package_relative=${package_file#"$src/"}
          mkdir -p "$dest/$(dirname "$package_relative")"
          cp "$package_file" "$dest/$package_relative"
        done
      ;;
    tree)
      mkdir -p "$install_path"
      chmod -R u+w "$install_path"
      cp -R "$source_path/." "$install_path/"
      ;;
    *)
      echo "token-meter: unsupported runtime manifest entry: $kind" >&2
      exit 1
      ;;
  esac
done < "$manifest"

PYTHONPATH="$src" python3 -m token_meter.packaging parity "$src" "$dest" "$manifest"
