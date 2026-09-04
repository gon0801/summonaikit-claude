#!/usr/bin/env bash
# tests/test_autopilot_config.sh - Task 18.7: tools/saikit-setup-autopilot.sh
# (D15 + D20).
#
# QUE AFIRMA (DoD de la fila 18.7, columna 3 de Plans.md):
#   - 5 respuestas => .saikit/autopilot.json con el esquema de
#     docs/phase-18-autopilot-plan.md thinspace 4.2; merge_despliega nace
#     unknown (trampa: nace unknown, no false); sin_verify_app y telegram
#     nacen false.
#   - JSON valido/invalido: un autopilot.json existente corrupto se REPORTA
#     y no se toca (exit 2), no se silicona en silencio (precedente 17.3).
#   - Contencion REAL con dos worktrees del mismo repo (el lock vive en
#     $(git rev-parse --git-common-dir), compartido): el segundo REPORTA el
#     lock y sale 3; nunca hay dos escrituras.
#   - Lock viejo (pid muerto) => reporta y BLOQUEA (exit 3); jamas se
#     auto-limpia (trampa: solo --liberar-lock explicito lo quita).
#   - --liberar-lock muestra el contenido y lo quita (exit 0).
#
# INFRAESTRUCTURA: git REAL en sandbox (repo + origin bare local). Cada caso
# monta su sandbox fresco via caso()/sb_reset. Sin acentos en este archivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
SETUP_REAL="$repo/tools/saikit-setup-autopilot.sh"
SETUP="${SAIKIT_SETUP_TOOL:-$SETUP_REAL}"
# La lib JSON del repo (sin jq): valida y lee lo que el setup escribe.
. "$repo/tools/lib/veredicto_contract.sh"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_contiene() { if ! printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: no contiene [$3]"; fi; }
_no_contiene() { if printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: contiene [$3] y no deberia"; fi; }
_no_contiene() { if printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: contiene [$3] y no deberia"; fi; }

SB=""
OUT=""
RC=0

# ------------------------------------------------------------------ sandbox
sb_reset() {
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-setup-XXXXXX")" || exit 1
  git init --bare -q "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null
  cd "$SB/work" || exit 1
  git symbolic-ref HEAD refs/heads/master
  git config user.email op@example.com
  git config user.name op
  printf 'base\n' > app.sh
  git add app.sh
  git commit -qm "chore: base"
  git push -q origin master
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; sb_reset; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

correr() {  # corre el setup bajo prueba desde el work del sandbox
  OUT="$(bash "$SETUP" "$@" 2>&1)"
  RC=$?
}

json_get() {  # $1=archivo $2=ruta
  saikit_json_get "$(cat "$1" 2>/dev/null)" "$2"
}

# ------------------------------------------------------------------ casos
caso "valido_5_respuestas_escriben_el_esquema"
{
  correr --merge si --despliega si-publica --salud-url "https://api.example.com/salud" \
    --sin-verify-app no --telegram no --rama master --pr 7
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f .saikit/autopilot.json ] || _mal "no escribio .saikit/autopilot.json: $OUT"
  if ! saikit_json_valido "$(cat .saikit/autopilot.json 2>/dev/null)"; then
    _mal "lo escrito no es JSON valido"
  else
    [ "$(json_get .saikit/autopilot.json merge)" = "true" ] || _mal "merge deberia ser true"
    [ "$(json_get .saikit/autopilot.json merge_despliega)" = "publica" ] || _mal "merge_despliega deberia ser publica"
    [ "$(json_get .saikit/autopilot.json salud_url)" = "https://api.example.com/salud" ] || _mal "salud_url no quedo"
    [ "$(json_get .saikit/autopilot.json sin_verify_app)" = "false" ] || _mal "sin_verify_app deberia ser false"
    [ "$(json_get .saikit/autopilot.json telegram)" = "false" ] || _mal "telegram deberia ser false"
    [ "$(json_get .saikit/autopilot.json rama)" = "master" ] || _mal "rama deberia ser master"
    [ "$(json_get .saikit/autopilot.json revert_si_rojo)" = "true" ] || _mal "revert_si_rojo deberia nacer true (esquema 4.2 del plan)"
  fi
  _contiene "reporta la ruta" "$OUT" ".saikit/autopilot.json"
}
fin_caso "valido_5_respuestas_escriben_el_esquema"

caso "existente_corrupto_se_reporta_y_no_se_toca"
{
  mkdir -p .saikit
  printf '{esto no es json' > .saikit/autopilot.json
  antes="$(cksum < .saikit/autopilot.json)"
  correr --merge no --despliega no-se --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  [ "$(cksum < .saikit/autopilot.json)" = "$antes" ] || _mal "piso un autopilot.json corrupto en vez de reportarlo"
  _contiene "nombra el problema" "$OUT" "no es JSON valido"
}
fin_caso "existente_corrupto_se_reporta_y_no_se_toca"

caso "defaults_merge_despliega_nace_unknown"
{
  correr --pr 1 < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f .saikit/autopilot.json ] || _mal "no escribio con defaults: $OUT"
  # La trampa: "nadie contesto" no es "contesto que no".
  [ "$(json_get .saikit/autopilot.json merge)" = "false" ] || _mal "merge deberia nacer false"
  [ "$(json_get .saikit/autopilot.json merge_despliega)" = "unknown" ] || _mal "merge_despliega deberia nacer unknown, no false"
  [ "$(json_get .saikit/autopilot.json salud_url)" = "<null>" ] || _mal "salud_url deberia nacer null"
  [ "$(json_get .saikit/autopilot.json sin_verify_app)" = "false" ] || _mal "sin_verify_app deberia nacer false"
  [ "$(json_get .saikit/autopilot.json telegram)" = "false" ] || _mal "telegram deberia nacer false"
  [ "$(json_get .saikit/autopilot.json rama)" = "master" ] || _mal "rama deberia nacer master"
  [ "$(json_get .saikit/autopilot.json revert_si_rojo)" = "true" ] || _mal "revert_si_rojo deberia nacer true"
}
fin_caso "defaults_merge_despliega_nace_unknown"

caso "salud_url_con_otro_esquema_se_rechaza_sin_escribir"
{
  correr --merge si --despliega no --salud-url "ftp://interno.example.com/x" --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio con una salud_url no http(s)"
  _contiene "nombra el esquema" "$OUT" "http"
}
fin_caso "salud_url_con_otro_esquema_se_rechaza_sin_escribir"

caso "flag_sin_valor_sale_2_no_gira (cross-review kimi)"
{
  # El bug de la Task 0.4: `shift 2` con un solo argumento no consume nada y
  # el while gira para siempre. Acotado con timeout: 124 es bucle, 2 es fix.
  OUT="$(timeout 5 bash "$SETUP" --merge 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "exige el valor" "$OUT" "exige un valor"
}
fin_caso "flag_sin_valor_sale_2_no_gira (cross-review kimi)"

caso "desde_subdir_toma_el_lock_real (cross-review kimi)"
{
  # El common-dir relativo (`../.git`) lo es al cwd de invocacion: correr
  # desde un subdir tomaba un lock fantasma en / y reportaba LOCK ocupado.
  mkdir -p sub
  cd sub || exit 1
  OUT="$(bash "$SETUP" --merge no --despliega no --sin-verify-app no --telegram no 2>&1)"
  RC=$?
  cd "$SB/work" || exit 1
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f .saikit/autopilot.json ] || _mal "no escribio corriendo desde el subdir: $OUT"
  _no_contiene "sin falso LOCK ocupado" "$OUT" "LOCK ocupado"
}
fin_caso "desde_subdir_toma_el_lock_real (cross-review kimi)"

caso "salud_con_comilla_o_inyeccion_se_veta_sin_escribir (cross-review kimi+grok)"
{
  correr --merge no --despliega no --salud-url 'https://x","inyectada":"si' --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio una salud_url con comillas"
  _contiene "nombra el veto" "$OUT" "comillas"
  correr --merge no --despliega no --salud-url 'https://x\y.example.com/s' --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2 con backslash, dio $RC: $OUT"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio una salud_url con backslash"
}
fin_caso "salud_con_comilla_o_inyeccion_se_veta_sin_escribir (cross-review kimi+grok)"

caso "gitignore_de_veredictos_idempotente"
{
  correr --merge no --despliega no-se --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f .saikit/veredictos/.gitignore ] || _mal "no aseguro .saikit/veredictos/.gitignore"
  [ "$(grep -c -x -F '*' .saikit/veredictos/.gitignore)" = "1" ] || _mal "el .gitignore deberia traer exactamente una linea '*'"
  # Segunda corrida: idempotente, no duplica.
  correr --merge no --despliega no-se --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 0 ] || _mal "segunda corrida deberia salir 0, dio $RC: $OUT"
  [ "$(grep -c -x -F '*' .saikit/veredictos/.gitignore)" = "1" ] || _mal "la segunda corrida duplico la linea '*'"
}
fin_caso "gitignore_de_veredictos_idempotente"

