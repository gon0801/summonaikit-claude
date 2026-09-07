#!/usr/bin/env bash
# tests/test_feature_map_isolation.sh — 19.2: runtime aislado obligatorio.
#
# Mutaciones discriminantes (SAIKIT_VERIFY_MUTATE). Cada una pone rojo un
# caso identificado si se quita la guardia:
#   skip_physical_path     — omite ruta física / symlink / `..` / pertenencia
#   skip_env_sanitize      — hereda SAIKIT_*/GIT_*/credenciales/transportes
#   skip_cwd_isolation     — permite setup/merge/postmerge sobre el checkout
#   skip_cleanup_ownership — cleanup borra cualquier temporal con prefijo /tmp
#
# Violación de aislamiento observada = FAIL (1), nunca unknown (3).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

SKILL="$repo/.cursor/skills/verify-summonaikit"
CTRL="$SKILL/scripts/control-summonaikit"
RUNTIME="$SKILL/scripts/lib/runtime.sh"
STATEPY="$SKILL/scripts/lib/state.py"
CATALOG="$SKILL/features/catalog.json"

STATE="$SANDBOX/verify-state"
ART="$SANDBOX/verify-artifacts"
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

# $1=label $2=regex; resto = comando. Exige exit 1 (nunca 0 ni 3) y motivo.
expect_fail() {
  local label="$1" pat="$2"; shift 2
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    malo "$label: debio fallar (exit 0): $out"
    return
  fi
  if [ "$rc" -eq 3 ]; then
    malo "$label: unknown (3) — aislamiento observado es FAIL: $out"
    return
  fi
  if [ "$rc" -ne 1 ]; then
    malo "$label: exit $rc (se espera 1): $out"
  fi
  printf '%s' "$out" | grep -Eq "$pat" \
    || malo "$label: sin motivo [$pat]: $out"
}

sha_of() { cksum "$1" | awk '{print $1" "$2}'; }

reset_state() {
  rm -rf "$STATE" "$ART"
  mkdir -p "$STATE" "$ART"
}

# ---------------------------------------------------------------------------
# Fuentes internas presentes y parseables
# ---------------------------------------------------------------------------
caso "runtime.sh y state.py existen y parsean"
[ -f "$RUNTIME" ] || malo "falta scripts/lib/runtime.sh"
[ -f "$STATEPY" ] || malo "falta scripts/lib/state.py"
if [ -f "$RUNTIME" ]; then
  bash -n "$RUNTIME" || malo "bash -n fallo en runtime.sh"
fi
bash -n "$CTRL" || malo "bash -n fallo en control-summonaikit"
if [ -f "$STATEPY" ]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -c \
    "import ast,pathlib; ast.parse(pathlib.Path(r'$STATEPY').read_text(encoding='utf-8'))" \
    || malo "state.py no parsea"
fi

caso "catalogo clasifica scripts/lib como helpers internal"
python3 - <<PY || malo "helpers de lib no clasificados"
import json
from pathlib import Path
c=json.loads(Path("$CATALOG").read_text())
h=c.get("helpers") or {}
for rel in ("scripts/lib/runtime.sh", "scripts/lib/state.py"):
    meta=h.get(rel)
    assert meta and meta.get("kind")=="internal", rel
PY

caso "SKILL.md documenta state.json y migracion de .run/env"
grep -q 'state.json' "$SKILL/SKILL.md" || malo "SKILL.md no nombra state.json"
grep -E -q 're-lanzar|relanzar|re-launch' "$SKILL/SKILL.md" \
  || malo "SKILL.md sin instruccion de re-lanzar"
grep -q '.run/env' "$SKILL/SKILL.md" || malo "SKILL.md no menciona .run/env legado"

# ---------------------------------------------------------------------------
# Estado peligroso: comando incrustado / metacaracteres / espacios
# ---------------------------------------------------------------------------
caso "env legado con comando incrustado se rechaza y no se ejecuta"
reset_state
sentinel="$SANDBOX/pwned-embedded"
rm -f "$sentinel"
cat > "$STATE/env" <<EOF
VERIFY_HOME=$SANDBOX/fake-home; touch '$sentinel'
VERIFY_DEST=$SANDBOX/fake-home/hook.sh
VERIFY_RUN_ID=evil
VERIFY_REPO=$repo
EOF
mkdir -p "$SANDBOX/fake-home"
expect_fail "env-comando-doctor" 're-lanzar|relanzar|\.run/env|legado|legacy' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor
[ ! -e "$sentinel" ] || malo "env legado ejecuto el comando incrustado"

