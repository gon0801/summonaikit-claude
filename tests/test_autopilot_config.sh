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
BASE=""
MUTADO=""

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

c_lock_emision() {
  # 20.2: ver el caso lock_ocupado_emite_liberar_ejecutable_con_scripts_100644.
  # Vive como c_ para que la mutacion emision_lock_sin_bash la corra contra el
  # mutado.
  CASO_ROJO=0; sb_reset
  lock=".git/saikit-autopilot.lock"
  mkdir -p "$lock"
  printf '99999999' > "$lock/pid"
  printf 'host-viejo' > "$lock/host"
  printf '2000-01-01T00:00:00Z' > "$lock/started_at"
  printf '7' > "$lock/pr"
  correr --merge si --despliega no --sin-verify-app no --telegram no --pr 9
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
  _contiene "B muestra como liberarlo" "$OUT" "--liberar-lock"
  cmd="$(printf '%s\n' "$OUT" | grep -F 'tools/saikit-setup-autopilot.sh --liberar-lock' | head -1 | sed 's/^[[:space:]]*//')"
  [ -n "$cmd" ] || _mal "no se pudo extraer el comando de liberacion"
  rm -rf tools
  cp -R "$repo/tools" tools
  cp "$SETUP" tools/saikit-setup-autopilot.sh   # el (posible) mutado
  find tools -type f -exec chmod 644 {} +
  OUT2="$(eval "$cmd" 2>&1)"; RC2=$?
  [ "$RC2" -eq 0 ] || _mal "la forma emitida fallo con scripts 100644 (rc=$RC2): $OUT2"
  _contiene "libera de verdad" "$OUT2" "lock liberado"
  [ ! -e "$lock" ] || _mal "la forma emitida no quito el lock"
  _no_contiene "sin denegacion de ejecucion" "$OUT2" "denied"
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

caso "escritura_fallida_no_pisa_config_previa (lead PR #161)"
{
  # Config previa VALIDA + intento que falla (salud_url que no puede entrar al
  # JSON): la previa tiene que quedar byte-identica. Con el veto activo el
  # rechazo es antes de escribir; la mutacion veto_y_validacion_fuera (abajo)
  # ejerce la rama de escritura que este caso nombra.
  mkdir -p .saikit
  printf '{"merge":false}' > .saikit/autopilot.json
  antes="$(cksum < .saikit/autopilot.json)"
  correr --merge no --despliega no --salud-url 'https://x","merge":true' --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -ne 0 ] || _mal "rc esperaba != 0, dio $RC: $OUT"
  [ "$(cksum < .saikit/autopilot.json)" = "$antes" ] || _mal "piso la config previa valida"
}
fin_caso "escritura_fallida_no_pisa_config_previa (lead PR #161)"

caso "saikit_simbolico_se_rechaza_sin_escribir_a_traves (lead PR #161)"
{
  # .saikit como symlink a un dir ajeno con centinela: el setup falla (exit 2)
  # y NUNCA escribe a traves del enlace.
  mkdir -p "$SB/afuera"
  printf 'centinela\n' > "$SB/afuera/centinela.txt"
  ln -s "$SB/afuera" .saikit
  correr --merge no --despliega no --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "nombra el enlace" "$OUT" "enlace simbolico"
  [ ! -e "$SB/afuera/autopilot.json" ] || _mal "escribio autopilot.json a traves del enlace"
  [ ! -e "$SB/afuera/veredictos" ] || _mal "escribio veredictos/ a traves del enlace"
  [ "$(cat "$SB/afuera/centinela.txt")" = "centinela" ] || _mal "el centinela del dir apuntado no sobrevivio"
}
fin_caso "saikit_simbolico_se_rechaza_sin_escribir_a_traves (lead PR #161)"

caso "veredictos_simbolico_se_rechaza_sin_escribir_a_traves (review ronda 2)"
{
  # .saikit real pero veredictos/ como symlink a un dir ajeno con centinela:
  # mkdir -p "ya existe" a traves del enlace y el append del .gitignore
  # escribiria FUERA del repo (hallazgo del reviewer, ronda 2).
  mkdir -p .saikit "$SB/afuera-v"
  printf 'centinela\n' > "$SB/afuera-v/centinela.txt"
  ln -s "$SB/afuera-v" .saikit/veredictos
  correr --merge no --despliega no --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "nombra el enlace" "$OUT" "enlace simbolico"
  [ ! -e "$SB/afuera-v/.gitignore" ] || _mal "escribio el .gitignore a traves del enlace de veredictos"
  [ "$(cat "$SB/afuera-v/centinela.txt")" = "centinela" ] || _mal "el centinela del dir apuntado no sobrevivio"
}
fin_caso "veredictos_simbolico_se_rechaza_sin_escribir_a_traves (review ronda 2)"

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

