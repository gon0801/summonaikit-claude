#!/usr/bin/env bash
# tests/test_feature_map_evidence.sh — 19.3: evidencia v1 por intento exclusivo.
#
# Mutaciones (SAIKIT_VERIFY_MUTATE). Cada knob, aplicada, pone rojo el caso
# nombrado (la proteccion deja de atrapar / el intento valido se corrompe):
#   skip_empty_guard         — empty-steps-exit-0
#   skip_required_assertions — omitted-required
#   lie_counts               — false-counts
#   exit_summary_mismatch    — exit-summary-incoherent
#   degrade_fail_to_unknown  — fail-dominates-unknown
#   skip_redact              — secret-never-in-artifacts
#   reuse_attempt_id         — exclusive-attempt-ids
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SKILL="$repo/.cursor/skills/verify-summonaikit"
EVID="$SKILL/scripts/lib/evidence.py"
CTRL="$SKILL/scripts/control-summonaikit"
ART="$SANDBOX/verify-artifacts"
STATE="$SANDBOX/verify-state"
mkdir -p "$ART" "$STATE"

# Tokens sintéticos armados en runtime (no literales contiguos en el archivo).
form_token() {
  local cola36='FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE'
  local cola16='FAKEFAKEFAKEFAKE'
  case "$1" in
    ghp_)        printf 'ghp_%s' "$cola36" ;;
    github_pat_) printf 'github_pat_%s' "$cola36" ;;
    gho_)        printf 'gho_%s' "$cola36" ;;
    sk-)         printf 'sk-proj-%s' "$cola36" ;;
    AKIA)        printf 'AKIA%s' "$cola16" ;;
    xoxb-)       printf 'xox%s' "b-1234567890-$cola16" ;;
    *)           printf '' ;;
  esac
}

ev() {
  PYTHONDONTWRITEBYTECODE=1 python3 "$EVID" "$@"
}

ev_mut() {
  local m="$1"; shift
  SAIKIT_VERIFY_MUTATE="$m" PYTHONDONTWRITEBYTECODE=1 python3 "$EVID" "$@"
}

# create-attempt imprime ATTEMPT_ID= y ATTEMPT_DIR=
create_attempt() {
  local run_id="$1" feature_id="$2"
  shift 2
  ev create-attempt --artifacts "$ART" --run-id "$run_id" --feature-id "$feature_id" \
    --repo "$repo" "$@"
}

parse_kv() {
  local key="$1" text="$2"
  printf '%s\n' "$text" | sed -n "s/^${key}=//p" | head -1
}

hash_tree() {
  # cksum estable de todos los archivos regulares del intento (ordenados).
  local d="$1"
  ( cd "$d" && find . -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      cksum "$f"
    done )
}

# ---------------------------------------------------------------------------
# Fuentes presentes
# ---------------------------------------------------------------------------
caso "evidence.py y schemas v1 existen y parsean"
[ -f "$EVID" ] || malo "falta scripts/lib/evidence.py"
[ -f "$SKILL/schemas/step.schema.json" ] || malo "falta schemas/step.schema.json"
[ -f "$SKILL/schemas/summary.schema.json" ] || malo "falta schemas/summary.schema.json"
[ -f "$SKILL/schemas/doctor.schema.json" ] || malo "falta schemas/doctor.schema.json (stub)"
if [ -f "$EVID" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    "import ast,pathlib; ast.parse(pathlib.Path(r'$EVID').read_text(encoding='utf-8'))" \
    || malo "evidence.py no parsea"
fi

# ---------------------------------------------------------------------------
# Intento exclusivo + escritura antes de ejecutar
# ---------------------------------------------------------------------------
caso "create-attempt escribe dir exclusivo antes de ejecutar"
out="$(create_attempt "run-a" "feat-a" --mode sandbox --cases "c1" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  malo "create-attempt fallo: $out"
  AID=""; ADIR=""
else
  AID="$(parse_kv ATTEMPT_ID "$out")"
  ADIR="$(parse_kv ATTEMPT_DIR "$out")"
  [ -n "$AID" ] || malo "create-attempt sin ATTEMPT_ID: $out"
  [ -n "$ADIR" ] && [ -d "$ADIR" ] || malo "create-attempt sin dir: $out"
  case "$ADIR" in
    */run-a/feat-a/"$AID") ;;
    *) malo "layout no es artifacts/<run>/<feature>/<attempt>: $ADIR" ;;
  esac
  [ -f "$ADIR/steps.jsonl" ] || malo "falta steps.jsonl al crear (escribir antes de ejecutar)"
