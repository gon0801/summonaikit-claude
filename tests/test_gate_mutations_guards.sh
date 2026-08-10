#!/usr/bin/env bash
# Task 1.3 — las guardias del mutation-test, probadas.
#
# `tests/test_gate_mutations.sh` sale verde cuando cada mutacion es atrapada por
# algun caso. Pero "13 de 13 atrapadas" describe igual de bien a un driver que
# no sabe ponerse en rojo: si sus guardias estuvieran mal escritas, tambien
# diria OK, y toda la garantia de la Task 1.3 seria teatro.
#
# Esta bateria le pone al driver, una por una, las cuatro situaciones que TIENE
# que rechazar, y exige que rompa la corrida en cada una. Es el mismo criterio
# que ya usa `tests/test_runner_guards.sh` con el runner: al verificador se lo
# verifica.
#
# Barato a proposito: las tres primeras guardias cortan ANTES de correr ningun
# caso, asi que cada una cuesta una sola corrida del hook (la que el banco usa
# para descubrir la ruta de estado).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
driver="$here/test_gate_mutations.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_gate_mutations_guards: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_gate_mutations_guards")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-mutg-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# Mutaciones de mentira, solo para esta bateria.
cat > "$tmp/lib.sh" <<'LIB'
# No toca nada: simula un `sed` que quedo obsoleto porque el hook cambio de
# forma y ya no matchea.
mut_inerte() { cat; }
# Cambia el archivo pero lo deja sin parsear.
mut_rompe_sintaxis() { printf 'if [\n'; cat; }
LIB

correr_driver() { # $1 = catalogo, $2 = lib (opcional)
  SAIKIT_MUTACIONES="$1" SAIKIT_MUTACIONES_LIB="${2:-}" bash "$driver" 2>&1
}

# ------------------------------------------------- 1) la mutacion no existe
caso "mutacion sin funcion que la aplique => rompe la corrida"
salida="$(correr_driver 'G1|no_existe_esta_mutacion|una mutacion inventada')"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0, salio 0"
printf '%s' "$salida" | grep -q 'no existe la funcion' || malo "no nombra el motivo (funcion inexistente)"

# ---------------------------------------------------- 2) el sed quedo obsoleto
caso "mutacion que no cambia el hook => rompe la corrida (sed obsoleto)"
salida="$(correr_driver 'G1|inerte|no cambia nada' "$tmp/lib.sh")"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0, salio 0"
printf '%s' "$salida" | grep -q 'no cambio nada' || malo "no nombra el motivo (mutacion inerte)"

# --------------------------------------------------- 3) el hook mutado no corre
caso "mutacion que rompe la sintaxis => rompe la corrida (no probaria nada)"
salida="$(correr_driver 'G1|rompe_sintaxis|deja el hook sin parsear' "$tmp/lib.sh")"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0, salio 0"
printf '%s' "$salida" | grep -q 'no parsea' || malo "no nombra el motivo (sintaxis rota)"

# ------------------------------------------- 4) la mutacion pasa desapercibida
# El caso que le da sentido a todo: una mutacion REAL, valida y aplicada, pero
# atribuida a un gate cuyos casos no la pueden ver (se sube el presupuesto de
# ciclos y se declara como si fuera del gate del sentinel). Los casos de G1
# quedan todos en verde, y el driver tiene que llamarlo lo que es: ese gate no
# esta atado.
caso "mutacion real que ningun caso del gate detecta => rompe la corrida"
salida="$(correr_driver 'G1|presupuesto_infinito|mutacion real atribuida a un gate que no la cubre')"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0, salio 0: el driver no sabe ponerse en rojo"
printf '%s' "$salida" | grep -q 'ningun caso detecto' || malo "no nombra el motivo (gate sin atar)"

if [ "$fail" -ne 0 ]; then
  echo "test_gate_mutations_guards: FAIL" >&2
  exit 1
fi
echo "test_gate_mutations_guards: OK"