caso "wrapper_bateria_no_reconocida_se_genera_y_corre"
{
  # 22.1 via (a): repo cuya bateria es tests/test_app.sh (medido 20.10).
  mkdir -p tests
  printf '#!/bin/sh\necho BATERIA-REAL-OK\n' > tests/test_app.sh
  chmod +x tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f tests/run.sh ] || _mal "no genero tests/run.sh: $OUT"
  [ -x tests/run.sh ] || _mal "el wrapper no quedo ejecutable"
  _contiene "nombra el wrapper" "$OUT" "wrapper escrito"
  WOUT="$(bash tests/run.sh 2>&1)"; WRC=$?
  [ "$WRC" -eq 0 ] || _mal "el wrapper fallo con rc=$WRC: $WOUT"
  _contiene "el wrapper corre la bateria real" "$WOUT" "BATERIA-REAL-OK"
}
fin_caso "wrapper_bateria_no_reconocida_se_genera_y_corre"

caso "wrapper_noop_con_run_sh_real"
{
  mkdir -p tests
  printf '#!/bin/sh\necho MIO\n' > tests/run.sh
  chmod +x tests/run.sh
  antes="$(cksum < tests/run.sh)"
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cksum < tests/run.sh)" = "$antes" ] || _mal "piso un tests/run.sh real"
  _contiene "verifica el runner" "$OUT" "runner reconocido"
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$(cksum < tests/run.sh)" = "$antes" ] || _mal "la segunda corrida toco tests/run.sh"
}
fin_caso "wrapper_noop_con_run_sh_real"

caso "wrapper_sin_bateria_avisa_y_no_inventa"
{
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "invento un wrapper sin bateria"
  _contiene "avisa sin bateria" "$OUT" "sin bateria detectable"
}
fin_caso "wrapper_sin_bateria_avisa_y_no_inventa"

caso "wrapper_multiples_candidatos_no_adivina"
{
  mkdir -p tests
  : > tests/test_a.sh
  : > tests/test_b.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "adivino entre varias baterias"
  _contiene "nombra las candidatas" "$OUT" "no se adivina"
}
fin_caso "wrapper_multiples_candidatos_no_adivina"

caso "wrapper_reconocido_npm_no_ofrece"
{
  printf '{"name":"x","scripts":{"test":"jest"}}' > package.json
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "genero wrapper con npm test reconocido"
  _contiene "reconoce npm" "$OUT" "runner reconocido"
}
fin_caso "wrapper_reconocido_npm_no_ofrece"

caso "wrapper_default_no_sin_tty"
{
  mkdir -p tests
  printf '#!/bin/sh\necho X\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "genero wrapper sin consentimiento (sin TTY)"
  _contiene "avisa que el gate lo exige" "$OUT" "sin wrapper"
}
fin_caso "wrapper_default_no_sin_tty"

caso "wrapper_carrera_pre_rechequeo_no_pisa"
{
  # 22.1r2 P2(1): tests/run.sh aparece entre consentimiento y publish — el
  # rechequeo lo ve y no se pisa (espejo de escribir_atomico de ci-minimo).
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  export SAIKIT_SETUP_BEFORE_WRITE='printf "MIO" > tests/run.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  unset SAIKIT_SETUP_BEFORE_WRITE
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cat tests/run.sh 2>/dev/null)" = "MIO" ] || _mal "piso el run.sh aparecido en carrera"
  _contiene "reporta la carrera" "$OUT" "carrera: ya hay tests/run.sh; no se pisa"
}
fin_caso "wrapper_carrera_pre_rechequeo_no_pisa"

caso "wrapper_carrera_post_rechequeo_no_pisa"
{
  # 22.1r2 P2(1): aparece DESPUES del rechequeo (ventana TOCTOU) — mv -n no
  # reemplaza y se reporta (el temporal sobreviviente delata la carrera).
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  export SAIKIT_SETUP_BEFORE_MV='printf "MIO" > tests/run.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  unset SAIKIT_SETUP_BEFORE_MV
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cat tests/run.sh 2>/dev/null)" = "MIO" ] || _mal "piso el run.sh aparecido en la ventana TOCTOU"
  _contiene "reporta la carrera tardia" "$OUT" "carrera: tests/run.sh aparecio al publicar; no se pisa"
}
fin_caso "wrapper_carrera_post_rechequeo_no_pisa"

