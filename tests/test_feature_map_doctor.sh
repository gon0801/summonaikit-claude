#!/usr/bin/env bash
# tests/test_feature_map_doctor.sh — 19.5: doctor granular por feature.
#
# Mutaciones discriminantes (SAIKIT_VERIFY_MUTATE). Cada una pone rojo un
# caso identificado si se quita la guarda:
#   local_miss_global  — falta-gh-solo-live (la falta local se vuelve global)
#   blocked_as_pass    — blocked-no-es-pass (BLOCKED se presenta como PASS)
#   fake_gh_as_live    — gh-falso-no-es-vivo (un gh script acredita live)
#   skip_isolation     — escape-bloquea-todo (un escape deja de tumbar drivers)
#
# Falta de dep = unknown/MISSING; corrupción observada = FAIL;
# MISSING/BLOCKED nunca son resultado, quedan bajo unknown.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
DOCTOR="$SKILL/scripts/lib/doctor.py"
SCHEMA="$SKILL/schemas/doctor.schema.json"
CATALOG="$SKILL/features/catalog.json"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
ORIG_PATH="$PATH"
mkdir -p "$STATE" "$ART"

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

ctrl_mut() {
  local m="$1"; shift
  SAIKIT_VERIFY_MUTATE="$m" SAIKIT_VERIFY_STATE="$STATE" \
    SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" "$@"
}

doctor_py() {
  PYTHONDONTWRITEBYTECODE=1 python3 "$DOCTOR" \
    --skill "$SKILL" --repo "$repo" \
    --state-dir "$STATE" --artifacts "$ART" "$@"
}

doctor_py_mut() {
  local m="$1"; shift
  SAIKIT_VERIFY_MUTATE="$m" PYTHONDONTWRITEBYTECODE=1 python3 "$DOCTOR" \
    --skill "$SKILL" --repo "$repo" \
    --state-dir "$STATE" --artifacts "$ART" "$@"
}

reset_io() {
  PATH="$ORIG_PATH"
  export PATH
  rm -rf "$STATE" "$ART"
  mkdir -p "$STATE" "$ART"
  unset SAIKIT_VERIFY_PTY SAIKIT_VERIFY_MUTATE || true
}

# Oculta $1 sin descartar el directorio entero (en CI `gh` vive en /usr/bin
# junto a rm/mkdir; quitar ese dir rompe el harness). Construye un PATH de
# symlinks que omite solo el binario nombrado, para que which() → None.
hide_from_path() {
  local name="$1"
  local out="$SANDBOX/path-without-$name"
  local d f base
  rm -rf "$out"
  mkdir -p "$out"
  local IFS=':'
  for d in $ORIG_PATH; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      base="${f##*/}"
      [ "$base" = "$name" ] && continue
      [ -e "$out/$base" ] && continue
      ln -s "$f" "$out/$base" 2>/dev/null || true
    done
  done
  printf '%s' "$out"
}

install_fake_gh() {
  # $1=bin-dir $2=version-line $3=log-file
  local bindir="$1" ver="$2" log="$3"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >> "$log"
if [ "\$1" = "--version" ]; then
  printf '%s\\n' "$ver"
  exit 0
fi
printf 'quota-burned %s\\n' "\$*"
exit 0
EOF
  chmod +x "$bindir/gh"
}