caso "contencion_dos_worktrees_el_segundo_reporta_y_no_escribe"
{
  # El lock vive en el git-common-dir, COMPARTIDO entre worktrees (D20): dos
  # setups a la vez no pueden proceder los dos. A sostiene el lock en fondo,
  # B corre en el otro worktree y tiene que REPORTAR (exit 3) sin escribir.
  git worktree add -q "$SB/otro" -b feat/otro 2>/dev/null \
    || _mal "no se pudo crear el segundo worktree"
  SAIKIT_SETUP_SOSTENER_SEG=6 bash "$SETUP" --merge si --despliega no \
    --sin-verify-app no --telegram no --pr 7 > "$SB/a.log" 2>&1 &
  a_pid=$!
  # Esperar a que A tome el lock (acotado: si no aparece, el caso no mide).
  cont=0
  while [ ! -d .git/saikit-autopilot.lock ] && [ "$cont" -lt 100 ]; do
    sleep 0.1; cont=$((cont + 1))
  done
  [ -d .git/saikit-autopilot.lock ] || _mal "A no tomo el lock; el caso no mide contencion"
  cd "$SB/otro" || exit 1
  OUT="$(bash "$SETUP" --merge si --despliega no --sin-verify-app no \
    --telegram no --pr 8 2>&1)"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "B deberia bloquearse con 3, dio $RC: $OUT"
  _contiene "B reporta el lock" "$OUT" "saikit-autopilot.lock"
  _contiene "B muestra como liberarlo" "$OUT" "--liberar-lock"
  [ ! -e "$SB/otro/.saikit/autopilot.json" ] || _mal "B escribio pese al lock: habria dos setups a la vez"
  wait "$a_pid"; a_rc=$?
  [ "$a_rc" -eq 0 ] || _mal "A deberia terminar en 0, dio $a_rc: $(cat "$SB/a.log")"
  [ -f "$SB/work/.saikit/autopilot.json" ] || _mal "A no escribio su config"
  [ ! -d "$SB/work/.git/saikit-autopilot.lock" ] || _mal "A no libero su lock al salir"
  cd "$SB/work" || exit 1
}
fin_caso "contencion_dos_worktrees_el_segundo_reporta_y_no_escribe"

