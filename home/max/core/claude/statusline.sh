#!/usr/bin/env bash
# Status line per https://code.claude.com/docs/en/statusline
# Fields: <model> <ctx-used%> | 5h:N% | 7d:N% | $cost | session-time
# Rate-limit fields appear only for Claude.ai subscribers after the first API
# response in the session; context_window fields may be null until the first
# response. All optional fields are omitted when absent (no dangling separators).

input=$(cat)

# Model display name ------------------------------------------------------------
model_name=$(echo "$input" | jq -r '.model.display_name // empty')

# Context usage % --------------------------------------------------------------
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$ctx_used" ]; then
  ctx_used_fmt="$(LC_NUMERIC=C printf '%.0f%%' "$ctx_used")"
else
  ctx_used_fmt="?%"
fi

# 5-hour rate limit ------------------------------------------------------------
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five" ]; then
  five_fmt="5h:$(LC_NUMERIC=C printf '%.0f' "$five")%"
else
  five_fmt=""
fi

# 7-day rate limit -------------------------------------------------------------
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$week" ]; then
  week_fmt="7d:$(LC_NUMERIC=C printf '%.0f' "$week")%"
else
  week_fmt=""
fi

# Session cost USD -------------------------------------------------------------
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost" ]; then
  cost_fmt="\$$(LC_NUMERIC=C printf '%.4f' "$cost")"
else
  cost_fmt=""
fi

# Session duration -------------------------------------------------------------
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
duration_fmt=""
if [ -n "$duration_ms" ]; then
  elapsed=$(( duration_ms / 1000 ))
  h=$(( elapsed / 3600 ))
  m=$(( (elapsed % 3600) / 60 ))
  s=$(( elapsed % 60 ))
  if [ "$h" -gt 0 ]; then
    duration_fmt="${h}h${m}m"
  else
    duration_fmt="${m}m${s}s"
  fi
fi

# Assemble ---------------------------------------------------------------------
if [ -n "$model_name" ]; then
  parts=("${model_name} ${ctx_used_fmt}")
else
  parts=("${ctx_used_fmt}")
fi
[ -n "$five_fmt" ]     && parts+=("$five_fmt")
[ -n "$week_fmt" ]     && parts+=("$week_fmt")
[ -n "$cost_fmt" ]     && parts+=("$cost_fmt")
[ -n "$duration_fmt" ] && parts+=("$duration_fmt")

sep=" | "
out="${parts[0]}"
for ((i=1; i<${#parts[@]}; i++)); do
  out="${out}${sep}${parts[i]}"
done
printf '%s' "$out"