expect_fail "env-comando-cli" 're-lanzar|relanzar|\.run/env|legado|legacy' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cli -- tools/install-hook.sh --dry-run
[ ! -e "$sentinel" ] || malo "cli ejecuto el env legado"

expect_fail "env-comando-cleanup" 're-lanzar|relanzar|\.run/env|legado|legacy|propio|ownership' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cleanup
[ ! -e "$sentinel" ] || malo "cleanup ejecuto el env legado"
# no debe haber borrado a ciegas un HOME inventado por el env
[ -d "$SANDBOX/fake-home" ] || malo "cleanup borro el HOME del env legado a ciegas"

caso "JSON con metacaracteres de shell se rechaza"
reset_state
python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "evil",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "/tmp/x; touch $SANDBOX/pwned-meta",
  "dest": "/tmp/x/hook.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "/tmp/x/tmp",
  "owned_temps": ["/tmp/x"],
  "host_dests": {},
}), encoding="utf-8")
PY
expect_fail "json-meta-doctor" 'inválid|invalid|metacar|shell|escape|JSON' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor
[ ! -e "$SANDBOX/pwned-meta" ] || malo "JSON peligroso se ejecuto"

caso "JSON con espacios peligrosos si se sourcea se rechaza"
reset_state
python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "spaces",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "/tmp/saikit home && touch $SANDBOX/pwned-spaces",
  "dest": "/tmp/saikit home/hook.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "/tmp/saikit home/tmp",
  "owned_temps": ["/tmp/saikit home"],
  "host_dests": {},
}), encoding="utf-8")
PY
expect_fail "json-spaces-doctor" 'inválid|invalid|metacar|shell|escape|espacio' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor
[ ! -e "$SANDBOX/pwned-spaces" ] || malo "path con espacios se ejecuto como shell"

# ---------------------------------------------------------------------------
# JSON truncado / invalido
# ---------------------------------------------------------------------------
caso "JSON truncado es FAIL 1 (nunca unknown)"
reset_state
printf '{"schema_version":1,"run_id":' > "$STATE/state.json"
expect_fail "json-truncado-doctor" 'JSON|truncad|mal formado|inválid|invalid' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor
# reponer truncado (doctor no lo borra)
printf '{"schema_version":1,"run_id":' > "$STATE/state.json"
expect_fail "json-truncado-cli" 'JSON|truncad|mal formado|inválid|invalid' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cli -- tools/check-deploy-log.sh
# cleanup soft-clear: exit 0, motivo visible, desbloquea launch (no deadlock)
printf '{"schema_version":1,"run_id":' > "$STATE/state.json"
out="$(
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cleanup 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "json-truncado-cleanup: debio salir 0 (soft-clear): $out"
[ "$rc" -eq 3 ] && malo "json-truncado-cleanup: unknown (3) — aislamiento observado es FAIL"
printf '%s' "$out" | grep -Eq 'JSON|truncad|mal formado|inválid|invalid|no recuperable' \
  || malo "json-truncado-cleanup: sin motivo: $out"
[ ! -f "$STATE/state.json" ] || malo "json-truncado-cleanup: debio borrar state.json"

# ---------------------------------------------------------------------------
# Symlink escape
# ---------------------------------------------------------------------------
caso "symlink escape en STATE se rechaza"
reset_state
outside="$SANDBOX/outside-state"
mkdir -p "$outside"
ln -s "$outside" "$SANDBOX/state-link"
expect_fail "symlink-state-launch" 'symlink|enlace|escape|físic|fisic' \
  env SAIKIT_VERIFY_STATE="$SANDBOX/state-link" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" launch

caso "symlink escape en ARTIFACTS se rechaza"
reset_state
mkdir -p "$SANDBOX/outside-art"
ln -s "$SANDBOX/outside-art" "$SANDBOX/art-link"
expect_fail "symlink-art-launch" 'symlink|enlace|escape|físic|fisic' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$SANDBOX/art-link" \
  bash "$CTRL" launch

