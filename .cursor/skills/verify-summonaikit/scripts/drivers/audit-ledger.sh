#!/usr/bin/env bash
# audit-ledger driver — real audita-ledger.sh on disposable fixtures.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

AUDITOR="$VERIFY_REPO/tools/audita-ledger.sh"

synth="$VERIFY_TMPDIR/ledger-repo"
gitr() {
  git -C "$synth" \
    -c user.email='t@example.invalid' -c user.name='t' \
    -c commit.gpgsign=false \
    "$@"
}
if [ ! -d "$synth/.git" ]; then
  mkdir -p "$synth"
  git -c init.defaultBranch=master init -q "$synth"
  gitr commit -q --allow-empty -m 'docs(16.3): principios por rol en los cuatro perfiles'
  gitr commit -q --allow-empty -m 'chore: un commit sin alcance de task'
  gitr update-ref refs/remotes/origin/master HEAD
fi

encabezado() {
  printf '| Task | Contenido | DoD | Depends | Status |\n'
  printf '|------|------|-----|---------|--------|\n'
}

run_auditor() {
  local ledger="$1"
  runtime_exec "$VERIFY_HOME" bash "$AUDITOR" "$synth"
}

# Plans.md lives at $synth/Plans.md (tool default). Swap per case.

if fm_only ledger-ok; then
  {
    encabezado
    printf '| 99.9 | una task que nadie empezo | DoD | - | cc:TODO |\n'
  } > "$synth/Plans.md"
  set +e
  out="$(SAIKIT_LEDGER="$synth/Plans.md" run_auditor "$synth/Plans.md" 2>&1)"
  rc=$?
  set -e
  # runtime_exec strips SAIKIT_LEDGER; default is $repo/Plans.md = $synth/Plans.md
  fm_action ledger-ok act-ok "$rc" "$out" bash "$AUDITOR" "$synth"
  if printf '%s' "$out" | grep -q 'AUDITORIA DEL LEDGER'; then
    fm_pass ledger-ok header_AUDITORIA "AUDITORIA DEL LEDGER" "AUDITORIA DEL LEDGER"
  else
    fm_fail ledger-ok header_AUDITORIA "AUDITORIA DEL LEDGER" "$out"
  fi
  if printf '%s' "$out" | grep -q 'AUDITORIA DEL LEDGER: OK'; then
    fm_pass ledger-ok ledger_ok_line "AUDITORIA DEL LEDGER: OK" "AUDITORIA DEL LEDGER: OK"
  else
    fm_fail ledger-ok ledger_ok_line "AUDITORIA DEL LEDGER: OK" "$out"
  fi
  if [ "$rc" -eq 0 ]; then
    fm_pass ledger-ok exit_0 "0" "exit $rc"
  else
    fm_fail ledger-ok exit_0 "0" "exit $rc"
  fi
fi

if fm_only ledger-stale; then
  {
    encabezado
    printf '| 16.3 | contenido | DoD | - | cc:TODO |\n'
  } > "$synth/Plans.md"
  set +e
  out="$(run_auditor "$synth/Plans.md" 2>&1)"
  rc=$?
  set -e
  fm_action ledger-stale act-stale "$rc" "$out" bash "$AUDITOR" "$synth"
  # El veredicto negativo no usa el header OK; la razon concreta es el contrato.
  # assert:stale_reason
  if printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' \
    && printf '%s' "$out" | grep -q 'fila 16.3'; then
    fm_pass ledger-stale stale_reason "LEDGER DESACTUALIZADO fila 16.3" \
      "LEDGER DESACTUALIZADO fila 16.3"
  else
    fm_fail ledger-stale stale_reason "LEDGER DESACTUALIZADO fila 16.3" "$out"
  fi
  # assert:stale_reason_end
fi

exit 0
