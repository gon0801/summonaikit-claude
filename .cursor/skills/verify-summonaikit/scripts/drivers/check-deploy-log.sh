#!/usr/bin/env bash
# check-deploy-log driver — real check-deploy-log.sh on disposable fixtures.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

TOOL="$VERIFY_REPO/tools/check-deploy-log.sh"

run_check() {
  local log="$1"
  runtime_exec "$VERIFY_HOME" bash "$TOOL" --log "$log"
}

if fm_only deploy-log-ok; then
  log="$VERIFY_TMPDIR/deploy-ok.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — PR #201 / Task X — deploy NO-OP
cuerpo
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-ok act-ok "$rc" "$out" bash "$TOOL" --log "$log"
  if [ "$rc" -eq 0 ]; then
    fm_pass deploy-log-ok exit_0 "0" "exit $rc"
  else
    fm_fail deploy-log-ok exit_0 "0" "exit $rc: $out"
  fi
  if printf '%s' "$out" | grep -q '\[deploy-log\] OK'; then
    fm_pass deploy-log-ok deploy_log_ok_line "[deploy-log] OK" "[deploy-log] OK"
  else
    fm_fail deploy-log-ok deploy_log_ok_line "[deploy-log] OK" "$out"
  fi
fi

if fm_only deploy-log-order; then
  log="$VERIFY_TMPDIR/deploy-order.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-05 — PR #201 / Task X — deploy NO-OP
cuerpo
## 2026-09-06 — PR #202 / Task Y — deploy NO-OP
cuerpo
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-order act-order "$rc" "$out" bash "$TOOL" --log "$log"
  if [ "$rc" -ne 0 ]; then
    fm_pass deploy-log-order exit_nonzero "nonzero" "exit $rc"
  else
    fm_fail deploy-log-order exit_nonzero "nonzero" "exit 0"
  fi
  if printf '%s' "$out" | grep -q 'orden'; then
    fm_pass deploy-log-order reason_orden "orden" "orden"
  else
    fm_fail deploy-log-order reason_orden "orden" "$out"
  fi
fi

if fm_only deploy-log-dup; then
  log="$VERIFY_TMPDIR/deploy-dup.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-06 — PR #203 / Task X — deploy NO-OP
cuerpo
## 2026-09-05 — PR #203 / Task X (reintento) — deploy REAL
cuerpo
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-dup act-dup "$rc" "$out" bash "$TOOL" --log "$log"
  if [ "$rc" -ne 0 ]; then
    fm_pass deploy-log-dup exit_nonzero "nonzero" "exit $rc"
  else
    fm_fail deploy-log-dup exit_nonzero "nonzero" "exit 0"
  fi
  # assert:reason_dup_pr
  if printf '%s' "$out" | grep -q '#203'; then
    fm_pass deploy-log-dup reason_dup_pr "#203" "#203"
  else
    fm_fail deploy-log-dup reason_dup_pr "#203" "$out"
  fi
  # assert:reason_dup_pr_end
fi

exit 0