caso "lock_viejo_pid_muerto_reporta_y_bloquea_sin_borrar"
{
  # La trampa: un lock que se borra solo cuando el pid esta muerto parece
  # amable y es decoracion si el proceso vive en otra maquina. Se REPORTA y
  # BLOQUEA; solo --liberar-lock explicito lo quita.
  lock=".git/saikit-autopilot.lock"
  mkdir -p "$lock"
  printf '99999999' > "$lock/pid"
  printf 'host-viejo' > "$lock/host"
  printf '2000-01-01T00:00:00Z' > "$lock/started_at"
  printf '7' > "$lock/pr"
  correr --merge si --despliega no --sin-verify-app no --telegram no --pr 9
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
  _contiene "reporta el pid" "$OUT" "99999999"
  _contiene "dice que no lo borra solo" "$OUT" "no se borra solo"
  _contiene "dice como liberarlo" "$OUT" "--liberar-lock"
  [ -d "$lock" ] || _mal "borro solo el lock viejo (pid muerto)"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio pese al lock viejo"
}
fin_caso "lock_viejo_pid_muerto_reporta_y_bloquea_sin_borrar"

caso "liberar_lock_muestra_y_quita"
{
  lock=".git/saikit-autopilot.lock"
  mkdir -p "$lock"
  printf '99999999' > "$lock/pid"
  printf 'host-viejo' > "$lock/host"
  printf '2000-01-01T00:00:00Z' > "$lock/started_at"
  printf '7' > "$lock/pr"
  OUT="$(bash "$SETUP" --liberar-lock 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "muestra el contenido" "$OUT" "99999999"
  [ ! -e "$lock" ] || _mal "--liberar-lock no quito el lock"
  # Sin lock, liberar es no-op en verde (idempotente).
  OUT="$(bash "$SETUP" --liberar-lock 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "liberar sin lock deberia salir 0, dio $RC: $OUT"
}
fin_caso "liberar_lock_muestra_y_quita"