fi

caso "exclusive-attempt-ids: dos creates no comparten dir"
out2="$(create_attempt "run-a" "feat-a" --mode sandbox --cases "c1" 2>&1)" && rc2=0 || rc2=$?
if [ "$rc2" -ne 0 ]; then
  malo "segundo create-attempt fallo: $out2"
else
  AID2="$(parse_kv ATTEMPT_ID "$out2")"
  ADIR2="$(parse_kv ATTEMPT_DIR "$out2")"
  [ -n "$AID2" ] && [ "$AID2" != "$AID" ] \
    || malo "attempt_id reusado: '$AID' vs '$AID2'"
  [ -n "$ADIR2" ] && [ "$ADIR2" != "$ADIR" ] \
    || malo "attempt dir compartido: '$ADIR' vs '$ADIR2'"
  [ -d "$ADIR" ] && [ -d "$ADIR2" ] || malo "un intento piso al otro"
fi

# ---------------------------------------------------------------------------
# Agregacion PASS/0 FAIL/1 unknown/3
# ---------------------------------------------------------------------------
append_pass() {
  local dir="$1" case_id="$2" asid="$3"
  ev append-step --attempt-dir "$dir" --type assertion \
    --case-id "$case_id" --step-id "s-$asid" --assertion-id "$asid" \
    --expected pass --observed pass --result PASS
}

make_pass_attempt() {
  local run="$1" feat="$2" case_id="$3"
  shift 3
  local req="$*"
  local created adir
  created="$(create_attempt "$run" "$feat" --mode sandbox --cases "$case_id" \
    --required-assertions "$req" 2>&1)" || { printf '%s\n' "$created"; return 1; }
  adir="$(parse_kv ATTEMPT_DIR "$created")"
  ev append-step --attempt-dir "$adir" --type action \
    --case-id "$case_id" --step-id "act-1" --command "ev --synth" \
    --tool-exit 0 --observation "ran" || return 1
  local a
  for a in $req; do
    append_pass "$adir" "$case_id" "$a" || return 1
  done
  printf '%s\n' "$adir"
}

caso "PASS/0: aserciones requeridas observadas y validas"
AD_PASS="$(make_pass_attempt "run-pass" "feat-p" "c1" "a1" "a2" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ] || [ ! -d "$AD_PASS" ]; then
  malo "no se pudo armar intento PASS: $AD_PASS"
else
  fout="$(ev finalize --attempt-dir "$AD_PASS" --required-assertions "a1 a2" 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 0 ] || malo "finalize PASS debio exit 0: $fout"
  [ "$(parse_kv result "$fout")" = PASS ] || malo "result no PASS: $fout"
  [ "$(parse_kv exit_code "$fout")" = 0 ] || malo "exit_code no 0: $fout"
  [ -f "$AD_PASS/summary.json" ] || malo "falta summary.json"
  python3 - <<PY || malo "summary PASS invalido"
import json
from pathlib import Path
s=json.loads(Path("$AD_PASS/summary.json").read_text())
assert s.get("result")=="PASS" and s.get("exit_code")==0
assert s.get("schema_version")==1 or s.get("version")==1
steps=Path("$AD_PASS/steps.jsonl").read_text().strip().splitlines()
assert steps, "steps vacio"
PY
fi

caso "FAIL/1: asercion fallida observada"
created="$(create_attempt "run-fail" "feat-f" --mode sandbox --cases "c1" \
  --required-assertions "need" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  malo "create FAIL intento: $created"
else
  AD_FAIL="$(parse_kv ATTEMPT_DIR "$created")"
  ev append-step --attempt-dir "$AD_FAIL" --type action \
    --case-id c1 --step-id act --tool-exit 1 --observation boom >/dev/null
  ev append-step --attempt-dir "$AD_FAIL" --type assertion \
    --case-id c1 --step-id s-need --assertion-id need \
    --expected ok --observed boom --result FAIL >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_FAIL" --required-assertions need 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 1 ] || malo "finalize FAIL debio exit 1 (got $frc): $fout"
  [ "$(parse_kv result "$fout")" = FAIL ] || malo "result no FAIL: $fout"
  [ "$(parse_kv exit_code "$fout")" = 1 ] || malo "exit_code no 1: $fout"