caso "symlink escape en verify_home se rechaza"
reset_state
mkdir -p "$SANDBOX/outside-home" "$SANDBOX/real-home"
ln -s "$SANDBOX/outside-home" "$SANDBOX/home-link"
python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "symhome",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "$SANDBOX/home-link",
  "dest": "$SANDBOX/home-link/.claude/hooks/summonaikit-harness.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "$SANDBOX/home-link/tmp",
  "owned_temps": ["$SANDBOX/home-link"],
  "host_dests": {"claude": "$SANDBOX/home-link/.claude/hooks/summonaikit-harness.sh"},
  "token": "not-owned",
}), encoding="utf-8")
PY
expect_fail "symlink-home-doctor" 'symlink|enlace|escape|físic|fisic' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor

caso "symlink escape en destino de host se rechaza"
reset_state
mkdir -p "$SANDBOX/owned-home/.claude/hooks" "$SANDBOX/outside-dest"
ln -s "$SANDBOX/outside-dest/hook.sh" \
  "$SANDBOX/owned-home/.claude/hooks/summonaikit-harness.sh"
printf 'x\n' > "$SANDBOX/outside-dest/hook.sh"
python3 - <<PY
import json
from pathlib import Path
home="$SANDBOX/owned-home"
(Path(home)/".saikit-run").write_text("run_id=symdest\ntoken=t\n", encoding="utf-8")
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "symdest",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": home,
  "dest": home+"/.claude/hooks/summonaikit-harness.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": home+"/tmp",
  "owned_temps": [home],
  "host_dests": {"claude": home+"/.claude/hooks/summonaikit-harness.sh"},
  "token": "t",
}), encoding="utf-8")
PY
expect_fail "symlink-dest-doctor" 'symlink|enlace|escape|físic|fisic' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor

# ---------------------------------------------------------------------------
# `..` escaping the run
# ---------------------------------------------------------------------------
caso "ruta con .. que escapa el run se rechaza"
reset_state
python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "dotdot",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "$STATE/../escaped-home",
  "dest": "$STATE/../escaped-home/hook.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "$STATE/../escaped-home/tmp",
  "owned_temps": ["$STATE/../escaped-home"],
  "host_dests": {},
  "token": "t",
}), encoding="utf-8")
PY
expect_fail "dotdot-doctor" '\.\.|escape|inválid|invalid' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor

# ---------------------------------------------------------------------------
# HOME_REAL adulterado no prueba pertenencia
# ---------------------------------------------------------------------------
caso "HOME_REAL adulterado no acredita un HOME ajeno"
reset_state
foreign_home="$SANDBOX/adulterated-home"
mkdir -p "$foreign_home/.claude/hooks"
printf 'not-ours\n' > "$foreign_home/.claude/hooks/summonaikit-harness.sh"
python3 - <<PY
import json
from pathlib import Path
home="$SANDBOX/adulterated-home"
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "adul",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": home,
  "dest": home+"/.claude/hooks/summonaikit-harness.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": home+"/tmp",
  "owned_temps": [home],
  "host_dests": {"claude": home+"/.claude/hooks/summonaikit-harness.sh"},
  "token": "wrong-token",
}), encoding="utf-8")
PY
expect_fail "home-real-adulterado" 'propio|ownership|perten|marker|token|inválid|invalid' \
  env HOME_REAL="$foreign_home" SAIKIT_VERIFY_STATE="$STATE" \
  SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" doctor

# ---------------------------------------------------------------------------
# Overrides heredados se eliminan
# ---------------------------------------------------------------------------
caso "overrides host/Git/transporte heredados no llegan al subproceso"
reset_state
ext_grok="$SANDBOX/ext-grok-hooks"
mkdir -p "$ext_grok"
printf 'SENTINEL-GROK-OVERRIDE\n' > "$ext_grok/sentinel.txt"
grok_sha="$(sha_of "$ext_grok/sentinel.txt")"
out="$(
  env \
    SAIKIT_VERIFY_STATE="$STATE" \
    SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_GROK_HOOKS_DIR="$ext_grok" \
    GIT_DIR="$SANDBOX/no-such-git" \
    GIT_CONFIG="$SANDBOX/no-such-gitconfig" \
    GIT_CONFIG_GLOBAL="$SANDBOX/no-such-gitconfig" \
    GH_TOKEN="must-not-leak" \
    HTTPS_PROXY="http://127.0.0.1:9" \
    https_proxy="http://127.0.0.1:9" \
    bash "$CTRL" launch 2>&1
)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  malo "launch con overrides heredados debio sanitizar y pasar: $out"
else
  dry="$(
    env \
      SAIKIT_VERIFY_STATE="$STATE" \
      SAIKIT_VERIFY_ARTIFACTS="$ART" \
      SAIKIT_GROK_HOOKS_DIR="$ext_grok" \
      GIT_DIR="$SANDBOX/no-such-git" \
      GH_TOKEN="must-not-leak" \
      HTTPS_PROXY="http://127.0.0.1:9" \
      bash "$CTRL" cli -- tools/install-hook.sh --host grok --dry-run 2>&1
  )" && dry_rc=0 || dry_rc=$?
  if [ "$dry_rc" -ne 0 ]; then
    malo "cli dry-run grok debio pasar con env saneado: $dry"
  else
    printf '%s' "$dry" | grep -Fq "$ext_grok" \
      && malo "override SAIKIT_GROK_HOOKS_DIR heredado llego al tool: $dry"
    printf '%s' "$dry" | grep -Fq "must-not-leak" \
      && malo "GH_TOKEN heredado aparecio en la salida"
  fi
