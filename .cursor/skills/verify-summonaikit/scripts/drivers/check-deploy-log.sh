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

# 20.27: horas de deploy con cordón HORA_CONTROL del checker. Las tres formas:
# recuperable (hora + .bak citado) aceptada; no-recuperada honesta aceptada;
# hora sin evidencia rechazada nombrando la regla.
if fm_only deploy-log-hora-evidente; then
  log="$VERIFY_TMPDIR/deploy-hora-evidente.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #301 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:54 PDT / 20:54 UTC):** master sincronizado; cuatro copias
  REPARADO. Backups: `summonaikit-harness.sh.nuestro.20260908-135442.bak`.
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-hora-evidente act-hora-evidente "$rc" "$out" \
    bash "$TOOL" --log "$log"
  # assert:hora_evidente_aceptado
  if [ "$rc" -eq 0 ]; then
    fm_pass deploy-log-hora-evidente hora_evidente_aceptado "0" \
      "exit 0: hora de deploy respaldada por .bak del instalador"
  else
    fm_fail deploy-log-hora-evidente hora_evidente_aceptado "0" "exit $rc: $out"
  fi
  # assert:hora_evidente_aceptado_end
fi

if fm_only deploy-log-hora-no-recuperada; then
  log="$VERIFY_TMPDIR/deploy-hora-no-recuperada.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #302 / Task Y — hooks NO-OP

- **Merge (21:12 UTC — mergedAt de GitHub):** `b93e2c61528`, gate SUCCESS.
- **Deploy (hora no recuperada — no-op sin backup; mergedAt acredita el merge, no el deploy):** master sincronizado.
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-hora-no-recuperada act-hora-norec "$rc" "$out" \
    bash "$TOOL" --log "$log"
  # assert:hora_no_recuperada_aceptado
  if [ "$rc" -eq 0 ]; then
    fm_pass deploy-log-hora-no-recuperada hora_no_recuperada_aceptado "0" \
      "exit 0: unknown honesto (sin hora no se exige evidencia)"
  else
    fm_fail deploy-log-hora-no-recuperada hora_no_recuperada_aceptado "0" \
      "exit $rc: $out"
  fi
  # assert:hora_no_recuperada_aceptado_end
fi

if fm_only deploy-log-hora-sin-evidencia; then
  log="$VERIFY_TMPDIR/deploy-hora-sin-evidencia.md"
  cat > "$log" <<'EOF'
# Deploy log — fixture
## 2026-09-08 — PR #303 / Task X — deploy REAL

- **Merge (13:29 UTC — mergedAt de GitHub):** `abc123def456`, gate SUCCESS.
- **Deploy (13:29 PDT / 20:29 UTC):** master sincronizado; cuatro copias
  REPARADO. Sin backup citado.
- **Verificación:** `install-hook.sh --check` exit 0.
EOF
  set +e
  out="$(run_check "$log" 2>&1)"
  rc=$?
  set -e
  fm_action deploy-log-hora-sin-evidencia act-hora-sinev "$rc" "$out" \
    bash "$TOOL" --log "$log"
  # assert:hora_sin_evidencia_rechazado
  if [ "$rc" -eq 1 ]; then
    fm_pass deploy-log-hora-sin-evidencia hora_sin_evidencia_rechazado "1" \
      "exit 1: hora de deploy sin fuente"
  else
    fm_fail deploy-log-hora-sin-evidencia hora_sin_evidencia_rechazado "1" \
      "exit $rc: $out"
  fi
  # assert:hora_sin_evidencia_rechazado_end
  # assert:reason_evidencia
  if printf '%s' "$out" | grep -q 'evidencia'; then
    fm_pass deploy-log-hora-sin-evidencia reason_evidencia "evidencia" \
      "nombra la regla de evidencia"
  else
    fm_fail deploy-log-hora-sin-evidencia reason_evidencia "evidencia" "$out"
  fi
  # assert:reason_evidencia_end
fi

exit 0
