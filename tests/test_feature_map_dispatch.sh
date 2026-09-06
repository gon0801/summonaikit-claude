#!/usr/bin/env bash
# tests/test_feature_map_dispatch.sh — 19.3: list-features, drive <id>, aliases.
#
# Mutaciones de evidencia (SAIKIT_VERIFY_MUTATE) que el dispatcher reenvia:
#   reuse_attempt_id — exclusive-attempt-ids en aliases/drive
# El resto de knobs se cubre en test_feature_map_evidence.sh.
#
# SAIKIT_VERIFY_SYNTHETIC_EXECUTOR=PASS|FAIL|unknown evita install real.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
mkdir -p "$STATE" "$ART"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

ctrl_synth() {
  local kind="$1"; shift
  SAIKIT_VERIFY_SYNTHETIC_EXECUTOR="$kind" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

# ---------------------------------------------------------------------------
# list-features: sin launch
# ---------------------------------------------------------------------------
caso "list-features enumera id/card/mode/scope sin launch"
[ -f "$STATE/state.json" ] && malo "state.json preexistente"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
[ ! -f "$STATE/state.json" ] || malo "list-features lanzo (creo state.json)"
n_attempts="$(find "$ART" -mindepth 3 -type d 2>/dev/null | wc -l | tr -d ' ')"
[ "${n_attempts:-0}" = 0 ] || malo "list-features escribio intentos: $out"
printf '%s' "$out" | grep -q 'install-guardian' \
  || malo "list-features sin install-guardian: $out"
printf '%s' "$out" | grep -Eq 'card=.*install-guardian' \
  || malo "list-features sin card: $out"
printf '%s' "$out" | grep -Eq 'mode=sandbox' \
  || malo "list-features sin mode: $out"
printf '%s' "$out" | grep -Eq 'scope=' \
  || malo "list-features sin scope: $out"
printf '%s' "$out" | grep -q 'gate-turn' || malo "falta gate-turn"
printf '%s' "$out" | grep -q 'audit-ledger' || malo "falta audit-ledger"
printf '%s' "$out" | grep -q 'check-deploy-log' || malo "falta check-deploy-log"

caso "list-features incluye blocked vivo y ninguna pending"
printf '%s' "$out" | grep -q 'saikit-postmerge' || malo "falta saikit-postmerge"
printf '%s' "$out" | grep -E 'id=saikit-postmerge' | grep -q 'status=active' \
  || malo "saikit-postmerge no esta active: $out"
printf '%s' "$out" | grep -q 'status=pending' \
  && malo "list-features aun declara pending: $out"
printf '%s' "$out" | grep -E 'id=merge-happy-path' | grep -q 'status=blocked' \
  || malo "merge-happy-path no sale blocked: $out"

# ---------------------------------------------------------------------------
# drive <id> sintetico: PASS/0 FAIL/1 unknown/3 + evidencia
# ---------------------------------------------------------------------------
reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

caso "drive <id> sintetico PASS/0 escribe evidencia exclusiva"
reset_art
out="$(ctrl_synth PASS drive install-guardian 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive PASS debio exit 0: $out"
n="$(find "$ART" -name summary.json | wc -l | tr -d ' ')"
[ "$n" -ge 1 ] || malo "drive PASS no escribio summary.json"
sum="$(find "$ART" -name summary.json | head -1)"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - <<PY || malo "summary PASS mal formado"
import json
from pathlib import Path
s=json.loads(Path("$sum").read_text())
assert s.get("result")=="PASS"
assert s.get("exit_code")==0
assert s.get("mode") in ("sandbox","simulated","live")
ident=s.get("identity") or s
assert ident.get("feature_id")=="install-guardian" or s.get("feature_id")=="install-guardian"
PY
fi
# layout artifacts/<run>/<feature>/<attempt>/
case "$sum" in
  */install-guardian/*/summary.json) ;;
  *) malo "layout drive no es .../install-guardian/<attempt>/summary.json: $sum" ;;
esac
[ -f "$(dirname "$sum")/steps.jsonl" ] || malo "drive PASS sin steps.jsonl"

caso "drive <id> sintetico FAIL/1"
reset_art
out="$(ctrl_synth FAIL drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "drive FAIL debio exit 1 (got $rc): $out"
sum="$(find "$ART" -name summary.json | head -1)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "drive FAIL sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - <<PY || malo "summary FAIL mal formado"
import json
from pathlib import Path
s=json.loads(Path("$sum").read_text())
assert s.get("result")=="FAIL" and s.get("exit_code")==1
PY
fi

caso "drive <id> sintetico unknown/3"
reset_art
out="$(ctrl_synth unknown drive check-deploy-log 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "drive unknown debio exit 3 (got $rc): $out"
sum="$(find "$ART" -name summary.json | head -1)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "drive unknown sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - <<PY || malo "summary unknown mal formado"
import json
from pathlib import Path
s=json.loads(Path("$sum").read_text())
assert s.get("result")=="unknown" and s.get("exit_code")==3
PY
fi

caso "drive <id> corre todos los casos requeridos (gate-turn)"
reset_art
out="$(ctrl_synth PASS drive gate-turn 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive gate-turn PASS fallo: $out"
sum="$(find "$ART" -path '*gate-turn*' -name summary.json | head -1)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "drive gate-turn sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - <<PY || malo "drive gate-turn no pidio ambos casos"
import json
from pathlib import Path
s=json.loads(Path("$sum").read_text())
cases=s.get("cases") or s.get("cases_requested") or []
if isinstance(cases, str):
    cases=cases.split()
text=" ".join(cases) if not isinstance(cases, str) else cases
assert "gate-unarmed" in text and "gate-armed" in text, cases
PY
fi

# ---------------------------------------------------------------------------
# Precondicion bloqueada no es PASS
# ---------------------------------------------------------------------------
caso "drive blocked (merge-happy-path) no es PASS"
reset_art
out="$(ctrl drive merge-happy-path 2>&1)" && rc=0 || rc=$?
[ "$rc" -ne 0 ] || malo "drive blocked no debe PASS/0: $out"
[ "$rc" -eq 3 ] || [ "$rc" -eq 1 ] \
  || malo "drive blocked exit $rc (se espera unknown/3 o FAIL/1): $out"
printf '%s' "$out" | grep -Eqi 'BLOCKED|pending|unknown|sin ejecutor|blocked|instancia' \
  || malo "drive blocked sin motivo: $out"
[ "$rc" -eq 0 ] && malo "blocked no puede ser PASS"

caso "drive activo sin instancia (doctor faltante) no es PASS"
reset_art
out="$(ctrl drive install-guardian 2>&1)" && rc=0 || rc=$?
[ "$rc" -ne 0 ] || malo "drive sin launch no debe PASS: $out"
printf '%s' "$out" | grep -Eqi 'BLOCKED|doctor|instancia|launch|unknown|FAIL|activo' \
  || malo "sin instancia sin motivo: $out"

# ---------------------------------------------------------------------------
# Aliases escriben evidencia y gate declara alcance parcial
# ---------------------------------------------------------------------------
caso "cuatro aliases sintetico PASS escriben evidencia v1"
reset_art
for alias in drive-install-dry-run drive-audit-ledger drive-deploy-log; do
  out="$(ctrl_synth PASS "$alias" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || malo "$alias sintetico PASS fallo: $out"
done
out="$(ctrl_synth PASS drive-gate-scenario 01-sin-armar 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive-gate-scenario sintetico PASS fallo: $out"
n="$(find "$ART" -name summary.json | wc -l | tr -d ' ')"
[ "$n" -ge 4 ] || malo "aliases no escribieron 4 summaries (hay $n)"

caso "alias gate-scenario declara alcance parcial"
sum="$(find "$ART" -path '*gate-turn*' -name summary.json | tail -1)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "sin summary de gate-turn alias"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - <<PY || malo "alias gate no declara scope parcial / solo un caso"
import json
from pathlib import Path
s=json.loads(Path("$sum").read_text())
scope=str(s.get("scope") or s.get("declared_scope") or "")
partial=s.get("scope_partial")
cases=s.get("cases") or s.get("cases_requested") or []
if isinstance(cases, str):
    cases=cases.split()
text=" ".join(str(c) for c in cases)
assert partial is True or "partial" in scope.lower() or "parcial" in scope.lower(), (scope, partial)
assert "gate-armed" not in text, cases
assert "gate-unarmed" in text or "01-sin-armar" in text, cases
PY
fi
printf '%s' "$out" | grep -Eqi 'partial|parcial|alcance' \
  || malo "stdout del alias gate no declara alcance parcial: $out"

# ---------------------------------------------------------------------------
# Reintento de alias conserva intento previo
# ---------------------------------------------------------------------------
caso "reintento de alias no pisa el intento anterior"
reset_art
ctrl_synth FAIL drive-audit-ledger >/dev/null 2>&1 || true
first="$(find "$ART" -name summary.json | head -1)"
[ -n "$first" ] && [ -f "$first" ] || malo "primer alias FAIL sin summary"
h1=""
if [ -n "$first" ] && [ -f "$first" ]; then
  h1="$(cksum "$first")"
fi
ctrl_synth PASS drive-audit-ledger >/dev/null 2>&1 || true
if [ -n "$first" ]; then
  [ -f "$first" ] || malo "reintento borro summary FAIL"
  [ -n "$h1" ] && [ "$(cksum "$first")" = "$h1" ] || malo "reintento muto el summary FAIL"
fi
n="$(find "$ART" -name summary.json | wc -l | tr -d ' ')"
[ "$n" -ge 2 ] || malo "reintento no creo un segundo intento (n=$n)"

caso "mutacion reuse_attempt_id en drive choca directorios"
reset_art
SAIKIT_VERIFY_MUTATE=reuse_attempt_id SAIKIT_VERIFY_SYNTHETIC_EXECUTOR=PASS \
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" drive audit-ledger >/dev/null 2>&1 || true
SAIKIT_VERIFY_MUTATE=reuse_attempt_id SAIKIT_VERIFY_SYNTHETIC_EXECUTOR=FAIL \
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" drive audit-ledger >/dev/null 2>&1 || true
n="$(find "$ART" -name summary.json | wc -l | tr -d ' ')"
[ "$n" -eq 1 ] || malo "reuse_attempt_id debio dejar 1 summary (hay $n; protege exclusive-attempt-ids)"

# ---------------------------------------------------------------------------
# SKILL.md documenta los comandos nuevos
# ---------------------------------------------------------------------------
caso "SKILL.md documenta list-features y drive"
grep -q 'list-features' "$SKILL/SKILL.md" || malo "SKILL.md no documenta list-features"
grep -Eq 'drive <id>|drive \`|<id\>`' "$SKILL/SKILL.md" \
  || grep -q 'drive <id>' "$SKILL/SKILL.md" \
  || malo "SKILL.md no documenta drive <id>"

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_dispatch"
exit 0