fi
[ "$(sha_of "$ext_grok/sentinel.txt")" = "$grok_sha" ] \
  || malo "sentinel de override grok fue mutado"

# ---------------------------------------------------------------------------
# cwd real / write tools sobre el checkout
# ---------------------------------------------------------------------------
caso "cli rechaza merge/postmerge/setup sobre el checkout de trabajo"
reset_state
# launch real para tener estado valido; si launch falla, el rechazo de cwd
# igual debe ocurrir ante un estado plantado, pero preferimos el run autentico.
if ! out="$(ctrl launch 2>&1)"; then
  malo "launch previo a cwd-isolation fallo: $out"
else
  expect_fail "cli-merge-checkout" 'checkout|desechable|escritura|aisl' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-merge.sh --help"
  expect_fail "cli-postmerge-checkout" 'checkout|desechable|escritura|aisl' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-postmerge.sh --help"
  expect_fail "cli-setup-checkout" 'checkout|desechable|escritura|aisl' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-setup-autopilot.sh --help"
fi

caso "cli -- no admite shell ni comando arbitrario"
# reutiliza el run del caso anterior si sigue activo
if [ ! -f "$STATE/state.json" ]; then
  ctrl launch >/dev/null 2>&1 || true
fi
expect_fail "cli-bash" 'catálogo|catalogo|catalog|públic|public|no admit' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cli -- bash -c 'echo pwned'
expect_fail "cli-abs" 'catálogo|catalogo|catalog|públic|public|no admit' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cli -- /bin/echo pwned

# ---------------------------------------------------------------------------
# Artifacts fuera de la asignacion privada
# ---------------------------------------------------------------------------
caso "artifacts fuera de la asignacion privada se rechaza"
reset_state
expect_fail "art-dotdot" 'artifact|escape|\.\.|asign|privad' \
  env SAIKIT_VERIFY_STATE="$STATE" \
  SAIKIT_VERIFY_ARTIFACTS="$SANDBOX/verify-artifacts/../escaped-art" \
  bash "$CTRL" launch

# ---------------------------------------------------------------------------
# Cleanup de temporal no propio
# ---------------------------------------------------------------------------
caso "cleanup no borra un temporal que no es de este run"
reset_state
foreign="$(mktemp -d "${TMPDIR:-/tmp}/saikit-foreign-XXXXXX")"
printf 'keep-me\n' > "$foreign/important.txt"
python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "foreign",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "$foreign",
  "dest": "$foreign/hook.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "$foreign/tmp",
  "owned_temps": ["$foreign"],
  "host_dests": {},
  "token": "not-this-run",
}), encoding="utf-8")
PY
# Soft-clear: exit 0, state gone, foreign HOME untouched, launch unblocked.
out="$(ctrl cleanup 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-ajeno: debio salir 0 (recuperacion): $out"
printf '%s' "$out" | grep -Eq 'propio|ownership|perten|ajeno|token|marker|no recuperable|HOME no tocado' \
  || malo "cleanup-ajeno: sin motivo de ownership/recuperacion: $out"
[ -f "$foreign/important.txt" ] || malo "cleanup borro temporal ajeno"
[ -d "$foreign" ] || malo "cleanup elimino el dir ajeno"
[ ! -f "$STATE/state.json" ] || malo "cleanup-ajeno: debio borrar state.json"
out="$(ctrl launch 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-ajeno: launch tras soft-clear debio pasar: $out"
ctrl cleanup >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Recuperacion: cleanup inocuo desbloquea launch (review major)
# ---------------------------------------------------------------------------
caso "cleanup recupera JSON truncado y desbloquea launch"
reset_state
printf '{"schema_version":1,"run_id":' > "$STATE/state.json"
out="$(ctrl cleanup 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-truncado: debio salir 0: $out"
printf '%s' "$out" | grep -Eq 'no recuperable|re-lanzar|HOME no tocado|truncad|mal formado' \
  || malo "cleanup-truncado: sin mensaje de recuperacion: $out"
