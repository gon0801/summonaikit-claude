# driver.sh — helpers for feature-map drivers (19.4).
# Sourced after skill_root is set. Never sourced as the run state.
# Requires SAIKIT_FM_ATTEMPT_DIR from the controller.

fm_only() {
  local case_id="$1"
  if [ -n "${SAIKIT_FM_ONLY_CASE:-}" ] && [ "${SAIKIT_FM_ONLY_CASE}" != "$case_id" ]; then
    return 1
  fi
  return 0
}

fm_evidence() {
  local ev="${SAIKIT_FM_EVIDENCE:-$skill_root/scripts/lib/evidence.py}"
  PYTHONDONTWRITEBYTECODE=1 python3 "$ev" "$@"
}

fm_action() {
  local case_id="$1" step="$2" tool_exit="$3" observation="$4"
  shift 4
  fm_evidence append-step --attempt-dir "$SAIKIT_FM_ATTEMPT_DIR" --type action \
    --case-id "$case_id" --step-id "$step" \
    --tool-exit "$tool_exit" --observation "$observation" \
    --command "$*" >/dev/null
}

fm_assert() {
  local case_id="$1" asid="$2" result="$3" expected="$4" observed="$5"
  fm_evidence append-step --attempt-dir "$SAIKIT_FM_ATTEMPT_DIR" --type assertion \
    --case-id "$case_id" --step-id "s-$asid" --assertion-id "$asid" \
    --expected "$expected" --observed "$observed" --result "$result" >/dev/null
}

fm_pass() { fm_assert "$1" "$2" PASS "$3" "$4"; }
fm_fail() { fm_assert "$1" "$2" FAIL "$3" "$4"; }

fm_sha() {
  sha256sum < "$1" | awk '{print $1}'
}