# ---------------------------------------------------------------------------
# Fuentes
# ---------------------------------------------------------------------------
caso "doctor.py, schema v1 y helper en catalogo"
[ -f "$DOCTOR" ] || malo "falta scripts/lib/doctor.py"
[ -f "$SCHEMA" ] || malo "falta schemas/doctor.schema.json"
if [ -f "$DOCTOR" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    "import ast,pathlib; ast.parse(pathlib.Path(r'$DOCTOR').read_text(encoding='utf-8'))" \
    || malo "doctor.py no parsea"
fi
bash -n "$CTRL" || malo "bash -n fallo en control-summonaikit"
python3 - <<PY || malo "catalogo no clasifica doctor.py como helper internal"
import json
from pathlib import Path
c=json.loads(Path("$CATALOG").read_text())
h=(c.get("helpers") or {}).get("scripts/lib/doctor.py")
assert h and h.get("kind")=="internal", h
PY

# ---------------------------------------------------------------------------
# doctor.json + texto; instancia no es FAIL global (unknown/MISSING)
# ---------------------------------------------------------------------------
caso "doctor sin instancia escribe doctor.json y no es PASS de features con instance"
reset_io
out="$(ctrl doctor 2>&1)" && rc=0 || rc=$?
[ -f "$ART/doctor.json" ] || malo "doctor no escribio artifacts/doctor.json: $out"
if [ -f "$ART/doctor.json" ]; then
python3 - <<PY || malo "doctor.json no cumple schema v1"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
assert d.get("schema_version")==1
for k in ("features","ready","blocked","failed","isolation","result","exit_code"):
    assert k in d, k
assert d["isolation"]["result"] in ("PASS","FAIL")
assert d["result"] in ("PASS","FAIL","unknown")
assert d["exit_code"] in (0,1,3)
feats=d["features"]
assert "install-guardian" in feats
assert "gate-turn" in feats
assert "merge-happy-path" in feats
ig=feats["install-guardian"]
assert ig["result"] in ("PASS","FAIL","unknown")
assert ig["availability"] in ("ready","MISSING","BLOCKED","failed")
# sin instancia: instance-dependiente no es ready
assert ig["availability"]!="ready", ig
assert ig["result"]!="PASS", ig
PY
fi
[ "$rc" -eq 0 ] && malo "doctor sin instancia no debe salir 0/PASS: $out"
[ "$rc" -eq 3 ] || malo "doctor sin instancia debio unknown/3 (got $rc): $out"
printf '%s' "$out" | grep -Eq 'MISSING|unknown|instancia|instance' \
  || malo "sin instancia sin motivo MISSING/unknown: $out"
printf '%s' "$out" | grep -q 'doctor: PASS' \
  && malo "sin instancia no debe imprimir doctor: PASS: $out"

# ---------------------------------------------------------------------------
# falta gh solo afecta live
# ---------------------------------------------------------------------------
caso "falta-gh-solo-live: gh ausente no tumba gate ni simulated"
reset_io
PATH="$(hide_from_path gh)"
export PATH
command -v gh >/dev/null 2>&1 && malo "hide_from_path no oculto gh: $(command -v gh)"
out="$(doctor_py 2>&1)" && rc=0 || rc=$?
[ -f "$ART/doctor.json" ] || malo "falta-gh: sin doctor.json: $out"
python3 - <<PY || malo "falta-gh se filtro a no-live"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
gt=d["features"]["gate-turn"]
sm=d["features"]["saikit-merge"]
mh=d["features"]["merge-happy-path"]
def blob(feat):
    return json.dumps(feat, ensure_ascii=False).lower()
# live debe nombrar gh / MISSING
assert mh["result"]=="unknown", mh
assert mh["availability"]=="MISSING", mh
assert "gh" in blob(mh), mh
# gate (sandbox) no se bloquea por gh
assert "gh" not in blob(gt) or "missing" not in blob(gt).split("gh")[0], gt
reasons_gt=" ".join(str(x) for x in (
    [gt.get("reason","")] + [r.get("reason","") for r in (gt.get("requirements") or [])]
)).lower()
assert "gh" not in reasons_gt, gt
assert gt["availability"]!="failed"
# simulated no exige gh vivo
reasons_sm=" ".join(str(x) for x in (
    [sm.get("reason","")] + [r.get("reason","") for r in (sm.get("requirements") or [])]
)).lower()
assert sm["availability"]!="MISSING" or "gh" not in reasons_sm, sm
assert sm["result"]!="FAIL", sm
PY
# restaurar PATH (sandbox_init lo dejo en el entorno original + hide)
# re-export del PATH original: se recupera mas abajo por hide solo en subshells
true

# rehacer PATH limpio para el resto (el hide de arriba muto este shell)
# sandbox_init no guarda PATH original; reconstruir desde el login es frágil.
# Guardamos el PATH pre-hide al inicio del caso siguiente via /usr/bin/env.

# ---------------------------------------------------------------------------
# gh falso no acredita vivo; no quema cuota
# ---------------------------------------------------------------------------
caso "gh-falso-no-es-vivo: script en PATH no satisface live ni llama API"
reset_io
FAKEBIN="$SANDBOX/fake-bin"
GLOG="$SANDBOX/gh-argv.log"
rm -f "$GLOG"
install_fake_gh "$FAKEBIN" "gh version 2.98.0 (2026-08-20)" "$GLOG"
PATH="$FAKEBIN:$(hide_from_path gh)"
export PATH
out="$(doctor_py --feature-id merge-happy-path 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "gh falso: live debio unknown/3 (got $rc): $out"
python3 - <<PY || malo "gh falso acredito vivo"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
mh=d["features"]["merge-happy-path"]
assert mh["result"]=="unknown", mh
assert mh["availability"] in ("MISSING","BLOCKED"), mh
assert mh["availability"]!="ready", mh
blob=json.dumps(mh, ensure_ascii=False).lower()
assert "gh" in blob or "vivo" in blob or "live" in blob or "falso" in blob, mh
PY
if [ -f "$GLOG" ]; then
  grep -Eq '(^| )(api|pr|issue|run|auth)( |$)' "$GLOG" \
    && malo "doctor quemo cuota/API de gh: $(cat "$GLOG")"
  grep -q 'quota-burned' "$GLOG" \
    && malo "doctor invoco gh mas alla de --version: $(cat "$GLOG")"
fi
# simulated sigue observable con gh falso
out2="$(doctor_py --feature-id saikit-merge 2>&1)" && rc2=0 || rc2=$?
python3 - <<PY || malo "simulated se bloqueo por gh falso"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
sm=d["features"]["saikit-merge"]
assert sm["result"]!="FAIL", sm
reasons=json.dumps(sm, ensure_ascii=False).lower()
assert "live" not in reasons or sm["availability"]!="MISSING", sm
PY

# ---------------------------------------------------------------------------
# PTY: solo casos interactivos de setup / ci-minimo
# ---------------------------------------------------------------------------
caso "falta-pty-solo-interactivo: flags/defaults siguen observables"
reset_io
out="$(
  SAIKIT_VERIFY_PTY=missing PYTHONDONTWRITEBYTECODE=1 python3 "$DOCTOR" \
    --skill "$SKILL" --repo "$repo" \
    --state-dir "$STATE" --artifacts "$ART"
  2>&1
)" && rc=0 || rc=$?
python3 - <<PY || malo "falta PTY se filtro mal"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
sa=d["features"]["setup-autopilot"]
ci=d["features"]["ci-minimo"]
gt=d["features"]["gate-turn"]
def case(feat, cid):
    return (feat.get("cases") or {}).get(cid) or {}