[ ! -f "$STATE/state.json" ] || malo "cleanup-truncado: debio borrar state.json"
out="$(ctrl launch 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-truncado: launch debio pasar tras soft-clear: $out"
ctrl cleanup >/dev/null 2>&1 || true

caso "cleanup recupera VERIFY_HOME borrado y desbloquea launch"
reset_state
out="$(ctrl launch 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-wipe: launch inicial fallo: $out"
vh="$(printf '%s\n' "$out" | sed -n 's/.*VERIFY_HOME=\([^ ]*\).*/\1/p' | head -1)"
[ -n "$vh" ] && [ -d "$vh" ] || malo "cleanup-wipe: no se obtuvo VERIFY_HOME"
rm -rf "$vh"
out="$(ctrl cleanup 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-wipe: debio salir 0: $out"
printf '%s' "$out" | grep -Eq 'no recuperable|re-lanzar|HOME no tocado|propio|token|marker|already gone' \
  || malo "cleanup-wipe: sin mensaje de recuperacion: $out"
[ ! -f "$STATE/state.json" ] || malo "cleanup-wipe: debio borrar state.json"
out="$(ctrl launch 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "cleanup-wipe: launch debio pasar tras soft-clear: $out"
ctrl cleanup >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Segundo launch concurrente / duplicado
# ---------------------------------------------------------------------------
caso "segundo launch con run activo se rechaza"
reset_state
out="$(ctrl launch 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  malo "primer launch debio pasar: $out"
else
  expect_fail "launch-duplicado" 'activo|active|cleanup|ya hay' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" launch
fi

caso "launch con state.json plantado (sin cleanup) se rechaza"
reset_state
printf '{"schema_version":1,"run_id":"planted"}\n' > "$STATE/state.json"
expect_fail "launch-plantado" 'activo|active|cleanup|JSON|inválid|invalid' \
  env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" launch

# ---------------------------------------------------------------------------
# Sentinelas externos sintéticos (nunca el home real del operador)
# ---------------------------------------------------------------------------
caso "sentinelas externos sinteticos intactos byte a byte"
reset_state
EXT="$SANDBOX/external-profiles"
for h in claude grok dsh codex; do
  mkdir -p "$EXT/$h/hooks"
  printf 'SENTINEL-%s-UNIQUE-BYTES-%s\n' "$h" "$RANDOM" > "$EXT/$h/hooks/sentinel.txt"
done
sha_claude="$(sha_of "$EXT/claude/hooks/sentinel.txt")"
sha_grok="$(sha_of "$EXT/grok/hooks/sentinel.txt")"
sha_dsh="$(sha_of "$EXT/dsh/hooks/sentinel.txt")"
sha_codex="$(sha_of "$EXT/codex/hooks/sentinel.txt")"

# apuntar overrides de host a esos perfiles sinteticos: el runtime DEBE
# ignorarlos. Si los honrara, podria escribir junto a los sentinelas.
out="$(
  env \
    SAIKIT_VERIFY_STATE="$STATE" \
    SAIKIT_VERIFY_ARTIFACTS="$ART" \
    SAIKIT_GROK_HOOKS_DIR="$EXT/grok/hooks" \
    SAIKIT_DSH_HOME="$EXT/dsh" \
    HOME_REAL="$EXT/claude" \
    bash "$CTRL" launch 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "launch (sentinelas) fallo: $out"