fi

caso "unknown/3: parte obligatoria no observada, sin FAIL"
created="$(create_attempt "run-unk" "feat-u" --mode sandbox --cases "c1" \
  --required-assertions "need" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  malo "create unknown intento: $created"
else
  AD_UNK="$(parse_kv ATTEMPT_DIR "$created")"
  ev append-step --attempt-dir "$AD_UNK" --type action \
    --case-id c1 --step-id act --tool-exit "" --observation "never started" >/dev/null
  ev append-step --attempt-dir "$AD_UNK" --type assertion \
    --case-id c1 --step-id s-need --assertion-id need \
    --expected ok --observed missing --result unknown >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_UNK" --required-assertions need 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 3 ] || malo "finalize unknown debio exit 3 (got $frc): $fout"
  [ "$(parse_kv result "$fout")" = unknown ] || malo "result no unknown: $fout"
  [ "$(parse_kv exit_code "$fout")" = 3 ] || malo "exit_code no 3: $fout"
fi

caso "fail-dominates-unknown: FAIL gana a unknown"
created="$(create_attempt "run-dom" "feat-d" --mode sandbox --cases "c1 c2" \
  --required-assertions "a b" 2>&1)" || true
AD_DOM="$(parse_kv ATTEMPT_DIR "$created")"
if [ ! -d "$AD_DOM" ]; then
  malo "no hay intento para dominancia: $created"
else
  ev append-step --attempt-dir "$AD_DOM" --type assertion \
    --case-id c1 --step-id s-a --assertion-id a \
    --expected ok --observed no --result FAIL >/dev/null
  ev append-step --attempt-dir "$AD_DOM" --type assertion \
    --case-id c2 --step-id s-b --assertion-id b \
    --expected ok --observed "?" --result unknown >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_DOM" --required-assertions "a b" 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 1 ] || malo "FAIL+unknown debio exit 1: $fout"
  [ "$(parse_kv result "$fout")" = FAIL ] || malo "FAIL no domino unknown: $fout"
fi

caso "unknown domina PASS"
created="$(create_attempt "run-up" "feat-up" --mode sandbox --cases "c1 c2" \
  --required-assertions "a b" 2>&1)" || true
AD_UP="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_UP" ]; then
  append_pass "$AD_UP" c1 a >/dev/null
  ev append-step --attempt-dir "$AD_UP" --type assertion \
    --case-id c2 --step-id s-b --assertion-id b \
    --expected ok --observed "?" --result unknown >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_UP" --required-assertions "a b" 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 3 ] || malo "unknown+PASS debio exit 3: $fout"
  [ "$(parse_kv result "$fout")" = unknown ] || malo "unknown no domino PASS: $fout"
fi

caso "tool_exit nativo no es exit_code"
created="$(create_attempt "run-te" "feat-te" --mode sandbox --cases "c1" \
  --required-assertions "neg" 2>&1)" || true
AD_TE="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_TE" ]; then
  ev append-step --attempt-dir "$AD_TE" --type action \
    --case-id c1 --step-id act --tool-exit 2 --observation "native 2" >/dev/null
  ev append-step --attempt-dir "$AD_TE" --type assertion \
    --case-id c1 --step-id s-neg --assertion-id neg \
    --expected reject --observed "reject no-side-effects" --result PASS >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_TE" --required-assertions neg 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 0 ] || malo "rechazo esperado bien observado debio PASS/0: $fout"
  python3 - <<PY || malo "tool_exit se perdio o se copio a exit_code"
import json
from pathlib import Path
d=Path("$AD_TE")
s=json.loads((d/"summary.json").read_text())
assert s.get("exit_code")==0 and s.get("result")=="PASS"
found=False
for line in (d/"steps.jsonl").read_text().splitlines():
    if not line.strip():
        continue
    rec=json.loads(line)
    if rec.get("type")=="action":
        assert rec.get("tool_exit")==2, rec
        found=True
assert found, "sin action tool_exit=2"
PY
fi

# ---------------------------------------------------------------------------
# DoD: vacio / omitida / conteos / incoherencia / degradar = rojos
# ---------------------------------------------------------------------------
caso "empty-steps-exit-0: pasos vacios son FAIL del verificador"
created="$(create_attempt "run-empty" "feat-e" --mode sandbox --cases "c1" 2>&1)" || true
AD_EMPTY="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_EMPTY" ]; then
  fout="$(ev finalize --attempt-dir "$AD_EMPTY" --required-assertions need 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 1 ] || malo "empty-steps-exit-0 debio FAIL/1 (got $frc): $fout"
  [ "$(parse_kv result "$fout")" = FAIL ] || malo "empty no marco FAIL: $fout"