# interactivos: unknown/MISSING
for feat, cid in ((sa,"setup-interactive"),(ci,"ci-interactive")):
    c=case(feat, cid)
    assert c, (feat.get("id"), cid, feat)
    assert c.get("result")=="unknown", c
    assert c.get("availability")=="MISSING", c
    blob=json.dumps(c, ensure_ascii=False).lower()
    assert "pty" in blob or "tty" in blob, c
# flags/defaults observables
for feat, cid in (
    (sa,"setup-flags"),(sa,"setup-defaults"),
    (ci,"ci-flags"),(ci,"ci-defaults"),
):
    c=case(feat, cid)
    assert c, (feat.get("id"), cid)
    assert c.get("availability")=="ready", c
    assert c.get("result")=="PASS", c
# gate no depende de PTY
reasons_gt=json.dumps(gt, ensure_ascii=False).lower()
assert "pty" not in reasons_gt, gt
PY

# ---------------------------------------------------------------------------
# fixture corrupto = FAIL (nunca unknown)
# ---------------------------------------------------------------------------
caso "fixture-corrupto-es-fail: JSON de escenarios mal formado"
reset_io
FX="$SANDBOX/fx-repo"
mkdir -p "$FX/tests/fixtures/escenarios/01-sin-armar"
printf '{not-json\n' > "$FX/tests/fixtures/escenarios/01-sin-armar/01.prompt.claude.json"
out="$(
  PYTHONDONTWRITEBYTECODE=1 python3 "$DOCTOR" \
    --skill "$SKILL" --repo "$FX" \
    --state-dir "$STATE" --artifacts "$ART" \
    --feature-id gate-turn 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "fixture corrupto debio FAIL/1 (got $rc): $out"
