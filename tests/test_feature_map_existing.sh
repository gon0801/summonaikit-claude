#!/usr/bin/env bash
# tests/test_feature_map_existing.sh — 19.4: aserciones reales de las cuatro
# features actuales. No sustituye verify/ (criterios reutilizados, no invocados
# como driver). Un encabezado + exit 0 jamás acredita conducta.
#
# Mutaciones discriminantes (copia del driver en sandbox; SAIKIT_FM_DRIVER):
#   omit_dry_run_no_write — quita la aserción de "dry-run no escribe"
#   write_on_dry_run      — el driver instala de verdad en el dest del dry-run
#   omit_sin_estado       — unarmed sin afirmar ausencia de estado/contrato
#   omit_contract         — armed sin afirmar JSON/contrato
#   omit_harness_state    — armed sin afirmar harness-state/task_hash
#   omit_stop_rejected    — Stop sin afirmar exit 2 del paso stop
#   accept_stale_ledger   — ledger atrasado registrado como OK
#   accept_dup_pr         — PR duplicado registrado como OK
#   header_only           — solo encabezado + rc 0; no satisface conducta
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
VERIFY="$repo/verify"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"
. "$here/lib/feature_map_mut.sh"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}


latest_summary() {
  local fid="$1"
  find "$ART" -path "*/*/${fid}/*/summary.json" -type f \
    | awk -F/ '{print $0}' | tail -1
}

latest_steps() {
  local sum
  sum="$(latest_summary "$1")"
  [ -n "$sum" ] || return 1
  printf '%s' "$(dirname "$sum")/steps.jsonl"
}

assert_obs() {
  # $1=feature $2=assertion_id $3=regex that MUST appear in observed
  local fid="$1" asid="$2" pat="$3"
  local steps
  steps="$(latest_steps "$fid")" || { malo "$fid: sin steps para $asid"; return; }
  python3 - "$steps" "$asid" "$pat" <<'PY' || malo "$fid: $asid no observa [$pat]"
import json, re, sys
steps, asid, pat = sys.argv[1], sys.argv[2], sys.argv[3]
found = None
for line in open(steps, encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("type") == "assertion" and rec.get("assertion_id") == asid:
        found = rec
if found is None:
    raise SystemExit(f"falta aserción {asid}")
obs = str(found.get("observed") or "")
if found.get("result") != "PASS":
    raise SystemExit(f"{asid} result={found.get('result')} obs={obs!r}")
if not re.search(pat, obs):
    raise SystemExit(f"{asid} observed no coincide {pat!r}: {obs!r}")
PY
}


# ---------------------------------------------------------------------------
# verify/ preservado (no se toca; criterios se reutilizan, no se invoca)
# ---------------------------------------------------------------------------
caso "verify/ preservado (no sustituye el driver)"
if git -C "$repo" diff --quiet HEAD -- verify/ 2>/dev/null; then
  :
else
  malo "verify/ tiene cambios — 19.4 debe preservarlo"
fi
[ -f "$VERIFY/test_drive.py" ] || malo "falta verify/test_drive.py"
grep -q 'test_el_gate_sin_armar_y_armado' "$VERIFY/test_drive.py" \
  || malo "verify/test_drive.py perdio el caso unarmed/armed"
grep -q '(sin estado)' "$VERIFY/test_drive.py" \
  || malo "verify/test_drive.py perdio el criterio (sin estado)"
grep -q 'SUMMONAIKIT HARNESS REQUIRED' "$VERIFY/test_drive.py" \
  || malo "verify/test_drive.py perdio el criterio de contrato"

# ---------------------------------------------------------------------------
# Descriptores migrados a driver (no legacy inline)
# ---------------------------------------------------------------------------
caso "cuatro descriptores kind=driver y scripts presentes"
python3 - "$SKILL" <<'PY' || malo "descriptores no migraron a driver"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
for fid in ("install-guardian", "gate-turn", "audit-ledger", "check-deploy-log"):
    d = json.loads((skill / "features" / f"{fid}.json").read_text())
    ex = d.get("executor") or {}
    if ex.get("kind") != "driver":
        raise SystemExit(f"{fid}: kind={ex.get('kind')!r} (se espera driver)")
    path = ex.get("path") or f"scripts/drivers/{fid}.sh"
    p = skill / path
    if not p.is_file():
        raise SystemExit(f"{fid}: falta {path}")
PY
for fid in install-guardian gate-turn audit-ledger check-deploy-log; do
  bash -n "$SKILL/scripts/drivers/$fid.sh" \
    || malo "bash -n fallo en drivers/$fid.sh"
done

# ---------------------------------------------------------------------------
# Launch + drives reales
# ---------------------------------------------------------------------------
caso "launch aislado para drives reales"
reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay drives)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"
VERIFY_DEST="$(python3 - "$STATE/state.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["dest"])
PY
)"
VERIFY_HOME="$(python3 - "$STATE/state.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["verify_home"])
PY
)"
[ -n "$VERIFY_DEST" ] && [ -f "$VERIFY_DEST" ] || malo "launch no dejo DEST"