fi

caso "omitted-required: asercion omitida es FAIL"
created="$(create_attempt "run-omit" "feat-o" --mode sandbox --cases "c1" \
  --required-assertions "need extra" 2>&1)" || true
AD_OMIT="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_OMIT" ]; then
  ev append-step --attempt-dir "$AD_OMIT" --type action \
    --case-id c1 --step-id act --tool-exit 0 --observation echo-ok >/dev/null
  append_pass "$AD_OMIT" c1 need >/dev/null
  fout="$(ev finalize --attempt-dir "$AD_OMIT" --required-assertions "need extra" 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 1 ] || malo "omitted-required debio FAIL/1 (got $frc): $fout"
fi

caso "false-counts: validate rechaza conteos mentidos"
if [ -d "${AD_PASS:-}" ]; then
  python3 - <<PY
import json
from pathlib import Path
p=Path("$AD_PASS")/"summary.json"
s=json.loads(p.read_text())
s["step_count"]=999
s["assertion_count"]=999
p.write_text(json.dumps(s), encoding="utf-8")
PY
  vout="$(ev validate --attempt-dir "$AD_PASS" 2>&1)" && vrc=0 || vrc=$?
  [ "$vrc" -eq 1 ] || malo "false-counts debio ser validate FAIL: $vout"
  # restaurar via re-finalize limpio no hace falta; este dir ya esta sucio
fi

caso "exit-summary-incoherent: PASS con exit_code 1 es rojo"
created="$(create_attempt "run-mis" "feat-m" --mode sandbox --cases "c1" \
  --required-assertions "a1" 2>&1)" || true
AD_MIS="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_MIS" ]; then
  append_pass "$AD_MIS" c1 a1 >/dev/null
  ev finalize --attempt-dir "$AD_MIS" --required-assertions a1 >/dev/null 2>&1 || true
  python3 - <<PY
import json
from pathlib import Path
p=Path("$AD_MIS")/"summary.json"
s=json.loads(p.read_text())
s["result"]="PASS"
s["exit_code"]=1
p.write_text(json.dumps(s), encoding="utf-8")
PY
  vout="$(ev validate --attempt-dir "$AD_MIS" 2>&1)" && vrc=0 || vrc=$?
  [ "$vrc" -eq 1 ] || malo "exit-summary-incoherent debio validate FAIL: $vout"
fi

# ---------------------------------------------------------------------------
# Redaccion
# ---------------------------------------------------------------------------
caso "secret-never-in-artifacts: secreto sintetico no queda en claro"
TOK_GHP="$(form_token ghp_)"
TOK_PAT="$(form_token github_pat_)"
TOK_GHO="$(form_token gho_)"
TOK_SK="$(form_token sk-)"
TOK_AKIA="$(form_token AKIA)"
TOK_XOX="$(form_token xoxb-)"
created="$(create_attempt "run-sec" "feat-s" --mode sandbox --cases "c1" \
  --required-assertions "a1" 2>&1)" || true
AD_SEC="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_SEC" ]; then
  ev append-step --attempt-dir "$AD_SEC" --type action \
    --case-id c1 --step-id act \
    --command "curl --token=${TOK_GHP} https://user:p4ss@example.test/x" \
    --tool-exit 0 \
    --observation "password=s3cret ${TOK_PAT} ${TOK_GHO} key=${TOK_SK} ${TOK_AKIA} ${TOK_XOX}" \
    >/dev/null
  append_pass "$AD_SEC" c1 a1 >/dev/null
  ev finalize --attempt-dir "$AD_SEC" --required-assertions a1 >/dev/null 2>&1 || true
  leaked=0
  for tok in "$TOK_GHP" "$TOK_PAT" "$TOK_GHO" "$TOK_SK" "$TOK_AKIA" "$TOK_XOX" \
             "password=s3cret" "token=${TOK_GHP}" "user:p4ss@"; do
    if grep -RFq -- "$tok" "$AD_SEC" 2>/dev/null; then
      malo "secreto sintetico en artefactos: $tok"
      leaked=1
    fi
  done
  [ "$leaked" -eq 0 ] || true
  grep -RFq '[REDACTED]' "$AD_SEC" \
    || malo "no aparecio [REDACTED] en artefactos"