if [ "$rc" -eq 0 ]; then
  doc="$(ctrl doctor 2>&1)" && d_rc=0 || d_rc=$?
  [ "$d_rc" -eq 0 ] || malo "doctor (sentinelas) fallo: $doc"
  printf '%s' "$doc" | grep -q 'doctor: PASS' \
    || malo "doctor no dijo PASS: $doc"

  dry="$(ctrl drive-install-dry-run 2>&1)" && dry_rc=0 || dry_rc=$?
  [ "$dry_rc" -eq 0 ] || malo "drive-install-dry-run fallo: $dry"

  gate="$(ctrl drive-gate-scenario 01-sin-armar 2>&1)" && g_rc=0 || g_rc=$?
  [ "$g_rc" -eq 0 ] || malo "drive-gate-scenario fallo: $gate"

  cli_out="$(ctrl cli -- tools/install-hook.sh --dry-run 2>&1)" && c_rc=0 || c_rc=$?
  [ "$c_rc" -eq 0 ] || malo "cli install dry-run fallo: $cli_out"

  cln="$(ctrl cleanup 2>&1)" && cl_rc=0 || cl_rc=$?
  [ "$cl_rc" -eq 0 ] || malo "cleanup (sentinelas) fallo: $cln"
  # idempotente
  cln2="$(ctrl cleanup 2>&1)" && cl2_rc=0 || cl2_rc=$?
  [ "$cl2_rc" -eq 0 ] || malo "cleanup idempotente fallo: $cln2"
fi

[ "$(sha_of "$EXT/claude/hooks/sentinel.txt")" = "$sha_claude" ] \
  || malo "sentinel claude mutado"
[ "$(sha_of "$EXT/grok/hooks/sentinel.txt")" = "$sha_grok" ] \
  || malo "sentinel grok mutado"
[ "$(sha_of "$EXT/dsh/hooks/sentinel.txt")" = "$sha_dsh" ] \
  || malo "sentinel dsh mutado"
[ "$(sha_of "$EXT/codex/hooks/sentinel.txt")" = "$sha_codex" ] \
  || malo "sentinel codex mutado"

# ---------------------------------------------------------------------------
# F1-F4: pertenencia al run (dest, tmpdir, CLI flags, STATE)
# ---------------------------------------------------------------------------
caso "F1: drive dry-run no borra SAIKIT_FM_DRY_DEST ajeno"
reset_state
if ! out="$(ctrl launch 2>&1)"; then
  malo "f1-launch: $out"
else
  f1_sent="$SANDBOX/f1-external-dry.sh"
  printf 'F1-KEEP-%s\n' "$$" > "$f1_sent"
  f1_sha="$(sha_of "$f1_sent")"
  drv="$(
    env SAIKIT_FM_DRY_DEST="$f1_sent" \
      SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
      bash "$CTRL" drive-install-dry-run 2>&1
  )" && drv_rc=0 || drv_rc=$?
  [ -f "$f1_sent" ] || malo "F1: borro el sentinela ajeno: $drv"
  [ "$(sha_of "$f1_sent")" = "$f1_sha" ] || malo "F1: muto el sentinela ajeno"
  [ "$drv_rc" -eq 3 ] && malo "F1: unknown (3) — aislamiento observado es FAIL: $drv"
fi

caso "F2: cli --dest absoluto externo se rechaza"
reset_state
if ! out="$(ctrl launch 2>&1)"; then
  malo "f2-launch: $out"
else
  f2_hook="$SANDBOX/f2-cli-hook.sh"
  expect_fail "f2-cli-dest" 'escape|fuera del run|dest|perten|member' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cli -- tools/install-hook.sh --dest "$f2_hook"
  [ ! -e "$f2_hook" ] || malo "F2: instalo hook fuera del run"
fi

caso "F3: tmpdir externo inexistente se rechaza y no se crea"
reset_state
if ! out="$(ctrl launch 2>&1)"; then
  malo "f3-launch: $out"
else
  f3_tmp="$SANDBOX/f3-missing-tmp"
  python3 - "$STATE/state.json" "$f3_tmp" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["tmpdir"] = sys.argv[2]
p.write_text(json.dumps(data), encoding="utf-8")
PY
  expect_fail "f3-tmpdir" 'escape|fuera del run|tmpdir|perten|member' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cli -- tools/check-deploy-log.sh --help
  [ ! -e "$f3_tmp" ] || malo "F3: creo tmpdir externo"
fi

caso "F4: cleanup no borra a traves de STATE symlink"
reset_state
f4_out="$SANDBOX/f4-outside-state"
mkdir -p "$f4_out"
printf 'not-json\n' > "$f4_out/state.json"
ln -sfn "$f4_out" "$SANDBOX/f4-state-link"
out="$(
  env SAIKIT_VERIFY_STATE="$SANDBOX/f4-state-link" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cleanup 2>&1
)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "F4: debio salir 0: $out"
[ "$rc" -eq 3 ] && malo "F4: unknown (3) — aislamiento observado es FAIL"
printf '%s' "$out" | grep -Eq 'symlink|asignad|no se borra|escape|STATE' \
  || malo "F4: sin motivo visible: $out"