# ---- install-guardian -------------------------------------------------------
caso "drive install-guardian: dry-run sin delta, identidad, no-op, ajeno, restore"
reset_art
out="$(ctrl drive install-guardian 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive install-guardian rc=$rc: $out"
sum="$(latest_summary install-guardian)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "install-guardian sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "install-guardian summary incompleto"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS" and s.get("exit_code") == 0, s
cases = s.get("cases") or s.get("cases_requested") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
for need in ("install-dry-run", "install-ownership", "install-noop",
             "install-foreign", "install-restore"):
    assert need in text, (need, cases)
PY
fi
assert_obs install-guardian dry_run_no_write 'unchanged|ausente|no.write|sin.delta|intact'
assert_obs install-guardian source_identity 'procedencia: rama='
assert_obs install-guardian ownership_marker 'SAIKIT-CLAUDE-OWNED'
assert_obs install-guardian dest_matches_source '[a-f0-9]{12,}'
assert_obs install-guardian ya_al_dia 'YA AL DIA'
assert_obs install-guardian dest_unchanged 'unchanged|igual|intact'
assert_obs install-guardian foreign_intact 'intact|igual|unchanged'
assert_obs install-guardian restore_vendor_bytes 'vendor|restaur|igual|match'

# ---- gate-turn --------------------------------------------------------------
caso "drive gate-turn: unarmed sin estado/contrato; armed con ambos y SHA"
reset_art
out="$(ctrl drive gate-turn 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive gate-turn rc=$rc: $out"
sum="$(latest_summary gate-turn)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "gate-turn sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "gate-turn no pidio unarmed+armed+stop"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "PASS", s
cases = s.get("cases") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
assert "gate-unarmed" in text and "gate-armed" in text, cases
assert "gate-stop-no-receipt" in text, cases
PY
fi
src_sha="$(sha256sum < "$repo/hooks/summonaikit-harness.sh" | cut -d' ' -f1)"
assert_obs gate-turn hook_sha "$src_sha"
assert_obs gate-turn scenario_steps '01'
assert_obs gate-turn sin_estado '\(sin estado\)'
assert_obs gate-turn sin_contrato 'sin contrato|no.contrato|sin additionalContext|ausente'
assert_obs gate-turn contract_json 'SUMMONAIKIT HARNESS REQUIRED'
assert_obs gate-turn harness_state 'harness-state\.env'
assert_obs gate-turn stop_rejected 'stop exit 2'
assert_obs gate-turn not_scenario_01_02 '07-evidencia-incompleta'

# Independiente: 01/02 no acreditan el Stop
steps="$(latest_steps gate-turn)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "Stop se atribuyo a 01/02"
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("assertion_id") != "stop_rejected":
        continue
    if rec.get("case_id") in ("gate-unarmed", "gate-armed"):
        raise SystemExit("stop_rejected en caso 01/02")
    if rec.get("case_id") != "gate-stop-no-receipt":
        raise SystemExit(f"stop_rejected case={rec.get('case_id')}")
PY
fi

# ---- audit-ledger -----------------------------------------------------------
caso "drive audit-ledger: fixture OK y negativo con razon concreta"
reset_art
out="$(ctrl drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive audit-ledger rc=$rc: $out"
assert_obs audit-ledger ledger_ok_line 'AUDITORIA DEL LEDGER: OK'
assert_obs audit-ledger stale_reason 'LEDGER DESACTUALIZADO'
assert_obs audit-ledger stale_reason 'fila 16\.3'