[ "$rc" -eq 3 ] && malo "fixture corrupto no debe unknown/3: $out"
python3 - <<PY || malo "corrupcion no se reporto como FAIL"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
gt=d["features"]["gate-turn"]
assert gt["result"]=="FAIL", gt
assert gt["availability"]=="failed", gt
assert d["result"]=="FAIL" and d["exit_code"]==1
assert "gate-turn" in d["failed"]
blob=json.dumps(gt, ensure_ascii=False).lower()
assert "corrupt" in blob or "mal formado" in blob or "json" in blob or "integr" in blob, gt
PY

# ---------------------------------------------------------------------------
# dependencia ausente = unknown/MISSING (no FAIL)
# ---------------------------------------------------------------------------
caso "dep-ausente-es-unknown: deploy-log.md faltante"
reset_io
EMPTY="$SANDBOX/empty-repo"
mkdir -p "$EMPTY/docs"
out="$(
  PYTHONDONTWRITEBYTECODE=1 python3 "$DOCTOR" \
    --skill "$SKILL" --repo "$EMPTY" \
    --state-dir "$STATE" --artifacts "$ART" \
    --feature-id check-deploy-log 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "dep ausente debio unknown/3 (got $rc): $out"
[ "$rc" -eq 1 ] && malo "dep ausente no debe FAIL/1: $out"
python3 - <<PY || malo "dep ausente no quedo MISSING/unknown"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
cd=d["features"]["check-deploy-log"]
assert cd["result"]=="unknown", cd
assert cd["availability"]=="MISSING", cd
blob=json.dumps(cd, ensure_ascii=False).lower()
assert "deploy-log" in blob or "missing" in blob, cd
assert cd["result"]!="FAIL"
assert d["exit_code"]==3
PY

# ---------------------------------------------------------------------------
# escape bloquea todo driver
# ---------------------------------------------------------------------------
caso "escape-bloquea-todo: STATE symlink tumba todas las features"
reset_io
mkdir -p "$SANDBOX/escaped-state"
ln -sfn "$SANDBOX/escaped-state" "$SANDBOX/state-link"
out="$(
  SAIKIT_VERIFY_STATE="$SANDBOX/state-link" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" doctor 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "escape debio FAIL/1 (got $rc): $out"
[ "$rc" -eq 3 ] && malo "escape no debe unknown/3: $out"
printf '%s' "$out" | grep -Eqi 'symlink|enlace|escape|físic|fisic' \
  || malo "escape sin motivo: $out"
if [ -f "$ART/doctor.json" ]; then
python3 - <<PY || malo "escape no tumbo todos los drivers"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
assert d["isolation"]["result"]=="FAIL", d["isolation"]
assert d["result"]=="FAIL" and d["exit_code"]==1
feats=d["features"]
assert feats, "sin features"
for fid, feat in feats.items():
    assert feat["result"]=="FAIL", (fid, feat)
    assert feat["availability"]=="failed", (fid, feat)
assert set(d["failed"])==set(feats)
assert d["ready"]==[]
PY
fi

# ---------------------------------------------------------------------------
# no lee perfiles del operador; no instala
# ---------------------------------------------------------------------------
caso "doctor no lee perfiles vivos ni escribe en ellos"
reset_io
CANARY="$HOME/.claude/hooks/summonaikit-harness.sh"
mkdir -p "$(dirname "$CANARY")"
printf 'OPERATOR-PROFILE-CANARY\n' > "$CANARY"
sha_before="$(cksum "$CANARY" | awk '{print $1" "$2}')"
out="$(ctrl doctor 2>&1)" || true
sha_after="$(cksum "$CANARY" | awk '{print $1" "$2}')"
[ "$sha_before" = "$sha_after" ] || malo "doctor muto el perfil sandbox/operador"
printf '%s' "$out" | grep -Fq 'OPERATOR-PROFILE-CANARY' \
  && malo "doctor echo el canario del perfil: $out"
if [ -f "$ART/doctor.json" ]; then
  grep -Fq 'OPERATOR-PROFILE-CANARY' "$ART/doctor.json" \
    && malo "doctor.json cita el canario del perfil"
fi

