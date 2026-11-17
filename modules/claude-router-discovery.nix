{ name }:
''
  settings_dir=$(mktemp -d)
  trap 'rm -rf "$settings_dir"' EXIT
  models_json="$settings_dir/models.json"
  model_info_json="$settings_dir/model-info.json"
  fallback_json="$settings_dir/fallbacks.json"
  settings_json="$settings_dir/settings.json"

  fetch_json() {
    local url=$1
    local output=$2
    local status
    status=$(printf 'Authorization: Bearer %s\n' "$key_value" | curl \
      --fail \
      --silent \
      --show-error \
      --noproxy '*' \
      --output "$output" \
      --write-out '%{http_code}' \
      --header @- \
      "$url")
    if [[ "$status" != 200 ]]; then
      printf '%s\n' "${name}: model discovery returned HTTP $status" >&2
      return 1
    fi
    jq -e '.data | type == "array"' "$output" >/dev/null || {
      printf '%s\n' "${name}: model discovery returned an invalid response" >&2
      return 1
    }
  }

  fetch_json "$base_url/v1/models" "$models_json"
  fetch_json "$base_url/model/info" "$model_info_json"
  fetch_json \
    "$base_url/v1/models?include_metadata=true&fallback_type=context_window" \
    "$fallback_json"

  if ! jq -e --arg selected "$model" '.data | any(.[]; .id == $selected)' "$models_json" >/dev/null; then
    printf '%s\n' "${name}: selected model is not available to this key: $model" >&2
    exit 1
  fi

  if ! jq -n \
    --slurpfile models "$models_json" \
    --slurpfile model_info "$model_info_json" \
    --slurpfile fallback_models "$fallback_json" \
    --arg selected "$model" \
    '
      def fallback_targets($name):
        [ $fallback_models[0].data[]?
          | select(.id == $name)
          | .metadata.fallbacks[]?
          | strings ];

      # The own window of a group is its smallest member window; null when model info has none.
      def own_window($name):
        [ $model_info[0].data[]?
          | select(.model_name == $name)
          | .model_info.max_input_tokens?
          | select(type == "number" and . > 0) ]
        | if length > 0 then min else null end;

      # The largest window the router reaches for a group: its own, or that of a context-window fallback.
      def effective_window($name; $visited):
        if ($visited | index($name)) != null then null
        else
          [ own_window($name),
            (fallback_targets($name)[] | effective_window(.; $visited + [$name])) ]
          | map(select(. != null))
          | if length > 0 then max else null end
        end;

      # Ids with no window (image, speech, wildcard groups) stay out of the picker.
      [ $models[0].data[]?
        | .id as $id
        | effective_window($id; []) as $window
        | select($window != null)
        | { value: $id, label: ($id + " (" + ($window | tostring) + " tokens)") }
      ] as $options
      | {
          modelPicker: { options: $options },
          contextWindow: (effective_window($selected; [])
            // error("model info has no max_input_tokens for " + $selected))
        }
    ' >"$settings_json"; then
    printf '%s\n' "${name}: model windows could not be resolved from router model info" >&2
    exit 1
  fi

  context_window=$(jq -er '.contextWindow | select(type == "number" and . > 0)' "$settings_json")
  settings_file="$settings_dir/claude-settings.json"
  jq '{ modelPicker: .modelPicker }' "$settings_json" >"$settings_file"
''
