#!/usr/bin/env bash
# tests/test_feature_map_integration.sh — 19.17: integración y cierre honesto.
#
# DoD: catálogo sin pending ni legacy; cada exclusión con razón; cada
# activa/bloqueada con ejecutor y aserciones; drives locales + aliases +
# combo doctor→drive→reintento→cleanup; evidencia FAIL y unknown; superficie
# pública nueva rompe el candado; pytest verify/ observado en aislamiento;
# 18.27/18.26/18.10 en fichas; vivo inventariado y no observado.
#
# Mutaciones (lint --mutate):
#   accept_pending — pending de implementación deja de atrapar
#   accept_legacy  — legacy restante deja de atrapar
#   omit_discovery — superficie nueva deja de atrapar (candado de discovery)
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

LINT="$repo/.cursor/skills/verify-summonaikit/scripts/lint-feature-map.py"
SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
ORIG_PATH="$PATH"
mkdir -p "$STATE" "$ART"

run_lint() {
  python3 "$LINT" --repo "$1" --skill "$2" "${@:3}"
}

ctrl() {
  SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_HOOK_VIVO="$repo/hooks/summonaikit-harness.sh" \
    bash "$CTRL" "$@"
}

ctrl_synth() {
  local kind="$1"; shift
  SAIKIT_VERIFY_ALLOW_SYNTHETIC=1 \
  SAIKIT_VERIFY_SYNTHETIC_EXECUTOR="$kind" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_HOOK_VIVO="$repo/hooks/summonaikit-harness.sh" \
    bash "$CTRL" "$@"
}

reset_art() { rm -rf "$ART"; mkdir -p "$ART"; }

latest_summary() {
  local fid="$1"
  find "$ART" -path "*/*/${fid}/*/summary.json" -type f | tail -1
}

