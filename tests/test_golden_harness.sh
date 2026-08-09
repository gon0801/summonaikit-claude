#!/usr/bin/env bash
# Task 1.2 — el ARNES de salida dorada cumple lo que promete.
#
# Este test NO mira el hook vivo: prueba la herramienta contra un hook FALSO y
# escenarios FALSOS, todo adentro del sandbox. La comparacion contra el archivo
# vivo es el otro test (`test_golden_baseline.sh`); separarlos es lo que permite
# que este corra igual en una maquina donde el hook vivo no existe.
#
# Lo que se mide aca es exactamente lo que hace confiable a una linea base:
#   - que sea REPRODUCIBLE (dos corridas dan lo mismo);
#   - que DETECTE un cambio de comportamiento (si no, siempre diria "identico"
#     y no probaria nada — es el mutation-test que pide el DoD);
#   - que distinga "divergente" de "no se pudo mirar" (Core Rule 2);
#   - que no pueda salir verde con cobertura CERO;
#   - que jamas escriba al lado del hook que ejercita, ni en `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
arnes="$repo/tools/golden-harness.sh"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# --------------------------------------------------------------- utilleria
# Copia el hook falso y sus escenarios al sandbox. Se copian (no se usan en su
# lugar) para que el caso de aislamiento pueda mirar el ORIGINAL y comprobar
# que el arnes no le dejo nada al lado.
armar_falso() {
  destino="$1"
  mkdir -p "$destino"
  cp -r "$repo/tests/fixtures/arnes-falso/." "$destino/"
}

falso="$SANDBOX/falso"
armar_falso "$falso"
hook_falso="$falso/hook-falso.sh"
esc_falsos="$falso/escenarios"
base="$SANDBOX/baseline.txt"

correr() {
  # correr <archivo-salida> <args...> ; deja el exit code en $rc
  salida="$1"; shift
  bash "$arnes" "$@" > "$salida" 2>&1
  rc=$?
}

# ------------------------------------------------------- 1) reproducibilidad
caso "dos corridas contra el mismo hook dan un registro byte-identico"
correr "$SANDBOX/p1.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -eq 0 ] || malo "--print debio salir 0, dio $rc: $(cat "$SANDBOX/p1.txt")"
correr "$SANDBOX/p2.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
if ! cmp -s "$SANDBOX/p1.txt" "$SANDBOX/p2.txt"; then
  malo "el registro NO es reproducible entre corridas"
  diff -u "$SANDBOX/p1.txt" "$SANDBOX/p2.txt" | head -20 >&2
fi

# --------------------------------------------- 2) el registro tiene contenido
caso "el registro nombra cada escenario y trae exit code y stdout de cada paso"
for e in 01-verde 02-bloqueo; do
  grep -q "$e" "$SANDBOX/p1.txt" || malo "el registro no nombra el escenario $e"
done
grep -q '^exit ' "$SANDBOX/p1.txt" || malo "el registro no trae el exit code de los pasos"
grep -q 'stdout' "$SANDBOX/p1.txt" || malo "el registro no trae el stdout de los pasos"
grep -qi 'sha256' "$SANDBOX/p1.txt" || malo "el registro no declara la identidad del hook (sha256)"

# ------------------------------------------------------ 3) record + check ok
caso "--record y despues --check contra el MISMO hook => 0"
correr "$SANDBOX/rec.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base" --record
[ "$rc" -eq 0 ] || malo "--record debio salir 0, dio $rc: $(cat "$SANDBOX/rec.txt")"
[ -s "$base" ] || malo "--record no escribio la linea base"
correr "$SANDBOX/chk.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 0 ] || malo "--check contra el mismo hook debio salir 0, dio $rc: $(cat "$SANDBOX/chk.txt")"

# ------------------------------------- 4) mutation-test: detecta la diferencia
caso "hook MUTADO => --check falla (1) y nombra el escenario divergente"
mutado="$SANDBOX/hook-mutado.sh"
sed 's/{"ok":true}/{"ok":false}/' "$hook_falso" > "$mutado"
cmp -s "$hook_falso" "$mutado" && malo "la mutacion no cambio nada; el caso no probaria nada"
correr "$SANDBOX/mut.txt" --hook "$mutado" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 1 ] || malo "un hook mutado debe dar divergencia (exit 1), dio $rc"
grep -q '01-verde' "$SANDBOX/mut.txt" || malo "no nombra el escenario divergente: $(cat "$SANDBOX/mut.txt")"

caso "mutacion en el ESTADO (no en stdout) tambien se detecta"
mutado2="$SANDBOX/hook-mutado2.sh"
sed 's/^ESTADO_NOMBRE=.*/ESTADO_NOMBRE=otro.env/' "$hook_falso" > "$mutado2"
cmp -s "$hook_falso" "$mutado2" && malo "la mutacion de estado no cambio nada"
correr "$SANDBOX/mut2.txt" --hook "$mutado2" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 1 ] || malo "un cambio en el ESTADO que deja el hook debe detectarse, dio $rc"