caso "wrapper_instrucciones_exigen_commitear_run_sh"
{
  # 22.1r2 P2(2): si se escribio el wrapper, las instrucciones finales exigen
  # subirlo — local no sirve: el gate no lo ve y el merge sigue bloqueado.
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "exige commitear el wrapper" "$OUT" "incluye tambien tests/run.sh en el commit"
}
fin_caso "wrapper_instrucciones_exigen_commitear_run_sh"

caso "wrapper_run_sh_symlink_no_se_toca"
{
  # 22.1r1: tests/run.sh es un enlace (apunta a una bateria real) + hay
  # candidata: no se reemplaza el enlace ni se escribe a traves.
  mkdir -p tests real
  printf '#!/bin/sh\nexit 0\n' > real/bateria.sh
  ln -s ../real/bateria.sh tests/run.sh
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -L tests/run.sh ] || _mal "reemplazo o resolvio el enlace tests/run.sh"
  [ "$(readlink tests/run.sh)" = "../real/bateria.sh" ] || _mal "retoco el enlace: $(readlink tests/run.sh)"
  _contiene "nombra el enlace" "$OUT" "enlace simbolico"
}
fin_caso "wrapper_run_sh_symlink_no_se_toca"

caso "wrapper_tests_symlink_no_se_sigue"
{
  # 22.1r1: tests/ es un enlace a un dir con bateria: el rastreo no lo
  # sigue (ni descubre candidata adentro ni escribe en el destino).
  mkdir -p real/tests
  printf '#!/bin/sh\nexit 0\n' > real/tests/test_app.sh
  ln -s real/tests tests
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e real/tests/run.sh ] || _mal "escribio el wrapper dentro del destino del enlace"
  [ ! -e tests/run.sh ] || _mal "escribio a traves del enlace tests/"
  _contiene "no descubre bateria tras el enlace" "$OUT" "sin bateria detectable"
}
fin_caso "wrapper_tests_symlink_no_se_sigue"

caso "wrapper_nombres_peligrosos_se_vetan"
{
  # 22.1r1: $ expande en runtime a otro archivo; " rompe la linea exec
  # (el veto avisa antes que el backstop bash -n); \ se lee como escape;
  # salto crudo parte el script. Ninguno se envuelve.
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > 'tests/a$b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió bateria con \$ en el nombre"
  _contiene "veta el \$" "$OUT" 'comillas, $, \ o controles'
  rm -f 'tests/a$b.sh'
  printf '#!/bin/sh\nexit 0\n' > 'tests/a"b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió bateria con comilla en el nombre"
  _contiene "veta la comilla" "$OUT" 'comillas, $, \ o controles'
  rm -f 'tests/a"b.sh'
  printf '#!/bin/sh\nexit 0\n' > 'tests/a\b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió bateria con backslash en el nombre"
  _contiene "veta el backslash" "$OUT" 'comillas, $, \ o controles'
  rm -f 'tests/a\b.sh' tests/run.sh
  printf '#!/bin/sh\nexit 0\n' > "$(printf 'tests/a\nb.sh')"
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió bateria con salto en el nombre"
  _contiene "veta el salto" "$OUT" 'comillas, $, \ o controles'
}
fin_caso "wrapper_nombres_peligrosos_se_vetan"

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

caso "lock_ocupado_emite_liberar_ejecutable_con_scripts_100644"
{
  # 20.2: el hint de LOCK ocupado ("liberalo explicito con: ...") tiene que
  # correr TAL CUAL aunque el checkout este 100644 (sin bit de ejecucion).
  # Se ejecuta de VERDAD la linea emitida contra una copia del repo con el bit
  # quitado — chmod 644, JAMAS chmod +x — y libera el lock de verdad. No hay
  # git ni gh involucrados: el liberar es local al sandbox.
  c_lock_emision
}
fin_caso "lock_ocupado_emite_liberar_ejecutable_con_scripts_100644"

