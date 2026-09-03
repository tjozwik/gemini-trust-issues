#!/usr/bin/env bash

set -euo pipefail

readonly USER_HOME="${HOME:?HOME is not set}"
readonly AGY_CONFIG_ROOT="${AGY_CONFIG_ROOT:-${USER_HOME}/.gemini/config}"
readonly AGY_CLI_ROOT="${AGY_CLI_ROOT:-${USER_HOME}/.gemini/antigravity-cli}"
readonly HOOK_FILE="${AGY_CONFIG_ROOT}/hooks/ai-command-review.sh"
readonly SCHEMA_FILE="${AGY_CONFIG_ROOT}/hooks/decision.schema.json"
readonly HOOKS_FILE="${AGY_CONFIG_ROOT}/hooks.json"
readonly SETTINGS_FILE="${AGY_CLI_ROOT}/settings.json"
readonly STATUSLINE_FILE="${AGY_CLI_ROOT}/ai-command-review-statusline.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -x "$HOOK_FILE" ]] || fail "Reviewer hook is missing or not executable: $HOOK_FILE"
[[ -r "$SCHEMA_FILE" ]] || fail "Decision schema is missing: $SCHEMA_FILE"
[[ -x "$STATUSLINE_FILE" ]] || fail "Status line script is missing or not executable: $STATUSLINE_FILE"

bash -n "$HOOK_FILE" "$STATUSLINE_FILE"
jq -e . "$SCHEMA_FILE" >/dev/null
jq -e \
  --arg hook_command "$HOOK_FILE" '
    .["codex-ai-command-review"].PreToolUse[] |
    select(.matcher == "run_command") |
    .hooks[] |
    select(.command == $hook_command)
  ' "$HOOKS_FILE" >/dev/null || fail "PreToolUse hook is not configured."
jq -e \
  --arg statusline_command "$STATUSLINE_FILE" '
    .statusLine.enabled == true and
    .statusLine.stack_with_default == true and
    .statusLine.command == $statusline_command and
    (.permissions.allow | index("command(*)") != null)
  ' "$SETTINGS_FILE" >/dev/null || fail "Status line or command permission bridge is not configured."

command -v codex >/dev/null 2>&1 || fail "codex is not available on PATH."
command -v agy >/dev/null 2>&1 || fail "agy is not available on PATH."
command -v timeout >/dev/null 2>&1 || fail "timeout is not available on PATH."

printf 'OK: installation files and configuration are valid.\n'
printf 'Codex: %s\n' "$(codex --version | head -n 1)"
printf 'Agy:   %s\n' "$(agy --version | head -n 1)"
printf 'Run agy normally and use /hooks for the final runtime check.\n'