# ---- check-deploy-log -------------------------------------------------------
caso "drive check-deploy-log: valido, orden y PR duplicado"
reset_art
out="$(ctrl drive check-deploy-log 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive check-deploy-log rc=$rc: $out"
assert_obs check-deploy-log deploy_log_ok_line '\[deploy-log\] OK'
assert_obs check-deploy-log reason_orden 'orden'
assert_obs check-deploy-log reason_dup_pr '#203'

# ---------------------------------------------------------------------------
# Encabezado falso + rc 0 no satisface conducta
# ---------------------------------------------------------------------------
caso "encabezado falso con rc 0 no acredita conducta"
reset_art
stub="$SANDBOX/header-only.sh"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
adir="${SAIKIT_FM_ATTEMPT_DIR:?}"
skill="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# standalone stub: speak evidence.py from the real skill via env
EVID="${SAIKIT_FM_EVIDENCE:?}"
fid="${SAIKIT_FM_FEATURE:?}"
assert() {
  python3 "$EVID" append-step --attempt-dir "$adir" --type assertion \
    --case-id "$1" --step-id "s-$2" --assertion-id "$2" \
    --expected "$2" --observed "$3" --result PASS
}
case "$fid" in
  install-guardian)
    assert install-dry-run exit_0 "exit 0"
    assert install-dry-run dry_run_no_write "dry-run"
    assert install-dry-run source_identity "dry-run"
    assert install-ownership ownership_marker "INSTALADO"
    assert install-ownership dest_matches_source "INSTALADO"
    assert install-noop ya_al_dia "YA AL DIA"
    assert install-noop dest_unchanged "YA AL DIA"
    assert install-foreign foreign_intact "ok"
    assert install-restore restore_vendor_bytes "ok"
    ;;
  gate-turn)
    assert gate-unarmed hook_sha "=== escenario 01-sin-armar"
    assert gate-unarmed scenario_steps "=== escenario 01-sin-armar"
    assert gate-unarmed sin_estado "=== escenario 01-sin-armar"
    assert gate-unarmed sin_contrato "=== escenario 01-sin-armar"
    assert gate-armed hook_sha "=== escenario 02-armado-contrato"
    assert gate-armed scenario_steps "=== escenario 02-armado-contrato"
    assert gate-armed contract_json "=== escenario 02-armado-contrato"
    assert gate-armed harness_state "=== escenario 02-armado-contrato"
    assert gate-stop-no-receipt stop_rejected "=== escenario 07"
    assert gate-stop-no-receipt not_scenario_01_02 "=== escenario 07"
    ;;
  audit-ledger)
    assert ledger-ok header_AUDITORIA "AUDITORIA DEL LEDGER"
    assert ledger-ok ledger_ok_line "AUDITORIA DEL LEDGER"
    assert ledger-ok exit_0 "0"
    assert ledger-stale header_AUDITORIA "AUDITORIA DEL LEDGER"
    assert ledger-stale stale_reason "AUDITORIA DEL LEDGER"
    ;;
  check-deploy-log)
    assert deploy-log-ok exit_0 "0"
    assert deploy-log-ok deploy_log_ok_line "[deploy-log] OK"
    assert deploy-log-order exit_nonzero "0"
    assert deploy-log-order reason_orden "[deploy-log] OK"
    assert deploy-log-dup exit_nonzero "0"
    assert deploy-log-dup reason_dup_pr "[deploy-log] OK"
    ;;
esac
exit 0
EOF
chmod +x "$stub"
export SAIKIT_FM_EVIDENCE="$SKILL/scripts/lib/evidence.py"
ctrl_drv "$stub" drive gate-turn >/dev/null 2>&1 || true
steps="$(latest_steps gate-turn)"
[ -n "$steps" ] && [ -f "$steps" ] || malo "stub gate-turn no escribio steps"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "el test acepto encabezado falso como (sin estado)"
import json, re, sys
found = None
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("assertion_id") == "sin_estado":
        found = rec
if found is None:
    raise SystemExit(0)  # omitted ≠ accredited
obs = str(found.get("observed") or "")
if re.search(r"\(sin estado\)", obs):
    raise SystemExit("header-only acredito (sin estado)")