fi

# ---------------------------------------------------------------------------
# Reintento + cleanup conservan rojo
# ---------------------------------------------------------------------------
caso "reintento+cleanup conservan hash del intento FAIL previo"
created="$(create_attempt "run-keep" "feat-k" --mode sandbox --cases "c1" \
  --required-assertions "need" 2>&1)" || true
AD_KEEP="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_KEEP" ]; then
  ev append-step --attempt-dir "$AD_KEEP" --type assertion \
    --case-id c1 --step-id s --assertion-id need \
    --expected ok --observed no --result FAIL >/dev/null
  ev finalize --attempt-dir "$AD_KEEP" --required-assertions need >/dev/null 2>&1 || true
  h1="$(hash_tree "$AD_KEEP")"
  [ -n "$h1" ] || malo "hash vacio del intento FAIL"
  # cleanup del controlador (sin run activo igual conserva artifacts/)
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cleanup >/dev/null 2>&1 || true
  [ -d "$AD_KEEP" ] || malo "cleanup borro el intento FAIL"
  h1b="$(hash_tree "$AD_KEEP")"
  [ "$h1" = "$h1b" ] || malo "cleanup muto el hash del FAIL previo"
  created2="$(create_attempt "run-keep" "feat-k" --mode sandbox --cases "c1" \
    --required-assertions need 2>&1)" || true
  AD_KEEP2="$(parse_kv ATTEMPT_DIR "$created2")"
  [ -n "$AD_KEEP2" ] && [ "$AD_KEEP2" != "$AD_KEEP" ] \
    || malo "reintento reuso el dir del FAIL"
  [ -d "$AD_KEEP" ] || malo "reintento borro el FAIL previo"
  h1c="$(hash_tree "$AD_KEEP")"
  [ "$h1" = "$h1c" ] || malo "reintento muto el hash del FAIL previo"
fi

# ---------------------------------------------------------------------------
# Mutaciones discriminantes
# ---------------------------------------------------------------------------
caso "mutacion skip_empty_guard: empty-steps-exit-0 deja de atrapar"
created="$(create_attempt "run-m-empty" "feat-me" --mode sandbox --cases "c1" 2>&1)" || true
AD_ME="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_ME" ]; then
  ev finalize --attempt-dir "$AD_ME" --required-assertions need >/dev/null 2>&1 && \
    malo "baseline empty-steps debio fallar"
  fout="$(ev_mut skip_empty_guard finalize --attempt-dir "$AD_ME" --required-assertions need 2>&1)" && frc=0 || frc=$?
  if [ "$frc" -eq 0 ]; then
    :
  else
    malo "mutacion skip_empty_guard debio pasar en falso (protege empty-steps-exit-0): $fout"
  fi
fi

caso "mutacion skip_required_assertions: omitted-required deja de atrapar"
created="$(create_attempt "run-m-omit" "feat-mo" --mode sandbox --cases "c1" \
  --required-assertions "need extra" 2>&1)" || true
AD_MO="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_MO" ]; then
  ev append-step --attempt-dir "$AD_MO" --type action \
    --case-id c1 --step-id act --tool-exit 0 --observation echo-ok >/dev/null
  append_pass "$AD_MO" c1 need >/dev/null
  ev finalize --attempt-dir "$AD_MO" --required-assertions "need extra" >/dev/null 2>&1 && \
    malo "baseline omitted-required debio fallar"
  fout="$(ev_mut skip_required_assertions finalize --attempt-dir "$AD_MO" \
    --required-assertions "need extra" 2>&1)" && frc=0 || frc=$?
  [ "$frc" -eq 0 ] || malo "mutacion skip_required_assertions debio pasar en falso: $fout"
fi

caso "mutacion lie_counts: false-counts deja de atrapar"
AD_LC="$(make_pass_attempt "run-m-lie" "feat-ml" "c1" "a1" 2>&1)" || AD_LC=""
if [ -d "$AD_LC" ]; then
  ev_mut lie_counts finalize --attempt-dir "$AD_LC" --required-assertions a1 >/dev/null 2>&1 || true
  ev validate --attempt-dir "$AD_LC" >/dev/null 2>&1 && \
    malo "baseline false-counts (validate) debio fallar tras lie_counts"
  ev_mut lie_counts validate --attempt-dir "$AD_LC" >/dev/null 2>&1 \
    || malo "mutacion lie_counts en validate debio pasar en falso (protege false-counts)"