# ------------------------------------------------- 5) unknown != divergencia
caso "hook inexistente => exit 2 y 'unknown', nunca 'identico' (Core Rule 2)"
correr "$SANDBOX/nohook.txt" --hook "$SANDBOX/no-existe.sh" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 2 ] || malo "sin hook que mirar el veredicto es unknown (exit 2), dio $rc"
grep -qi 'unknown' "$SANDBOX/nohook.txt" || malo "no dice unknown: $(cat "$SANDBOX/nohook.txt")"

caso "linea base inexistente => exit 2 y 'unknown', no un falso verde"
correr "$SANDBOX/nobase.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$SANDBOX/no-hay.txt" --check
[ "$rc" -eq 2 ] || malo "sin linea base el veredicto es unknown (exit 2), dio $rc"
grep -qi 'unknown' "$SANDBOX/nobase.txt" || malo "no dice unknown: $(cat "$SANDBOX/nobase.txt")"

# --------------------------------------------- 6) cobertura cero != verde
caso "directorio de escenarios vacio => falla, no pasa como verde"
mkdir -p "$SANDBOX/sin-escenarios"
correr "$SANDBOX/vacio.txt" --hook "$hook_falso" --scenarios "$SANDBOX/sin-escenarios" --print
[ "$rc" -ne 0 ] || malo "cero escenarios NO puede salir 0: seria 'todo verde' sin haber corrido nada"

caso "directorio de escenarios inexistente => falla"
correr "$SANDBOX/noesc.txt" --hook "$hook_falso" --scenarios "$SANDBOX/no-existe-dir" --print
[ "$rc" -ne 0 ] || malo "un directorio de escenarios inexistente NO puede salir 0"

# ------------------------------------------- 6-bis) basura del entorno
# Medido: el tooling del entorno deja directorios `.claude` vacios adentro de
# cualquier arbol donde se trabaje. Uno de esos colandose como "escenario"
# mete un bloque vacio en la linea base — cobertura fantasma que nadie pidio.
caso "un directorio oculto en el arbol de escenarios NO cuenta como escenario"
mkdir -p "$esc_falsos/.claude"
correr "$SANDBOX/oculto.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
grep -q '^=== escenario \.' "$SANDBOX/oculto.txt" && malo "un directorio oculto se colo como escenario"
[ "$(grep -c '^=== escenario ' "$SANDBOX/oculto.txt")" = "2" ] \
  || malo "esperaba exactamente 2 escenarios, hubo $(grep -c '^=== escenario ' "$SANDBOX/oculto.txt")"
rmdir "$esc_falsos/.claude"

# --------------------------------------------------------- 7) aislamiento
caso "el arnes NO escribe al lado del hook que ejercita"
[ ! -e "$falso/state" ] || malo "AISLAMIENTO ROTO: dejo state/ junto al hook original"
[ -z "$(find "$falso" -newer "$arnes" -name '*.env' 2>/dev/null)" ] \
  || malo "AISLAMIENTO ROTO: escribio estado adentro del arbol del hook original"

caso "el arnes NO escribe en \$HOME/.claude"
sobras="$(find "$HOME/.claude" -type f 2>/dev/null | head -5)"
[ -z "$sobras" ] || malo "AISLAMIENTO ROTO: escribio en \$HOME/.claude: $sobras"

# ------------------------------------ 8) la identidad no decide el veredicto
# Phase 2.1 va a cambiar el hook a proposito (le agrega el marcador de
# propiedad): ahi el sha CAMBIA y el comportamiento debe seguir igual. Si el
# arnes comparara la identidad, ese caso legitimo daria rojo y el arnes no
# serviria justo para lo que existe.
caso "hook con bytes distintos pero MISMO comportamiento => --check sale 0 y avisa del cambio de identidad"
marcado="$SANDBOX/hook-marcado.sh"
{ head -n 1 "$hook_falso"; printf '# SAIKIT-CLAUDE-OWNED summonaikit-claude 0.0.0-test\n'; tail -n +2 "$hook_falso"; } > "$marcado"
cmp -s "$hook_falso" "$marcado" && malo "el fixture marcado quedo identico; el caso no probaria nada"
correr "$SANDBOX/marcado.txt" --hook "$marcado" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 0 ] || malo "mismo comportamiento con otros bytes debe salir 0, dio $rc: $(cat "$SANDBOX/marcado.txt")"
grep -qi 'identidad' "$SANDBOX/marcado.txt" || malo "deberia AVISAR que el hook cambio de identidad: $(cat "$SANDBOX/marcado.txt")"

if [ "$fail" -ne 0 ]; then
  echo "test_golden_harness: FAIL" >&2
  exit 1
fi
echo "test_golden_harness: OK"