# expected: header-only observed is just the escenario line
raise SystemExit(0)
PY
fi
ctrl_drv "$stub" drive audit-ledger >/dev/null 2>&1 || true
steps="$(latest_steps audit-ledger)"
if [ -n "$steps" ] && [ -f "$steps" ]; then
python3 - "$steps" <<'PY' || malo "el test acepto encabezado como ledger atrasado"
import json, sys
found = None
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip():
        continue
    rec = json.loads(line)
    if rec.get("assertion_id") == "stale_reason":
        found = rec
if found is None:
    raise SystemExit(0)
obs = str(found.get("observed") or "")
if "LEDGER DESACTUALIZADO" in obs and "16.3" in obs:
    raise SystemExit("header-only acredito ledger atrasado")
raise SystemExit(0)
PY
fi

# ---------------------------------------------------------------------------
# Aliases siguen despachando al driver
# ---------------------------------------------------------------------------
caso "aliases drive-* despachan al driver (alcance parcial de gate)"
reset_art
out="$(ctrl drive-gate-scenario 01-sin-armar 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "alias gate-unarmed rc=$rc: $out"
printf '%s' "$out" | grep -Eqi 'partial|parcial|alcance' \
  || malo "alias gate no declara alcance parcial: $out"
assert_obs gate-turn sin_estado '\(sin estado\)'
sum="$(latest_summary gate-turn)"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "alias gate acredito gate-armed"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
cases = s.get("cases") or []
text = " ".join(cases) if not isinstance(cases, str) else cases
assert "gate-armed" not in text, cases
assert s.get("scope_partial") is True or "partial" in str(s.get("scope") or "").lower()
PY
fi

# ---------------------------------------------------------------------------
# Mutantes: copia del driver, quitar cada proteccion
# ---------------------------------------------------------------------------
copy_driver() {
  local fid="$1" dest="$2"
  cp "$SKILL/scripts/drivers/$fid.sh" "$dest"
  chmod +x "$dest"
}

fm_mut_check_flat_infra gate-turn "$SKILL/scripts/drivers/gate-turn.sh" drive gate-turn
fm_mut_require_baseline gate-turn "$SKILL/scripts/drivers/gate-turn.sh" drive gate-turn
fm_mut_check_flat_infra install-guardian "$SKILL/scripts/drivers/install-guardian.sh" drive-install-dry-run
fm_mut_require_baseline install-guardian "$SKILL/scripts/drivers/install-guardian.sh" drive-install-dry-run
fm_mut_check_flat_infra audit-ledger "$SKILL/scripts/drivers/audit-ledger.sh" drive audit-ledger
fm_mut_require_baseline audit-ledger "$SKILL/scripts/drivers/audit-ledger.sh" drive audit-ledger
fm_mut_check_flat_infra check-deploy-log "$SKILL/scripts/drivers/check-deploy-log.sh" drive check-deploy-log
fm_mut_require_baseline check-deploy-log "$SKILL/scripts/drivers/check-deploy-log.sh" drive check-deploy-log

caso "mutante omit_sin_estado: unarmed sin asercion de estado se pone rojo"
reset_art
mut="$SANDBOX/gate-omit-state.sh"
copy_driver gate-turn "$SANDBOX/gate-turn.src.sh"
if sed_must_change "$SANDBOX/gate-turn.src.sh" "$mut" \
  '/assert:sin_estado/,/assert:sin_estado_end/d' \
  "omit_sin_estado"
then
  out="$(ctrl_drv "$mut" drive-gate-scenario 01-sin-armar 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail gate-turn sin_estado '\(sin estado\)' "$rc"
fi

caso "mutante omit_contract: armed sin contrato se pone rojo"
reset_art
mut="$SANDBOX/gate-omit-contract.sh"
if sed_must_change "$SANDBOX/gate-turn.src.sh" "$mut" \
  '/assert:contract_json/,/assert:contract_json_end/d' \
  "omit_contract"
then
  out="$(ctrl_drv "$mut" drive-gate-scenario 02-armado-contrato 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail gate-turn contract_json 'SUMMONAIKIT HARNESS REQUIRED' "$rc"
fi

caso "mutante omit_harness_state: armed sin estado se pone rojo"
reset_art
mut="$SANDBOX/gate-omit-hstate.sh"
if sed_must_change "$SANDBOX/gate-turn.src.sh" "$mut" \
  '/assert:harness_state/,/assert:harness_state_end/d' \
  "omit_harness_state"