[ -f "$f4_out/state.json" ] || malo "F4: borro state.json externo"
printf '%s' "$(cat "$f4_out/state.json")" | grep -q 'not-json' \
  || malo "F4: muto state.json externo"

# ---------------------------------------------------------------------------
# Mutaciones: cada guardia, un caso que se pone verde en falso
# ---------------------------------------------------------------------------
caso "mutacion skip_physical_path: symlink STATE deja de atrapar"
reset_state
mkdir -p "$SANDBOX/mut-out-state"
ln -sfn "$SANDBOX/mut-out-state" "$SANDBOX/mut-state-link"
expect_fail "mut-path-baseline" 'symlink|enlace|escape|físic|fisic' \
  env SAIKIT_VERIFY_STATE="$SANDBOX/mut-state-link" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" launch
# con la guardia apagada, launch no debe rechazar por el symlink
if SAIKIT_VERIFY_MUTATE=skip_physical_path \
   SAIKIT_VERIFY_STATE="$SANDBOX/mut-state-link" \
   SAIKIT_VERIFY_ARTIFACTS="$ART" \
   bash "$CTRL" launch >/dev/null 2>&1; then
  SAIKIT_VERIFY_MUTATE=skip_physical_path \
    SAIKIT_VERIFY_STATE="$SANDBOX/mut-state-link" \
    SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cleanup >/dev/null 2>&1 || true
else
  malo "mutacion skip_physical_path debio pasar en falso (protege ruta fisica)"
fi

caso "mutacion skip_physical_path: F1 borra dest ajeno"
reset_state
if ! ctrl launch >/dev/null 2>&1; then
  malo "mut-f1-launch fallo"
else
  f1m="$SANDBOX/f1-mut-dry.sh"
  printf 'F1-MUT-KEEP\n' > "$f1m"
  SAIKIT_VERIFY_MUTATE=skip_physical_path \
    SAIKIT_FM_DRY_DEST="$f1m" \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" drive-install-dry-run >/dev/null 2>&1 || true
  [ ! -e "$f1m" ] || malo "mutacion skip_physical_path F1 debio borrar el dest ajeno"
fi

caso "mutacion skip_physical_path: F2 instala --dest externo"
reset_state
if ! ctrl launch >/dev/null 2>&1; then
  malo "mut-f2-launch fallo"
else
  f2m="$SANDBOX/f2-mut-hook.sh"
  if SAIKIT_VERIFY_MUTATE=skip_physical_path \
     SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
     bash "$CTRL" cli -- tools/install-hook.sh --dest "$f2m" --dry-run \
     >/dev/null 2>&1; then
    :
  else
    malo "mutacion skip_physical_path F2 debio aceptar --dest externo"
  fi
fi

caso "mutacion skip_physical_path: F3 crea tmpdir externo"
reset_state
if ! ctrl launch >/dev/null 2>&1; then
  malo "mut-f3-launch fallo"
else
  f3m="$SANDBOX/f3-mut-tmp"
  python3 - "$STATE/state.json" "$f3m" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
data["tmpdir"] = sys.argv[2]
p.write_text(json.dumps(data), encoding="utf-8")
PY
  SAIKIT_VERIFY_MUTATE=skip_physical_path \
    SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash "$CTRL" cli -- tools/check-deploy-log.sh --help >/dev/null 2>&1 || true
  [ -d "$f3m" ] || malo "mutacion skip_physical_path F3 debio crear tmpdir externo"
fi

caso "mutacion skip_physical_path: F4 borra state.json via symlink"
reset_state
f4m="$SANDBOX/f4-mut-outside"
mkdir -p "$f4m"
printf 'not-json\n' > "$f4m/state.json"
ln -sfn "$f4m" "$SANDBOX/f4-mut-link"
SAIKIT_VERIFY_MUTATE=skip_physical_path \
  SAIKIT_VERIFY_STATE="$SANDBOX/f4-mut-link" SAIKIT_VERIFY_ARTIFACTS="$ART" \
  bash "$CTRL" cleanup >/dev/null 2>&1 || true
[ ! -f "$f4m/state.json" ] || malo "mutacion skip_physical_path F4 debio borrar state.json externo"

caso "mutacion skip_env_sanitize: override grok deja de atraparse"
reset_state
ext_mut="$SANDBOX/mut-grok-hooks"
mkdir -p "$ext_mut"
printf 'MUT-GROK\n' > "$ext_mut/sentinel.txt"
if ! SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
     bash "$CTRL" launch >/dev/null 2>&1; then
  malo "launch baseline para skip_env_sanitize fallo"