# ------------------------------------------------------- mutation-test propio
# Cada mutacion rompe UNA proteccion del script; el caso que la nombra tiene
# que ponerse rojo (mismo mecanismo que tests/test_saikit_merge.sh).
# La guarda anti-sed-obsoleto baselinea contra BASE (la copia ya reescrita en
# HERE, SIN mutar): comparar contra $SETUP_REAL nunca daba iguales porque el
# original conserva su HERE real, y la guarda no disparaba jamas (hallazgo del
# lead, PR #161).
mut_sed() {  # $1=sed-expr; BASE=reescritura de HERE sin mutar, MUTADO=BASE mutado
  BASE="$SB-base-$$.sh"
  MUTADO="$SB-mutado-$$.sh"
  sed "s|^HERE=.*$|HERE=$repo/tools|" "$SETUP_REAL" > "$BASE"
  sed "$1" "$BASE" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre, $2=sed-expr, $3=funcion de caso
  local nombre="$1" expr="$2" fun="$3"
  mut_sed "$expr"
  if cmp -s "$BASE" "$MUTADO"; then
    printf '    FAIL: mutacion %s no cambio nada - el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    rm -f "$MUTADO" "$BASE"
    return
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    printf '    FAIL: mutacion %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    rm -f "$MUTADO" "$BASE"
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
  rm -f "$MUTADO" "$BASE"
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

c_atomico() {
  # Con el veto Y la validacion del temporal anulados, una escritura que no
  # valida tiene que dejar la config previa byte-identica (la compuerta es la
  # validacion del temporal ANTES del mv; la atomicidad evita archivos a medias).
  CASO_ROJO=0; sb_reset
  mkdir -p .saikit
  printf '{"merge":false}' > .saikit/autopilot.json
  antes="$(cksum < .saikit/autopilot.json)"
  correr --merge no --despliega no --salud-url 'https://x","merge":true' --sin-verify-app no --telegram no < /dev/null
  [ "$(cksum < .saikit/autopilot.json)" = "$antes" ] || _mal "una escritura que no valida piso la config previa"
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

c_wrap() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\necho BATERIA-REAL-OK\n' > tests/test_app.sh
  chmod +x tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -f tests/run.sh ] || _mal "no genero tests/run.sh: $OUT"
  _contiene "nombra el wrapper" "$OUT" "wrapper escrito"
}

c_wrap_symlink() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests real
  printf '#!/bin/sh\nexit 0\n' > real/bateria.sh
  ln -s ../real/bateria.sh tests/run.sh
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -L tests/run.sh ] || _mal "reemplazo o resolvio el enlace tests/run.sh"
  _contiene "nombra el enlace" "$OUT" "enlace simbolico"
}

c_wrap_tests_symlink() {
  # Espejo de wrapper_tests_symlink_no_se_sigue para la mutacion
  # wrap_symlink_tests_dir: sin el guard del dir, el rastreo descubre la
  # bateria tras el enlace y el motivo cambia a "enlace simbolico".
  CASO_ROJO=0; sb_reset
  mkdir -p real/tests
  printf '#!/bin/sh\nexit 0\n' > real/tests/test_app.sh
  ln -s real/tests tests
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e real/tests/run.sh ] || _mal "escribio el wrapper dentro del destino del enlace"
  [ ! -e tests/run.sh ] || _mal "escribio a traves del enlace tests/"
  _contiene "no descubre bateria tras el enlace" "$OUT" "sin bateria detectable"
}

c_wrap_multi() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  : > tests/test_a.sh
  : > tests/test_b.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "eligio entre varias baterias"
  _contiene "no adivina" "$OUT" "no se adivina"
}

c_wrap_consent() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "escribio sin consentimiento"
  _contiene "avisa" "$OUT" "sin wrapper"
}

c_wrap_dollar() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > 'tests/a$b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió nombre con dolar"
  _contiene "veta" "$OUT" "o controles"
}

c_wrap_dquote() {
  # La comilla es el unico veto cuya caida cambia el MOTIVO (el backstop
  # bash -n la ataja con "no parsea"): este helper pineado al mensaje del
  # veto demuestra ambas guardas — si el veto cae, el motivo cambia.
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > 'tests/a"b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió nombre con comilla"
  _contiene "veta por la guarda veto, no por -n" "$OUT" "comillas, $, \\ o controles"
}

c_wrap_backtick() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > 'tests/a`b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió nombre con backtick"
  _contiene "veta" "$OUT" "o controles"
}

c_wrap_newline() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > "$(printf 'tests/a\nb.sh')"
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió nombre con salto"
  _contiene "veta" "$OUT" "o controles"
}

c_wrap_backslash() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > 'tests/a\b.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -e tests/run.sh ] || _mal "envolvió nombre con backslash"
  _contiene "veta" "$OUT" "o controles"
}