# Fixture skill/repo mínimo (mismo patrón que 19.1) para mutar el candado.
mk_min_skill() {
  local d="$1"
  mkdir -p "$d/features" "$d/scripts"
  cp "$CTRL" "$d/scripts/control-summonaikit"
  chmod +x "$d/scripts/control-summonaikit"
  cp "$LINT" "$d/scripts/lint-feature-map.py"
  if [ -d "$SKILL/scripts/lib" ]; then
    mkdir -p "$d/scripts/lib"
    for f in "$SKILL/scripts/lib"/*; do
      [ -f "$f" ] || continue
      case "$f" in *.pyc) continue ;; esac
      cp "$f" "$d/scripts/lib/"
    done
  fi
  for f in "$SKILL/features/"*.md "$SKILL/features/"*.json; do
    [ -f "$f" ] || continue
    cp "$f" "$d/features/"
  done
  if [ -d "$SKILL/schemas" ]; then
    mkdir -p "$d/schemas"
    cp "$SKILL/schemas/"*.json "$d/schemas/" 2>/dev/null || true
  fi
  if [ -d "$SKILL/scripts/drivers" ]; then
    mkdir -p "$d/scripts/drivers"
    cp "$SKILL/scripts/drivers/"*.sh "$d/scripts/drivers/" 2>/dev/null || true
  fi
}

mk_min_repo() {
  local d="$1"
  mkdir -p "$d/tools/lib" "$d/hooks" "$d/hosts/dsh/spy" "$d/hosts/dsh/test" \
    "$d/agents" "$d/recetas/pendientes" \
    "$d/skills/saikit-setup-autopilot" \
    "$d/skills/saikit-verificar-app" \
    "$d/skills/sencillo"
  python3 - <<PY
import json
from pathlib import Path
repo=Path("$d")
cat=json.loads(Path("$SKILL/features/catalog.json").read_text())
for path in list(cat["surfaces"])+list(cat["exclusions"]):
    p=repo/path
    p.parent.mkdir(parents=True, exist_ok=True)
    if not p.exists():
        p.write_text("# fixture\n", encoding="utf-8")
PY
}

# ---------------------------------------------------------------------------
# Inventario real: discovery + sin pending + sin legacy
# ---------------------------------------------------------------------------
caso "lint real descubre el checkout y cierra OK"
out="$(run_lint "$repo" "$SKILL" 2>&1)" || malo "lint real fallo: $out"
printf '%s\n' "$out" | grep -q 'feature-map: OK' || malo "sin OK: $out"

caso "catalogo real: cero pending, cero legacy, exclusiones con razon"
python3 - "$SKILL" <<'PY' || malo "catalogo real incompleto o con leftover"
import json, sys
from pathlib import Path
skill = Path(sys.argv[1])
cat = json.loads((skill / "features/catalog.json").read_text(encoding="utf-8"))
feats = cat.get("features") or {}
pending = [fid for fid, m in feats.items() if (m or {}).get("status") == "pending"]
if pending:
    raise SystemExit(f"pending de implementación: {pending}")
exclusions = cat.get("exclusions") or {}
for path, meta in exclusions.items():
    reason = (meta or {}).get("reason") if isinstance(meta, dict) else None
    if not reason:
        raise SystemExit(f"exclusión sin razón: {path}")
for fid, meta in feats.items():
    st = (meta or {}).get("status") or "active"
    if st not in ("active", "blocked"):
        raise SystemExit(f"{fid}: status ilegal {st!r}")
    desc = json.loads((skill / "features" / f"{fid}.json").read_text(encoding="utf-8"))
    ex = desc.get("executor") or {}
    if not ex:
        raise SystemExit(f"{fid}: sin ejecutor")
    if ex.get("kind") == "legacy":
        raise SystemExit(f"{fid}: legacy restante")
    if ex.get("kind") != "driver":
        raise SystemExit(f"{fid}: executor.kind={ex.get('kind')!r}")
    path = ex.get("path") or f"scripts/drivers/{fid}.sh"
    if not (skill / path).is_file():
        raise SystemExit(f"{fid}: driver ausente {path}")
    cases = desc.get("cases") or []
    if not cases:
        raise SystemExit(f"{fid}: sin cases")
    for c in cases:
        if not c.get("required_assertions"):
            raise SystemExit(f"{fid}: caso {c.get('id')} sin required_assertions")
blocked = [fid for fid, m in feats.items() if (m or {}).get("status") == "blocked"]
if blocked != ["merge-happy-path"]:
    raise SystemExit(f"blocked inesperado: {blocked}")
PY

caso "list-features enumera todas las fichas; ninguna pending"
out="$(ctrl list-features 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "list-features fallo: $out"
printf '%s' "$out" | grep -q 'status=pending' && malo "list-features aun declara pending: $out"
printf '%s' "$out" | grep -E 'id=merge-happy-path' | grep -q 'status=blocked' \
  || malo "merge-happy-path no sale blocked: $out"
python3 - "$SKILL" "$out" <<'PY' || malo "list-features no cubre el catalogo"
import json, sys
from pathlib import Path
cat = json.loads((Path(sys.argv[1]) / "features/catalog.json").read_text())
listed = set()
for line in sys.argv[2].splitlines():
    if line.startswith("id="):
        listed.add(line.split()[0][3:])
want = set(cat.get("features") or {})
missing = sorted(want - listed)
extra = sorted(listed - want)
if missing or extra:
    raise SystemExit(f"missing={missing} extra={extra}")
PY

# ---------------------------------------------------------------------------
# Candado 19.17: leftover pending / leftover legacy / superficie nueva
# ---------------------------------------------------------------------------
caso "pending de implementacion restante => 1"
R="$SANDBOX/pend"; S="$SANDBOX/pend-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/catalog.json")
c=json.loads(p.read_text())
c["features"]["fantasma-pending"]={"status":"pending","owner_task":"19.99"}
p.write_text(json.dumps(c), encoding="utf-8")
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto pending de implementación"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'pending de implementación\|pending de implementacion' \
  || malo "sin motivo pending restante: $out"

caso "mutacion accept_pending: leftover pending deja de atrapar"
run_lint "$R" "$S" --mutate accept_pending >/dev/null 2>&1 \
  || malo "accept_pending debio pasar en falso"

caso "legacy restante (kind=legacy en feature activa) => 1"
R="$SANDBOX/leg"; S="$SANDBOX/leg-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
python3 - <<PY
import json
from pathlib import Path
p=Path("$S/features/gate-turn.json")
d=json.loads(p.read_text())
d["executor"]={"kind":"legacy","command":"drive-gate-scenario","function":"cmd_drive_gate_scenario"}
p.write_text(json.dumps(d), encoding="utf-8")
# el driver copiado quedaria huerfano y taparia el leftover
Path("$S/scripts/drivers/gate-turn.sh").unlink(missing_ok=True)
PY
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto legacy restante"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'legacy restante' || malo "sin motivo legacy restante: $out"

caso "mutacion accept_legacy: leftover legacy deja de atrapar"
run_lint "$R" "$S" --mutate accept_legacy >/dev/null 2>&1 \
  || malo "accept_legacy debio pasar en falso"

caso "superficie publica nueva rompe el candado"
R="$SANDBOX/surf"; S="$SANDBOX/surf-skill"
mkdir -p "$R" "$S"; mk_min_repo "$R"; mk_min_skill "$S"
printf '#!/bin/sh\n' > "$R/tools/nuevo-publico.sh"
chmod +x "$R/tools/nuevo-publico.sh"
run_lint "$R" "$S" >/dev/null 2>&1 && malo "acepto superficie sin clasificar"
out="$(run_lint "$R" "$S" 2>&1 || true)"
printf '%s' "$out" | grep -q 'sin clasificar' || malo "motivo sin 'sin clasificar': $out"

caso "mutacion omit_discovery: superficie nueva deja de atrapar"
run_lint "$R" "$S" --mutate omit_discovery >/dev/null 2>&1 \
  || malo "omit_discovery debio pasar en falso (protege discovery)"

# ---------------------------------------------------------------------------
# Wrapper en la particion rapida (no se pierde el shard)
# ---------------------------------------------------------------------------
caso "wrapper integration entra en rapidos; lentos sigue siendo solo mutations"
python3 - "$repo/tests/run.sh" <<'PY' || malo "particion perderia el wrapper"
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# lista EXPLICITA de lentos; un test nuevo cae en rapidos
if "test_feature_map_integration" in text and "SAIKIT_TESTS_LENTOS" in text:
    # no debe aparecer en la lista lenta
    for line in text.splitlines():
        if line.startswith("SAIKIT_TESTS_LENTOS="):
            if "test_feature_map_integration" in line:
                raise SystemExit("integration listado como lento")
if "test_gate_mutations" not in text:
    raise SystemExit("se perdio el shard lento")
print("ok")
PY
[ -f "$repo/tests/test_feature_map_integration.sh" ] \
  || malo "falta tests/test_feature_map_integration.sh"

# ---------------------------------------------------------------------------
# Fichas: 18.27 / 18.26 / 18.10 + vivo no observado
# ---------------------------------------------------------------------------
caso "fichas integran 18.27, 18.26, 18.10; vivo inventariado no observado"
python3 - "$SKILL" <<'PY' || malo "limites 18.x ausentes o cierran como todo-probado"
import sys
from pathlib import Path
skill = Path(sys.argv[1])
live = (skill / "features/merge-happy-path.md").read_text(encoding="utf-8")
gate = (skill / "features/gate-turn.md").read_text(encoding="utf-8")
merge = (skill / "features/saikit-merge.md").read_text(encoding="utf-8")
auto = (skill / "features/autopilot-contract.md").read_text(encoding="utf-8")
readme = (skill / "features/README.md").read_text(encoding="utf-8")
skillmd = (skill / "SKILL.md").read_text(encoding="utf-8")
blob = "\n".join([live, gate, merge, auto, readme, skillmd])
for needle in ("18.26", "18.27", "18.10"):
    if needle not in blob:
        raise SystemExit(f"falta {needle} en fichas/índice/SKILL")
if "18.26" not in live:
    raise SystemExit("merge-happy-path sin 18.26")
if "18.27" not in live and "18.27" not in gate:
    raise SystemExit("ni live ni gate-turn citan 18.27")
if "18.10" not in live and "18.10" not in readme:
    raise SystemExit("ni live ni README citan 18.10")
low = blob.lower()
if "todo probado" in low or "todo-probado" in low:
    raise SystemExit("cierre afirma 'todo probado'")
if "inventariado" not in low or "no observado" not in low:
    raise SystemExit("falta 'inventariado' / 'no observado' para el vivo")
if "including pending" in skillmd:
    raise SystemExit("SKILL.md sigue vendiendo pending como inventario vigente")
if "skill PASS" not in skillmd and "skill pass" not in skillmd.lower():
    if "no acredita" not in skillmd.lower() and "not the product" not in skillmd.lower():
        raise SystemExit("SKILL.md no separa PASS de skill vs sello verify/")
print("ok")
PY

# ---------------------------------------------------------------------------
# Drives locales + aliases + FAIL/unknown
# ---------------------------------------------------------------------------
caso "launch aislado para combo y aliases"
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch fallo: $out"
  echo "FAIL: $fail aserciones (sin launch no hay combo)" >&2
  exit 1
fi
printf '%s' "$out" | grep -q 'launched run_id=' || malo "launch sin run_id: $out"

caso "aliases reales: dry-run, gate parcial, ledger, deploy-log"
reset_art
out="$(ctrl drive-install-dry-run 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive-install-dry-run rc=$rc: $out"
out="$(ctrl drive-gate-scenario 01-sin-armar 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive-gate-scenario rc=$rc: $out"
printf '%s' "$out" | grep -Eqi 'partial|parcial|alcance' \
  || malo "alias gate no declara alcance parcial: $out"
out="$(ctrl drive-audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive-audit-ledger rc=$rc: $out"
out="$(ctrl drive-deploy-log 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive-deploy-log rc=$rc: $out"

caso "drive <id> local audit-ledger PASS/0"
reset_art
out="$(ctrl drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "drive audit-ledger rc=$rc: $out"
sum="$(latest_summary audit-ledger)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "audit-ledger sin summary"

caso "drive merge-happy-path: unknown/BLOCKED (inventariado; no observado)"
reset_art
out="$(ctrl drive merge-happy-path 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "merge-happy-path debio unknown/3 (got $rc): $out"
printf '%s' "$out" | grep -Eqi 'BLOCKED|unknown|inventari' \
  || malo "vivo sin motivo unknown/BLOCKED: $out"
sum="$(latest_summary merge-happy-path)"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary vivo no es unknown/live"
import json, sys
s = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result") == "unknown", s
assert s.get("exit_code") == 3, s
assert s.get("mode") == "live", s
PY
fi

caso "evidencia FAIL/1 y unknown/3 (sintetica, no solo verde)"
reset_art
out="$(ctrl_synth FAIL drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "FAIL sintetico debio exit 1 (got $rc): $out"
sum="$(latest_summary audit-ledger)"
[ -n "$sum" ] && [ -f "$sum" ] || malo "FAIL sin summary"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary FAIL mal formado"
import json, sys
s=json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result")=="FAIL" and s.get("exit_code")==1
PY
fi
reset_art
out="$(ctrl_synth unknown drive check-deploy-log 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 3 ] || malo "unknown sintetico debio exit 3 (got $rc): $out"
sum="$(latest_summary check-deploy-log)"
if [ -n "$sum" ] && [ -f "$sum" ]; then
python3 - "$sum" <<'PY' || malo "summary unknown mal formado"
import json, sys
s=json.loads(open(sys.argv[1], encoding="utf-8").read())
assert s.get("result")=="unknown" and s.get("exit_code")==3
PY
fi

# ---------------------------------------------------------------------------
# Combo doctor → drive → reintento → cleanup (evidencia sobrevive)
# ---------------------------------------------------------------------------
caso "launch y auditorias de fixtures no dependen de hook/installer"
lazy_repo="$SANDBOX/lazy-repo"
lazy_skill="$lazy_repo/.cursor/skills/verify-summonaikit"
mkdir -p "$lazy_repo/.cursor/skills" "$lazy_repo/tools" "$lazy_repo/docs"
cp -R "$SKILL" "$lazy_skill"
cp "$repo/tools/audita-ledger.sh" "$repo/tools/check-deploy-log.sh" "$lazy_repo/tools/"
cp "$repo/docs/deploy-log.md" "$lazy_repo/docs/deploy-log.md"
lazy_ctrl="$lazy_skill/scripts/control-summonaikit"
lazy_state="$SANDBOX/lazy-state"
lazy_art="$SANDBOX/lazy-artifacts"
mkdir -p "$lazy_state" "$lazy_art"
lazy() {
  SAIKIT_VERIFY_STATE="$lazy_state" SAIKIT_VERIFY_ARTIFACTS="$lazy_art" \
    bash "$lazy_ctrl" "$@"
}
out="$(lazy launch 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "launch sin hook/installer debio pasar: rc=$rc $out"
if [ "$rc" -eq 0 ]; then
  out="$(lazy doctor audit-ledger 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || malo "doctor audit-ledger sin hook/installer: rc=$rc $out"
  out="$(lazy drive audit-ledger 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || malo "drive audit-ledger sin hook/installer: rc=$rc $out"
  out="$(lazy drive check-deploy-log 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || malo "drive deploy-log sin hook/installer: rc=$rc $out"
  mkdir -p "$lazy_repo/hooks"
  cp "$repo/hooks/summonaikit-harness.sh" "$lazy_repo/hooks/summonaikit-harness.sh"
  cat > "$lazy_repo/tools/install-hook.sh" <<'EOF'
#!/usr/bin/env bash
printf 'TOKEN=synthetic-install-secret\n'
exit 7
EOF
  chmod +x "$lazy_repo/tools/install-hook.sh"
  out="$(lazy drive gate-turn 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 1 ] || malo "installer ejecutado/fallido debio FAIL/1: rc=$rc $out"
  out="$(lazy drive gate-turn 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 1 ] || malo "reintento de installer fallido debio FAIL/1: rc=$rc $out"
  log_count="$(find "$lazy_art" -path '*/gate-turn/*/hook-prepare.log' | wc -l | tr -d ' ')"
  [ "$log_count" -eq 2 ] \
    || malo "preparacion fallida no conservo dos logs por intento (n=$log_count)"
  if grep -R 'synthetic-install-secret' "$lazy_art" >/dev/null 2>&1; then
    malo "salida del installer quedo sin redactar"
  fi
  fail_sum="$(find "$lazy_art" -path '*/gate-turn/*/summary.json' | sort | tail -1)"
  fail_steps="$(dirname "$fail_sum")/steps.jsonl"
  python3 - "$fail_sum" "$fail_steps" <<'PY' \
    || malo "fallo del installer no dejo evidencia FAIL/tool_exit=7"
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
steps = [json.loads(x) for x in open(sys.argv[2], encoding="utf-8") if x.strip()]
assert s.get("result") == "FAIL" and s.get("exit_code") == 1, s
assert any(x.get("step_id") == "hook-prepare" and x.get("tool_exit") == 7
           for x in steps), steps
PY
  lazy cleanup >/dev/null 2>&1 || true
fi

caso "combo doctor→drive→reintento→cleanup conserva intentos"
reset_art
out="$(ctrl doctor audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "doctor audit-ledger rc=$rc: $out"
printf '%s' "$out" | grep -Eqi 'doctor|ready|PASS|audit-ledger' \
  || malo "doctor sin senal: $out"
[ -f "$ART/doctor.json" ] || [ -f "$STATE/doctor.json" ] \
  || find "$ART" "$STATE" -name doctor.json | grep -q . \
  || malo "doctor no escribio doctor.json"
out="$(ctrl drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "combo drive 1 rc=$rc: $out"
first="$(latest_summary audit-ledger)"
[ -n "$first" ] && [ -f "$first" ] || malo "combo sin primer summary"
h1=""
if [ -n "$first" ] && [ -f "$first" ]; then
  h1="$(cksum "$first")"
fi
out="$(ctrl drive audit-ledger 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "combo reintento rc=$rc: $out"
if [ -n "$first" ]; then
  [ -f "$first" ] || malo "reintento borro el primer intento"
  [ -n "$h1" ] && [ "$(cksum "$first")" = "$h1" ] || malo "reintento muto el primer summary"
fi
n="$(find "$ART" -path '*/audit-ledger/*/summary.json' | wc -l | tr -d ' ')"
[ "$n" -ge 2 ] || malo "reintento no dejo 2 summaries (n=$n)"
out="$(ctrl cleanup 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup rc=$rc: $out"
printf '%s' "$out" | grep -qi 'artifacts kept\|instance cleared' \
  || malo "cleanup no declara evidencia conservada: $out"
[ -f "$first" ] || malo "cleanup borro evidencia"
[ ! -f "$STATE/state.json" ] || malo "cleanup dejo state.json"

# ---------------------------------------------------------------------------
# pytest verify/ aislado — observado, no inferido del skill
# ---------------------------------------------------------------------------
caso "verify/ del checkout se conserva (sello no se infiere)"
LEEME="$repo/verify/LEEME.md"
[ -f "$LEEME" ] || malo "falta verify/LEEME.md"
[ -f "$repo/verify/test_drive.py" ] || malo "falta verify/test_drive.py"
seal_before="$(cksum "$LEEME")"
if git -C "$repo" diff --quiet HEAD -- verify/ 2>/dev/null; then
  :
else
  # Evidence.txt puede actualizarse con evidencia NUEVA real; el sello no.
  if git -C "$repo" diff --quiet HEAD -- verify/LEEME.md verify/test_drive.py \
    verify/Drive.md verify/Doctor.md verify/Launch.md verify/Cleanup.md 2>/dev/null
  then
    :
  else
    malo "19.17 no debe reescribir el sello ni las guias de verify/"
  fi
fi

caso "pytest verify/ aislado (fuente/env propios); cotejo honesto"
resolve_pytest() {
  if python3 -c "import pytest" 2>/dev/null; then
    printf '%s' "python3 -m pytest"
    return 0
  fi
  local venv="$SANDBOX/drive-venv"
  python3 -m venv "$venv" || return 1
  "$venv/bin/pip" install -q pytest==8.4.2 || return 1
  printf '%s' "$venv/bin/pytest"
}
mkdir -p "$SANDBOX/drive-home" "$SANDBOX/drive-tmp"
PYTEST_BIN="$(resolve_pytest)" || { malo "no se pudo provisionar pytest"; PYTEST_BIN=""; }
DRIVE_LOG="$SANDBOX/verify-drive.log"
DRIVE_RC=99
# Snapshot pre-pytest (20.28): __pycache__ / .pytest_cache gitignored ya
# presentes no son fuga del run.
had_pycache=0; [ -e "$repo/verify/__pycache__" ] && had_pycache=1
had_pytest_cache=0; [ -e "$repo/.pytest_cache" ] && had_pytest_cache=1
if [ -n "$PYTEST_BIN" ]; then
  # Cache y bytecode fuera del checkout: run.sh trata cualquier escritura
  # en el repo como LEAK.
  # shellcheck disable=SC2086
  env -u SAIKIT_VERIFY_STATE -u SAIKIT_VERIFY_ARTIFACTS \
    -u SAIKIT_VERIFY_SYNTHETIC_EXECUTOR -u SAIKIT_VERIFY_ALLOW_SYNTHETIC \
    -u SAIKIT_VERIFY_MUTATE \
    PATH="$ORIG_PATH" \
    HOME="$SANDBOX/drive-home" \
    USERPROFILE="$SANDBOX/drive-home" \
    TMPDIR="$SANDBOX/drive-tmp" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX="$SANDBOX/pycache" \
    SAIKIT_HOOK_VIVO="$repo/hooks/summonaikit-harness.sh" \
    $PYTEST_BIN "$repo/verify/" -v --tb=short \
      -o "cache_dir=$SANDBOX/pytest-cache" >"$DRIVE_LOG" 2>&1 \
    && DRIVE_RC=0 || DRIVE_RC=$?
fi
printf '    cotejo verify/: exit=%s\n' "$DRIVE_RC"
if [ -f "$DRIVE_LOG" ]; then
  tail -n 20 "$DRIVE_LOG" | sed 's/^/    | /'
fi
[ -f "$DRIVE_LOG" ] || malo "pytest verify/ no dejo log"
# El sello del checkout no se toca por correr el Drive.
[ "$(cksum "$LEEME")" = "$seal_before" ] \
  || malo "correr pytest verify/ muto LEEME.md — no transferir sello"
# Fuga real = aparece DESPUES del pytest (had_* tomado antes).
if [ "$had_pycache" -eq 0 ] && [ -e "$repo/verify/__pycache__" ]; then
  malo "pytest verify/ dejo verify/__pycache__ (fuga en el checkout)"
fi
if [ "$had_pytest_cache" -eq 0 ] && [ -e "$repo/.pytest_cache" ]; then
  malo "pytest verify/ dejo .pytest_cache en la raiz (fuga)"
fi
# Un PASS de skill (aliases/drives de arriba) no acredita el sello.
python3 - "$DRIVE_LOG" "$DRIVE_RC" "$repo" <<'PY' || malo "cotejo verify/ deshonesto"
import os, subprocess, sys
from pathlib import Path
log_p, rc_s, repo = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
log = log_p.read_text(encoding="utf-8", errors="replace") if log_p.is_file() else ""
rc = int(rc_s)
# Debe haber corrido los 5 tests del Drive (o declarado por que no).
needed = (
    "test_el_gate_sin_armar_y_armado",
    "test_instalar_en_seco_responde",
    "test_la_libreta_de_tareas_esta_al_dia",
    "test_el_registro_de_deploys_es_valido",
    "test_el_estado_del_mapa_se_reporta",
)
if rc == 99:
    raise SystemExit("pytest verify/ no se observo (sin binario)")
for name in needed:
    if name not in log:
        raise SystemExit(f"Drive no nombro {name}")
shallow = subprocess.check_output(
    ["git", "-C", str(repo), "rev-parse", "--is-shallow-repository"],
    text=True,
).strip()
has_master = subprocess.call(
    ["git", "-C", str(repo), "rev-parse", "--verify", "origin/master"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
) == 0
ledger_unknown = (
    "el clon es shallow" in log
    or "origin/master" in log
    or "AUDITORIA DEL LEDGER: unknown" in log
)
core_failed = any(
    f"{n} FAILED" in log
    for n in (
        "test_el_gate_sin_armar_y_armado",
        "test_instalar_en_seco_responde",
        "test_el_registro_de_deploys_es_valido",
        "test_el_estado_del_mapa_se_reporta",
    )
)
if core_failed:
    raise SystemExit("Drive FAIL en caso que si se pudo observar")
if rc == 0:
    print("Drive verify/: PASS observado (5/5). No se transfiere al sello.")
    raise SystemExit(0)
# FAIL/unknown del ledger por clon shallow o sin origin/master: inventariado.
if (shallow == "true" or not has_master) and ledger_unknown:
    print("Drive verify/: ledger inventariado; no observado (clon/ref).")
    raise SystemExit(0)
if "test_la_libreta_de_tareas_esta_al_dia FAILED" in log and ledger_unknown:
    print("Drive verify/: ledger unknown observado; resto cotejado.")
    raise SystemExit(0)
raise SystemExit(f"Drive verify/ exit={rc} sin razon declarada")
PY
# estado del mapa: cotejar, no exigir al_dia por inferencia
estado_out="$(
  HOME="$SANDBOX/drive-home" USERPROFILE="$SANDBOX/drive-home" \
    TMPDIR="$SANDBOX/drive-tmp" \
    bash "$repo/skills/saikit-verificar-app/verificar.sh" estado "$repo" 2>&1 || true
)"
printf '    estado verify/: %s\n' "$(printf '%s' "$estado_out" | head -1)"
printf '%s' "$estado_out" | grep -Eq '^(al_dia|desactualizado|viejo|unknown|sin_mapa)' \
  || malo "estado del mapa no cotejado: $estado_out"

# Mutante 20.28: quitar el snapshot y volver a [ ! -e ] trata un
# __pycache__ preexistente como fuga (falso rojo). Discriminante.
caso "mutante sin snapshot de fuga se pone rojo"
mkdir -p "$repo/verify/__pycache__"
naive_rc=0
# Copia de la asercion vieja: falla si el dir existe (preexistente o no).
[ ! -e "$repo/verify/__pycache__" ] || naive_rc=1
[ "$naive_rc" -eq 1 ] \
  || malo "mutante [ ! -e ] no se puso rojo ante __pycache__ preexistente"

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_integration"
exit 0