else
  dry_ok="$(
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
      SAIKIT_GROK_HOOKS_DIR="$ext_mut" \
      bash "$CTRL" cli -- tools/install-hook.sh --host grok --dry-run 2>&1
  )" || true
  printf '%s' "$dry_ok" | grep -Fq "$ext_mut" \
    && malo "baseline env-sanitize debio ocultar override: $dry_ok"
  dry_mut="$(
    env SAIKIT_VERIFY_MUTATE=skip_env_sanitize \
      SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
      SAIKIT_GROK_HOOKS_DIR="$ext_mut" \
      bash "$CTRL" cli -- tools/install-hook.sh --host grok --dry-run 2>&1
  )" || true
  printf '%s' "$dry_mut" | grep -Fq "$ext_mut" \
    || malo "mutacion skip_env_sanitize debio filtrar el override (protege saneamiento)"
  ctrl cleanup >/dev/null 2>&1 || true
fi

caso "mutacion skip_cwd_isolation: merge sobre checkout deja de atrapar"
reset_state
if ! ctrl launch >/dev/null 2>&1; then
  malo "launch baseline para skip_cwd_isolation fallo"
else
  expect_fail "mut-cwd-baseline" 'checkout|desechable|escritura|aisl' \
    env SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
    bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-merge.sh --help"
  if SAIKIT_VERIFY_MUTATE=skip_cwd_isolation \
     SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
     bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-merge.sh --help" \
     >/dev/null 2>&1; then
    :
  else
    # --help puede salir !=0 por el tool; lo que importa es que NO sea el
    # rechazo de aislamiento (exit 1 con motivo de checkout).
    mut_out="$(
      SAIKIT_VERIFY_MUTATE=skip_cwd_isolation \
        SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
        bash -c "cd \"$repo\" && bash \"$CTRL\" cli -- tools/saikit-merge.sh --help" \
        2>&1
    )" || mut_rc=$?
    printf '%s' "$mut_out" | grep -Eq 'checkout|desechable|escritura' \
      && malo "mutacion skip_cwd_isolation sigue rechazando checkout"
  fi
  ctrl cleanup >/dev/null 2>&1 || true
fi

caso "mutacion skip_cleanup_ownership: temporal ajeno deja de atraparse"
reset_state
foreign_mut="$(mktemp -d "${TMPDIR:-/tmp}/saikit-foreign-mut-XXXXXX")"
printf 'keep-mut\n' > "$foreign_mut/important.txt"
plant_foreign_state() {
  python3 - <<PY
import json
from pathlib import Path
p=Path("$STATE")/"state.json"
p.write_text(json.dumps({
  "schema_version": 1,
  "run_id": "foreign-mut",
  "launched_at": "2026-01-01T00:00:00Z",
  "repo": "$repo",
  "verify_home": "$foreign_mut",
  "dest": "$foreign_mut/hook.sh",
  "state_dir": "$STATE",
  "artifacts_dir": "$ART",
  "tmpdir": "$foreign_mut/tmp",
  "owned_temps": ["$foreign_mut"],
  "host_dests": {},
  "token": "not-this-run",
}), encoding="utf-8")
PY
}
plant_foreign_state
out="$(ctrl cleanup 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "mut-clean-baseline: soft-clear debio salir 0: $out"
[ -f "$foreign_mut/important.txt" ] || malo "baseline cleanup borro ajeno"
[ ! -f "$STATE/state.json" ] || malo "mut-clean-baseline: debio borrar state.json"
# Reponer estado para la mitad mutada (cleanup pudo rmdir STATE)
mkdir -p "$STATE" "$ART"
plant_foreign_state
if SAIKIT_VERIFY_MUTATE=skip_cleanup_ownership \
   SAIKIT_VERIFY_STATE="$STATE" SAIKIT_VERIFY_ARTIFACTS="$ART" \
   bash "$CTRL" cleanup >/dev/null 2>&1; then
  if [ -f "$foreign_mut/important.txt" ]; then
    malo "mutacion skip_cleanup_ownership debio borrar el temporal (protege ownership)"
  fi
else
  malo "mutacion skip_cleanup_ownership debio pasar en falso"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: $fail aserciones" >&2
  exit 1
fi
echo "OK: test_feature_map_isolation"
exit 0
