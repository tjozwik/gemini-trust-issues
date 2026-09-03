#!/usr/bin/env bash

set -euo pipefail

readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_DIR="${REPO_DIR}/global-hook"
readonly USER_HOME="${HOME:?HOME is not set}"
readonly AGY_CONFIG_ROOT="${AGY_CONFIG_ROOT:-${USER_HOME}/.gemini/config}"
readonly AGY_CLI_ROOT="${AGY_CLI_ROOT:-${USER_HOME}/.gemini/antigravity-cli}"
readonly HOOK_INSTALL_DIR="${AGY_CONFIG_ROOT}/hooks"
readonly HOOKS_FILE="${AGY_CONFIG_ROOT}/hooks.json"
readonly SETTINGS_FILE="${AGY_CLI_ROOT}/settings.json"
readonly STATUSLINE_FILE="${AGY_CLI_ROOT}/ai-command-review-statusline.sh"
readonly BACKUP_DIR="${AGY_CLI_ROOT}/gpt-review-backups/$(date +%Y%m%d-%H%M%S)-$$"

tmp_hooks=""
tmp_settings=""

cleanup() {
  [[ -z "$tmp_hooks" ]] || rm -f -- "$tmp_hooks"
  [[ -z "$tmp_settings" ]] || rm -f -- "$tmp_settings"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

for dependency in bash jq timeout codex agy; do
  command -v "$dependency" >/dev/null 2>&1 || fail "Missing required command: $dependency"
done

bash -n \
  "${SOURCE_DIR}/ai-command-review.sh" \
  "${SOURCE_DIR}/ai-command-review-statusline.sh"
jq -e . "${SOURCE_DIR}/decision.schema.json" >/dev/null
jq -e . "${SOURCE_DIR}/hooks.json" >/dev/null
jq -e . "${SOURCE_DIR}/settings.json" >/dev/null

mkdir -p -- "$HOOK_INSTALL_DIR" "$AGY_CLI_ROOT" "$BACKUP_DIR"

if [[ -f "$HOOKS_FILE" ]]; then
  cp -p -- "$HOOKS_FILE" "${BACKUP_DIR}/hooks.json"
fi
if [[ -f "$SETTINGS_FILE" ]]; then
  cp -p -- "$SETTINGS_FILE" "${BACKUP_DIR}/settings.json"
fi

install -m 0755 "${SOURCE_DIR}/ai-command-review.sh" "${HOOK_INSTALL_DIR}/ai-command-review.sh"
install -m 0644 "${SOURCE_DIR}/decision.schema.json" "${HOOK_INSTALL_DIR}/decision.schema.json"
install -m 0755 "${SOURCE_DIR}/ai-command-review-statusline.sh" "$STATUSLINE_FILE"

tmp_hooks="$(mktemp "${AGY_CONFIG_ROOT}/.hooks.json.XXXXXX")"

if [[ -f "$HOOKS_FILE" ]]; then
  jq -e 'type == "object"' "$HOOKS_FILE" >/dev/null || fail "Existing hooks.json is not a JSON object."
  jq \
    --arg hook_command "${HOOK_INSTALL_DIR}/ai-command-review.sh" \
    --slurpfile managed "${SOURCE_DIR}/hooks.json" '
      ($managed[0] |
        .["codex-ai-command-review"].PreToolUse[0].hooks[0].command = $hook_command
      ) as $managed_hook |
      . + $managed_hook
    ' "$HOOKS_FILE" >"$tmp_hooks"
else
  jq -n \
    --arg hook_command "${HOOK_INSTALL_DIR}/ai-command-review.sh" \
    --slurpfile managed "${SOURCE_DIR}/hooks.json" '
      $managed[0] |
      .["codex-ai-command-review"].PreToolUse[0].hooks[0].command = $hook_command
    ' >"$tmp_hooks"
fi

chmod 0644 -- "$tmp_hooks"
mv -f -- "$tmp_hooks" "$HOOKS_FILE"
tmp_hooks=""

tmp_settings="$(mktemp "${AGY_CLI_ROOT}/.settings.json.XXXXXX")"

read -r -d '' settings_filter <<'JQ' || true
  def append_unique($base; $extra):
    reduce (($base // []) + ($extra // []))[] as $item
      ([]; if index($item) then . else . + [$item] end);

  .permissions = (.permissions // {}) |
  .permissions.allow = append_unique(.permissions.allow; $managed[0].permissions.allow) |
  .statusLine = ($managed[0].statusLine | .command = $statusline_command)
JQ

if [[ -f "$SETTINGS_FILE" ]]; then
  jq -e '
    type == "object" and
    ((.permissions // {}) | type == "object") and
    ((.permissions.allow // []) | type == "array") and
    ((.permissions.deny // []) | type == "array")
  ' "$SETTINGS_FILE" >/dev/null || fail "Existing settings.json has an incompatible permissions structure."
  jq \
    --arg statusline_command "$STATUSLINE_FILE" \
    --slurpfile managed "${SOURCE_DIR}/settings.json" \
    "$settings_filter" \
    "$SETTINGS_FILE" >"$tmp_settings"
else
  jq -n \
    --arg statusline_command "$STATUSLINE_FILE" \
    --slurpfile managed "${SOURCE_DIR}/settings.json" \
    "{} | $settings_filter" >"$tmp_settings"
fi

chmod 0644 -- "$tmp_settings"
mv -f -- "$tmp_settings" "$SETTINGS_FILE"
tmp_settings=""

printf 'Installed Codex AI command review.\n'
printf 'Hooks:      %s\n' "$HOOKS_FILE"
printf 'Settings:   %s\n' "$SETTINGS_FILE"
printf 'Statusline: %s\n' "$STATUSLINE_FILE"
printf 'Backup:     %s\n' "$BACKUP_DIR"
printf 'Restart agy, then run /hooks to verify the PreToolUse hook.\n'