fi

caso "mutacion exit_summary_mismatch: exit-summary-incoherent deja de atrapar"
AD_XM="$(make_pass_attempt "run-m-xm" "feat-mx" "c1" "a1" 2>&1)" || AD_XM=""
if [ -d "$AD_XM" ]; then
  ev_mut exit_summary_mismatch finalize --attempt-dir "$AD_XM" --required-assertions a1 >/dev/null 2>&1 || true
  ev validate --attempt-dir "$AD_XM" >/dev/null 2>&1 && \
    malo "baseline exit-summary-incoherent debio fallar"
  ev_mut exit_summary_mismatch validate --attempt-dir "$AD_XM" >/dev/null 2>&1 \
    || malo "mutacion exit_summary_mismatch en validate debio pasar en falso"
fi

caso "mutacion degrade_fail_to_unknown: fail-dominates-unknown deja de atrapar"
created="$(create_attempt "run-m-deg" "feat-md" --mode sandbox --cases "c1" \
  --required-assertions need 2>&1)" || true
AD_MD="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_MD" ]; then
  ev append-step --attempt-dir "$AD_MD" --type assertion \
    --case-id c1 --step-id s --assertion-id need \
    --expected ok --observed no --result FAIL >/dev/null
  ev finalize --attempt-dir "$AD_MD" --required-assertions need >/dev/null 2>&1
  frc=$?
  [ "$frc" -eq 1 ] || malo "baseline fail-dominates debio exit 1 (got $frc)"
  fout="$(ev_mut degrade_fail_to_unknown finalize --attempt-dir "$AD_MD" \
    --required-assertions need 2>&1)" && mrc=0 || mrc=$?
  [ "$mrc" -eq 3 ] || malo "mutacion degrade_fail_to_unknown debio exit 3 (protege fail-dominates-unknown): $fout"
  [ "$(parse_kv result "$fout")" = unknown ] \
    || malo "degrade_fail_to_unknown no degradó a unknown: $fout"
fi

caso "mutacion skip_redact: secret-never-in-artifacts deja de atrapar"
TOK_M="$(form_token ghp_)"
created="$(create_attempt "run-m-red" "feat-mr" --mode sandbox --cases "c1" \
  --required-assertions a1 2>&1)" || true
AD_MR="$(parse_kv ATTEMPT_DIR "$created")"
if [ -d "$AD_MR" ]; then
  ev_mut skip_redact append-step --attempt-dir "$AD_MR" --type action \
    --case-id c1 --step-id act --command "tok=${TOK_M}" \
    --tool-exit 0 --observation "token=${TOK_M}" >/dev/null
  append_pass "$AD_MR" c1 a1 >/dev/null
  ev_mut skip_redact finalize --attempt-dir "$AD_MR" --required-assertions a1 >/dev/null 2>&1 || true
  grep -RFq -- "$TOK_M" "$AD_MR" \
    || malo "mutacion skip_redact debio persistir el secreto (protege secret-never-in-artifacts)"
fi

caso "mutacion reuse_attempt_id: exclusive-attempt-ids deja de atrapar"
out_a="$(ev_mut reuse_attempt_id create-attempt --artifacts "$ART" \
  --run-id run-reuse --feature-id feat-re --repo "$repo" --mode sandbox 2>&1)" || true
out_b="$(ev_mut reuse_attempt_id create-attempt --artifacts "$ART" \
  --run-id run-reuse --feature-id feat-re --repo "$repo" --mode sandbox 2>&1)" || true
ida="$(parse_kv ATTEMPT_ID "$out_a")"
idb="$(parse_kv ATTEMPT_ID "$out_b")"
dira="$(parse_kv ATTEMPT_DIR "$out_a")"
dirb="$(parse_kv ATTEMPT_DIR "$out_b")"
[ -n "$ida" ] && [ "$ida" = "$idb" ] \
  || malo "mutacion reuse_attempt_id debio chocar IDs (protege exclusive-attempt-ids): '$ida' vs '$idb'"
[ -n "$dira" ] && [ "$dira" = "$dirb" ] \
  || malo "mutacion reuse_attempt_id debio reusar el dir: '$dira' vs '$dirb'"

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_evidence"
exit 0