# ------------------------------------------------------- mutation-test propio
# Cada mutacion rompe UNA proteccion del script; el caso que la nombra tiene
# que ponerse rojo (mismo mecanismo que tests/test_saikit_merge.sh).
mut_sed() {  # $1=sed-expr, deja el mutado en $MUTADO con HERE al tools/ real
  MUTADO="$SB-mutado-$$.sh"
  { sed "$1" "$SETUP_REAL"; } | sed "s|^HERE=.*$|HERE=$repo/tools|" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre, $2=sed-expr, $3=funcion de caso
  local nombre="$1" expr="$2" fun="$3"
  mut_sed "$expr"
  if cmp -s "$SETUP_REAL" "$MUTADO"; then
    printf '    FAIL: mutacion %s no cambio nada - el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    return
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    printf '    FAIL: mutacion %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    return
  fi
  SETUP="$MUTADO"
  CASO_ROJO=0
  "$fun"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$fun"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  SETUP="${SAIKIT_SETUP_TOOL:-$SETUP_REAL}"
  rm -f "$MUTADO"
}

c_defaults() {
  CASO_ROJO=0; sb_reset
  correr --pr 1 < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(json_get .saikit/autopilot.json merge_despliega)" = "unknown" ] \
    || _mal "merge_despliega deberia nacer unknown"
}

c_flag_valor() {
  CASO_ROJO=0; sb_reset
  OUT="$(timeout 5 bash "$SETUP" --merge 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
}

c_subdir() {
  CASO_ROJO=0; sb_reset
  mkdir -p sub
  cd sub || exit 1
  OUT="$(bash "$SETUP" --merge no --despliega no --sin-verify-app no --telegram no 2>&1)"
  RC=$?
  cd "$SB/work" || exit 1
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f .saikit/autopilot.json ] || _mal "no escribio desde el subdir"
}

c_veto_json() {
  CASO_ROJO=0; sb_reset
  correr --merge no --despliega no --salud-url 'https://x","inyectada":"si' --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio una salud_url con comillas"
}

c_lock_viejo() {
  CASO_ROJO=0; sb_reset
  lock=".git/saikit-autopilot.lock"
  mkdir -p "$lock"
  printf '99999999' > "$lock/pid"
  printf 'host-viejo' > "$lock/host"
  printf '2000-01-01T00:00:00Z' > "$lock/started_at"
  printf '7' > "$lock/pr"
  correr --merge si --despliega no --sin-verify-app no --telegram no --pr 9
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
  [ -d "$lock" ] || _mal "el lock viejo desaparecio (se auto-limpio)"
  [ ! -e .saikit/autopilot.json ] || _mal "escribio pese al lock viejo"
}

c_contencion() {
  CASO_ROJO=0; sb_reset
  git worktree add -q "$SB/otro" -b feat/otro 2>/dev/null \
    || { _mal "no se pudo crear el segundo worktree"; return; }
  SAIKIT_SETUP_SOSTENER_SEG=6 bash "$SETUP" --merge si --despliega no \
    --sin-verify-app no --telegram no --pr 7 > "$SB/a.log" 2>&1 &
  a_pid=$!
  cont=0
  while [ ! -d .git/saikit-autopilot.lock ] && [ "$cont" -lt 100 ]; do
    sleep 0.1; cont=$((cont + 1))
  done
  [ -d .git/saikit-autopilot.lock ] || { _mal "A no tomo el lock"; wait "$a_pid"; return; }
  cd "$SB/otro" || exit 1
  OUT="$(bash "$SETUP" --merge si --despliega no --sin-verify-app no \
    --telegram no --pr 8 2>&1)"
  RC=$?
  [ "$RC" -eq 3 ] || _mal "B deberia bloquearse con 3, dio $RC: $OUT"
  [ ! -e "$SB/otro/.saikit/autopilot.json" ] || _mal "B escribio pese al lock"
  wait "$a_pid"
  cd "$SB/work" || exit 1
}

while IFS=$'\t' read -r nombre expr fun; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun"
done <<'MUTS'
despliega_default_false	s|despliega_default="no-se"|despliega_default="xxx"|	c_defaults
lock_sin_mkdir	s|if mkdir "$LOCK_DIR" 2>/dev/null; then|if true; then|	c_contencion
lock_se_autolimpia	s|# NUNCA se borra solo|rm -rf "$LOCK_DIR"; # NUNCA se borra solo|	c_lock_viejo
flag_sin_valor_pasa	s|if \[ \$# -lt 2 \]; then|if false; then|	c_flag_valor
common_contra_root	s|cd "$INVOC" && cd "$COMMON"|cd "$ROOT" \&\& cd "$COMMON"|	c_subdir
salud_sin_veto	s|printf 'saikit-setup-autopilot: --salud-url no puede traer comillas.*|    ;;|	c_veto_json
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_autopilot_config: FAIL" >&2
  exit 1
fi
echo "test_autopilot_config: OK"
