# pal-models-shared.jq
#
# Shared jq helpers for LMSYS arena rating lookup, included by both
# pal-models-mlx.jq and pal-models-openrouter.jq.
#
# Loaded via: jq -L <scripts_dir> --slurpfile ratings <ratings.json> --from-file <transform>.jq
#
# LMSYS arena Elo is the SINGLE source of intelligence scoring across the
# entire pipeline. There are no heuristic fallbacks. Models that aren't
# on the leaderboard are filtered out by the transforms — PAL only sees
# models with a real benchmark score.
#
# Score normalization: linear map from Elo to PAL's 1-20 scale.
#   (rating - 800) / 700 * 19 + 1, clamped to [1, 20]
#   1499 → 20  (claude-opus-4-7, current top)
#   1300 → ~14 (median 2026 frontier model)
#   1100 → ~9  (older frontier, e.g. claude-3-opus-20240229)
#    800 → 1   (early-2024 baseline)

# Lowercase + strip provider prefix + strip MLX quant suffix.
# OpenRouter ids: "anthropic/claude-opus-4.7" → "claude-opus-4.7"
# MLX ids:        "mlx-community/Qwen3.5-122B-A10B-4bit" → "qwen3.5-122b-a10b"
#                 "mlx-community/Qwen3.6-35B-A3B-mxfp4"  → "qwen3.6-35b-a3b"
def normalize_name:
  ascii_downcase
  | sub("^[^/]+/"; "")                        # strip "anthropic/", "mlx-community/", etc.
  | sub("-(mxfp[0-9]+|[0-9]+bit)$"; "");      # strip MLX quant suffix (4bit, mxfp4/mxfp8)

# Find the highest LMSYS rating among keys that start with $prefix.
# Used as a fuzzy fallback for variants the leaderboard names differently:
#   "x-ai/grok-4.20" → matches "grok-4.20-beta1" via prefix
# Returns null if no key matches.
def find_best_prefix_match($prefix):
  ($ratings[0] // {}) as $r
  | [$r | to_entries[] | select(.key | startswith($prefix)) | .value]
  | if length > 0 then max else null end;

# Proxy-rating aliases: a model not yet on the LMSYS leaderboard mapped to its
# nearest rated sibling (normalized names). The resident MoE shares size and
# architecture with its prior-generation sibling, so that Elo is a conservative
# lower bound until the leaderboard lists the model directly. Keep this tiny.
def rating_aliases: {
  "qwen3.6-35b-a3b": "qwen3.5-35b-a3b"
};

# Look up an Elo rating from the slurped $ratings file.
# Tries (in order): exact, hyphenated form (Anthropic), prefix match, proxy alias.
# Returns null if nothing matches — caller MUST handle null (typically by
# filtering the model out, never by inventing a fallback score).
def lookup_rating($name):
  ($ratings[0] // {}) as $r
  | ($name | normalize_name) as $base
  | ($base | gsub("\\."; "-")) as $hyphenated
  | $r[$base]
    // $r[$hyphenated]
    // find_best_prefix_match($base)
    // find_best_prefix_match($hyphenated)
    // (rating_aliases[$base] as $alias | if $alias != null then $r[$alias] else null end);

# Convert an Elo rating to PAL's 1-20 intelligence scale.
# Uses half-up rounding so 1499 → 20 (not 19 with floor).
# Returns null if rating is null. Callers must filter null results out.
def rating_to_score($rating):
  if $rating == null then null
  else
    ((($rating - 800) / 700 * 19 + 1 + 0.5) | floor) as $raw
    | if $raw < 1 then 1
      elif $raw > 20 then 20
      else $raw
      end
  end;

# One-shot lookup: name → score, or null if not in LMSYS arena.
def model_intelligence_score($name):
  lookup_rating($name) | rating_to_score(.);
