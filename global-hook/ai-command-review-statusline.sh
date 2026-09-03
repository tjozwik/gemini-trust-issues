#!/usr/bin/env bash

set -u
set -o pipefail

readonly REVIEW_STATE_DIR="${AGY_COMMAND_REVIEW_STATE_DIR:-${HOME}/.gemini/antigravity-cli/ai-command-review-state}"
readonly DEFAULT_MODEL="${AGY_COMMAND_REVIEW_MODEL:-gpt-5.6-luna}"
readonly DEFAULT_REASONING_EFFORT="${AGY_COMMAND_REVIEW_REASONING_EFFORT:-max}"

status_input="$(cat)" || exit 0
conversation_id="$(jq -r '.conversation_id // .session_id // empty' <<<"$status_input" 2>/dev/null)" || exit 0
[[ -n "$conversation_id" ]] || exit 0

safe_conversation_id="$(printf '%s' "$conversation_id" | tr -c 'A-Za-z0-9._-' '_')"
[[ -n "$safe_conversation_id" ]] || exit 0

state_file="${REVIEW_STATE_DIR}/${safe_conversation_id}.json"
[[ -r "$state_file" ]] || exit 0

message="$(
  jq -r \
    --arg default_model "$DEFAULT_MODEL" \
    --arg default_reasoning_effort "$DEFAULT_REASONING_EFFORT" '
    def clean_text($max_length):
      gsub("\u001B\\[[0-?]*[ -/]*[@-~]"; "") |
      gsub("[\u0000-\u001F\u007F]+"; " ") |
      gsub("  +"; " ") |
      if length > $max_length then .[:$max_length] else . end;

    (.model // $default_model) as $model |
    (.reasoning_effort // $default_reasoning_effort) as $reasoning_effort |
    select(
      (.decision == "allow" or .decision == "deny") and
      (.risk == "low" or .risk == "medium" or .risk == "high" or .risk == "critical" or .risk == "unknown") and
      (.command | type == "string") and
      ($model | type == "string") and
      ($reasoning_effort | type == "string")
    ) |
    (.command |
      gsub("\u001B\\[[0-?]*[ -/]*[@-~]"; "") |
      gsub("[\u0000-\u001F\u007F]+"; " ") |
      gsub("  +"; " ") |
      if length > 100 then .[:97] + "..." else . end
    ) as $command |
    ($model | clean_text(80) | gsub("-"; " ")) as $model_label |
    ($reasoning_effort | clean_text(30)) as $reasoning_effort_label |
    (if .decision == "allow" then "✓" else "✕" end) as $marker |
    "\($marker) AI REVIEW (\($model_label) \($reasoning_effort_label)) · \(.decision | ascii_upcase) · risk=\(.risk) · \($command)"
  ' "$state_file" 2>/dev/null
)" || exit 0

[[ -n "$message" ]] || exit 0

case "$message" in
  "✓ "*) readonly color_code="38;2;134;239;172" ;;
  "✕ "*) readonly color_code="38;2;252;165;165" ;;
  *) exit 0 ;;
esac

printf '\033[%sm%s\033[0m\n' "$color_code" "$message"