# ---------------------------------------------------------------------------
# doctor <id> acota el alcance
# ---------------------------------------------------------------------------
caso "doctor <id> reporta solo esa feature en el agregado"
reset_io
out="$(doctor_py --feature-id audit-ledger 2>&1)" && rc=0 || rc=$?
python3 - <<PY || malo "doctor <id> no acoto"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
assert d.get("scope")=="audit-ledger" or list(d["features"])==["audit-ledger"], d
assert "audit-ledger" in d["features"]
# el agregado no debe listar ajenas en ready/blocked/failed
for arr in d["ready"], d["blocked"], d["failed"]:
    assert all(x=="audit-ledger" for x in arr), arr
PY

# ---------------------------------------------------------------------------
# Mutaciones: cada guarda, un caso rojo nombrado
# ---------------------------------------------------------------------------
caso "mut-local-miss-global: local_miss_global pone gh en gate-turn"
reset_io
PATH="$(hide_from_path gh)"
export PATH
out_base="$(doctor_py 2>&1)" || true
python3 - <<PY || malo "baseline falta-gh-solo-live se rompio"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
gt=d["features"]["gate-turn"]
reasons=json.dumps(gt, ensure_ascii=False).lower()
assert "gh" not in reasons, gt
PY
out_mut="$(doctor_py_mut local_miss_global 2>&1)" || true
python3 - <<PY || malo "mutacion local_miss_global no globalizo la falta (protege falta-gh-solo-live)"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
gt=d["features"]["gate-turn"]
reasons=json.dumps(gt, ensure_ascii=False).lower()
assert "gh" in reasons, gt
assert gt["availability"] in ("MISSING","BLOCKED","failed") or gt["result"]=="unknown", gt
PY

caso "mut-blocked-as-pass: blocked_as_pass presenta BLOCKED como PASS"
reset_io
# live_authorization es BLOCKED aun con gh oficial (19.16: precondiciones, no vivo).
out_base="$(doctor_py --feature-id merge-happy-path 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] && malo "baseline blocked-no-es-pass no debe PASS/0: $out_base"
python3 - <<PY || malo "baseline merge-happy-path no esta BLOCKED/unknown"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
mh=d["features"]["merge-happy-path"]
assert mh["result"]=="unknown", mh
assert mh["availability"] in ("MISSING","BLOCKED"), mh
assert mh["result"]!="PASS"
found=False
for r in mh.get("requirements") or []:
    if r.get("kind")=="live_authorization" or "autoriz" in json.dumps(r, ensure_ascii=False).lower():
        assert r.get("availability")=="BLOCKED", r
        found=True
assert found, mh
PY
out_mut="$(doctor_py_mut blocked_as_pass --feature-id merge-happy-path 2>&1)" && mrc=0 || mrc=$?
python3 - <<PY || malo "mutacion blocked_as_pass no presento BLOCKED como PASS (protege blocked-no-es-pass)"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
mh=d["features"]["merge-happy-path"]
# el mutante miente: BLOCKED aparece como PASS
assert mh["result"]=="PASS" or any(
    r.get("result")=="PASS" and (
        r.get("kind")=="live_authorization"
        or r.get("availability")=="ready"
    )
    for r in (mh.get("requirements") or [])
    if r.get("kind")=="live_authorization" or "autoriz" in json.dumps(r, ensure_ascii=False).lower()
), mh
PY

caso "mut-fake-gh-as-live: fake_gh_as_live acepta script como vivo"
reset_io
FAKEBIN="$SANDBOX/fake-bin2"
GLOG="$SANDBOX/gh-argv2.log"
rm -f "$GLOG"
install_fake_gh "$FAKEBIN" "gh version 2.98.0 (2026-08-20)" "$GLOG"
PATH="$FAKEBIN:$(hide_from_path gh)"
export PATH
out_base="$(doctor_py --feature-id merge-happy-path 2>&1)" || true
python3 - <<PY || malo "baseline gh-falso-no-es-vivo se rompio"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
mh=d["features"]["merge-happy-path"]
reqs=mh.get("requirements") or []
gh=[r for r in reqs if r.get("kind")=="binary" and r.get("name")=="gh"]
assert gh, mh
assert gh[0].get("availability")!="ready", gh[0]
assert gh[0].get("result")!="PASS", gh[0]
PY
out_mut="$(doctor_py_mut fake_gh_as_live --feature-id merge-happy-path 2>&1)" || true
python3 - <<PY || malo "mutacion fake_gh_as_live no acredito el script (protege gh-falso-no-es-vivo)"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
mh=d["features"]["merge-happy-path"]
reqs=mh.get("requirements") or []
gh=[r for r in reqs if r.get("kind")=="binary" and r.get("name")=="gh"]
assert gh and gh[0].get("availability")=="ready" and gh[0].get("result")=="PASS", gh
PY