then
  out="$(ctrl_drv "$mut" drive-gate-scenario 02-armado-contrato 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail gate-turn harness_state 'harness-state' "$rc"
fi

caso "mutante omit_stop_rejected: Stop sin exit 2 se pone rojo"
reset_art
mut="$SANDBOX/gate-omit-stop.sh"
if sed_must_change "$SANDBOX/gate-turn.src.sh" "$mut" \
  '/assert:stop_rejected/,/assert:stop_rejected_end/d' \
  "omit_stop_rejected"
then
  out="$(ctrl_drv "$mut" drive-gate-scenario 07-evidencia-incompleta 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail gate-turn stop_rejected 'stop exit 2' "$rc"
fi

caso "mutante zero_stop_exit: el nombre evidencia no acredita Stop"
reset_art
mut="$SANDBOX/gate-zero-stop.sh"
if sed_must_change "$SANDBOX/gate-turn.src.sh" "$mut" \
  's/kv("STOP_EXIT", stop_exit)/kv("STOP_EXIT", "")/' \
  "zero_stop_exit"
then
  out="$(ctrl_drv "$mut" drive-gate-scenario 07-evidencia-incompleta 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail gate-turn stop_rejected 'stop exit 2' "$rc"
fi

caso "mutante omit_dry_run_no_write: quitar no-write se pone rojo"
reset_art
copy_driver install-guardian "$SANDBOX/install.src.sh"
mut="$SANDBOX/install-omit-nowrite.sh"
if sed_must_change "$SANDBOX/install.src.sh" "$mut" \
  '/assert:dry_run_no_write/,/assert:dry_run_no_write_end/d' \
  "omit_dry_run_no_write"
then
  out="$(ctrl_drv "$mut" drive-install-dry-run 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail install-guardian dry_run_no_write 'unchanged|ausente|sin.delta' "$rc"
fi

caso "mutante write_on_dry_run: escribir en el dest del dry-run se observa"
reset_art
mut="$SANDBOX/install-write-dry.sh"
if sed_must_change "$SANDBOX/install.src.sh" "$mut" \
  's/SAIKIT_FM_DRY_RUN=1/SAIKIT_FM_DRY_RUN=0/' \
  "write_on_dry_run"
then
  vtmp="$(python3 - "$STATE/state.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["tmpdir"])
PY
)"
  dest_probe="$vtmp/dry-dest-probe"
  : > "$dest_probe"
  out="$(SAIKIT_FM_DRY_DEST="$vtmp/fm-dry-dest.sh" \
    ctrl_drv "$mut" drive-install-dry-run 2>&1)" && rc=0 || rc=$?
  if [ -f "$vtmp/fm-dry-dest.sh" ]; then
    printf '    (discriminante: write_on_dry_run creo el dest)\n'
    [ "$rc" -ne 0 ] || assert_missing_or_fail install-guardian dry_run_no_write \
      'unchanged|ausente|sin.delta' "$rc"
  else
    assert_missing_or_fail install-guardian dry_run_no_write \
      'unchanged|ausente|sin.delta' "$rc"
  fi
fi

caso "mutante accept_stale_ledger: atrasado como OK se pone rojo"
reset_art
copy_driver audit-ledger "$SANDBOX/ledger.src.sh"
mut="$SANDBOX/ledger-accept-stale.sh"
if sed_must_change "$SANDBOX/ledger.src.sh" "$mut" \
  '/assert:stale_reason/,/assert:stale_reason_end/d' \
  "accept_stale_ledger"
then
  out="$(ctrl_drv "$mut" drive audit-ledger 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail audit-ledger stale_reason 'LEDGER DESACTUALIZADO' "$rc"
fi

caso "mutante accept_dup_pr: PR duplicado como OK se pone rojo"
reset_art
copy_driver check-deploy-log "$SANDBOX/deploy.src.sh"
mut="$SANDBOX/deploy-accept-dup.sh"
if sed_must_change "$SANDBOX/deploy.src.sh" "$mut" \
  '/assert:reason_dup_pr/,/assert:reason_dup_pr_end/d' \
  "accept_dup_pr"
then
  out="$(ctrl_drv "$mut" drive check-deploy-log 2>&1)" && rc=0 || rc=$?
  assert_missing_or_fail check-deploy-log reason_dup_pr '#203' "$rc"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_existing"
exit 0