c_race_recheck() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  export SAIKIT_SETUP_BEFORE_WRITE='printf "MIO" > tests/run.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  unset SAIKIT_SETUP_BEFORE_WRITE
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cat tests/run.sh 2>/dev/null)" = "MIO" ] || _mal "piso el run.sh aparecido en carrera"
  _contiene "reporta la carrera" "$OUT" "carrera: ya hay tests/run.sh; no se pisa"
}

c_race_mv() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  export SAIKIT_SETUP_BEFORE_MV='printf "MIO" > tests/run.sh'
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  unset SAIKIT_SETUP_BEFORE_MV
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ "$(cat tests/run.sh 2>/dev/null)" = "MIO" ] || _mal "piso el run.sh aparecido en la ventana TOCTOU"
  _contiene "reporta la carrera tardia" "$OUT" "carrera: tests/run.sh aparecio al publicar; no se pisa"
}

c_wrap_instr() {
  CASO_ROJO=0; sb_reset
  mkdir -p tests
  printf '#!/bin/sh\nexit 0\n' > tests/test_app.sh
  correr --merge no --despliega no --sin-verify-app no --telegram no --wrap-runner si < /dev/null
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "exige commitear el wrapper" "$OUT" "incluye tambien tests/run.sh en el commit"
}

while IFS=$'\t' read -r nombre expr fun; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun"
done <<'MUTS'
despliega_default_false	s|despliega_default="no-se"|despliega_default="xxx"|	c_defaults
wrap_nunca_instala	s|mv -n "$WRAP_TMP" "$WRAP"|true|	c_wrap
wrap_symlink_run_sh	s|elif \[ -L "\$WRAP" \]; then|elif false; then|	c_wrap_symlink
wrap_symlink_tests_dir	s# && \[ ! -L "\$ROOT/\$WRAP_D" \]##	c_wrap_tests_symlink
wrap_multi_elige	s|elif \[ "\$WRAP_N" -gt 1 \]; then|elif false; then|	c_wrap_multi
wrap_sin_consentimiento	s|^              WRAP_VOL=NO$|              WRAP_VOL=SI|	c_wrap_consent
wrap_veto_dollar	s#|\*\\\$\*##	c_wrap_dollar
wrap_veto_dquote	s#\*\\"\*|\*\\\$\*#*\\$*#	c_wrap_dquote
wrap_veto_backtick	s#|\*\\[`]\*##	c_wrap_backtick
wrap_veto_cntrl	s#\*\\[`]\*|\*\[\[:cntrl:\]\]\*#*\\`*#	c_wrap_newline
wrap_veto_backslash	s#|\*\\\\\*)#)#	c_wrap_backslash
wrap_carrera_sin_recheck	s#if \[ -e "\$WRAP" \] || \[ -L "\$WRAP" \]; then#if false; then#	c_race_recheck
wrap_carrera_mvf	s|mv -n "$WRAP_TMP" "$WRAP"|mv -f "$WRAP_TMP" "$WRAP"|	c_race_mv
wrap_instr_sin_runsh	s|if \[ "\$WRAP_ESCRITO" = 1 \]; then|if false; then|	c_wrap_instr
lock_sin_mkdir	s|if mkdir "$LOCK_DIR" 2>/dev/null; then|if true; then|	c_contencion
lock_se_autolimpia	s|# NUNCA se borra solo|rm -rf "$LOCK_DIR"; # NUNCA se borra solo|	c_lock_viejo
flag_sin_valor_pasa	s|if \[ \$# -lt 2 \]; then|if false; then|	c_flag_valor
common_contra_root	s|cd "$INVOC" && cd "$COMMON"|cd "$ROOT" \&\& cd "$COMMON"|	c_subdir
salud_sin_veto	s|printf 'saikit-setup-autopilot: --salud-url no puede traer comillas.*|    ;;|	c_veto_json
veto_y_validacion_fuera	s|printf 'saikit-setup-autopilot: --salud-url no puede traer comillas.*|    ;;|;s|if ! saikit_json_valido "\$(cat "\$CFG_TMP")"; then|if false; then|	c_atomico
emision_lock_sin_bash	s|bash tools/saikit-setup-autopilot.sh --liberar-lock|tools/saikit-setup-autopilot.sh --liberar-lock|	c_lock_emision
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_autopilot_config: FAIL" >&2
  exit 1
fi
echo "test_autopilot_config: OK"