caso "mut-skip-isolation: skip_isolation deja de tumbar drivers ante escape"
reset_io
mkdir -p "$SANDBOX/escaped-state2"
ln -sfn "$SANDBOX/escaped-state2" "$SANDBOX/state-link2"
out_base="$(
  SAIKIT_VERIFY_STATE="$SANDBOX/state-link2" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" doctor 2>&1
)" && brc=0 || brc=$?
[ "$brc" -eq 1 ] || malo "baseline escape-bloquea-todo debio 1 (got $brc): $out_base"
out_mut="$(
  SAIKIT_VERIFY_MUTATE=skip_isolation \
    SAIKIT_VERIFY_STATE="$SANDBOX/state-link2" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" doctor 2>&1
)" && mrc=0 || mrc=$?
[ "$mrc" -eq 1 ] && printf '%s' "$out_mut" | grep -Eqi 'symlink|enlace|escape' \
  && malo "mutacion skip_isolation sigue fallando por escape (protege escape-bloquea-todo)"
if [ -f "$ART/doctor.json" ]; then
python3 - <<PY || malo "mutacion skip_isolation no omitio el fail global"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
# con la guarda apagada isolation no es FAIL global
assert d["isolation"]["result"]!="FAIL" or d["result"]!="FAIL", d["isolation"]
if d.get("features"):
    failed=all(f.get("result")=="FAIL" for f in d["features"].values())
    assert not failed, "todas las features siguen FAIL bajo skip_isolation"
PY
fi

# ---------------------------------------------------------------------------
# instancia plantada: features activas locales listas → doctor: PASS
# ---------------------------------------------------------------------------
caso "instancia propia: activas locales ready y doctor: PASS"
reset_io
HOME_RUN="$SANDBOX/verify-home"
mkdir -p "$HOME_RUN/.claude/hooks" "$HOME_RUN/tmp"
printf 'run_id=planted\ntoken=tok-planted-19-5\n' > "$HOME_RUN/.saikit-run"
chmod 600 "$HOME_RUN/.saikit-run"
cp "$repo/hooks/summonaikit-harness.sh" \
  "$HOME_RUN/.claude/hooks/summonaikit-harness.sh"
DEST="$HOME_RUN/.claude/hooks/summonaikit-harness.sh"
python3 - <<PY
import json
from pathlib import Path
Path("$STATE").mkdir(parents=True, exist_ok=True)
Path("$STATE/state.json").write_text(json.dumps({
  "schema_version": 1,
  "run_id": "planted",
  "launched_at": "20260906T000000Z",
  "repo": "$repo",
  "verify_home": "$HOME_RUN",
  "dest": "$DEST",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "$HOME_RUN/tmp",
  "owned_temps": ["$HOME_RUN", "$HOME_RUN/tmp"],
  "host_dests": {"claude": "$DEST"},
  "token": "tok-planted-19-5",
}, indent=2) + "\n", encoding="utf-8")
PY
out="$(ctrl doctor 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "doctor con instancia propia debio 0: $out"
printf '%s' "$out" | grep -q 'doctor: PASS' \
  || malo "doctor con instancia no dijo PASS: $out"
python3 - <<PY || malo "activas locales no quedaron ready"
import json
from pathlib import Path
d=json.loads(Path("$ART/doctor.json").read_text())
assert d["result"]=="PASS" and d["exit_code"]==0
for fid in ("install-guardian","gate-turn","audit-ledger","check-deploy-log"):
    f=d["features"][fid]
    assert f["result"]=="PASS" and f["availability"]=="ready", (fid, f)
    assert fid in d["ready"]
# blocked live no se acredita
mh=d["features"]["merge-happy-path"]
assert mh["result"]!="PASS", mh
assert mh["availability"] in ("MISSING","BLOCKED")
PY

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_doctor"
exit 0
