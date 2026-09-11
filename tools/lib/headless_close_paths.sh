#!/usr/bin/env bash
# headless_close_paths.sh — STATE_PATH identico al hook (20.15).
# No glob. session_id vacio => UNKNOWN (nunca sin-session).
# Source-only.

headless_project_key() {
  printf '%s' "${1:?}" | cksum | cut -d ' ' -f 1
}

headless_session_key() {
  local raw="${1:-}"
  if [ -z "$raw" ]; then
    printf '%s' "UNKNOWN"
    return 0
  fi
  printf '%s' "$raw" | sed 's/[^A-Za-z0-9_-]/_/g' | cut -c1-64
}

headless_hook_dir() {
  if [ -n "${SAIKIT_HOOK_DIR:-}" ]; then
    printf '%s' "$SAIKIT_HOOK_DIR"
    return 0
  fi
  printf '%s' "${HOME}/.claude/hooks"
}

headless_state_path() {
  local host="${1:?}" project_root="${2:?}" session_id="${3:-}"
  local hook_dir project_key session_key
  hook_dir="$(headless_hook_dir)"
  project_key="$(headless_project_key "$project_root")"
  session_key="$(headless_session_key "$session_id")"
  printf '%s/state/%s/%s/%s/harness-state.env' "$hook_dir" "$host" "$project_key" "$session_key"
}

headless_state_dir_of() {
  local p="${1:?}"
  printf '%s' "${p%/*}"
}
