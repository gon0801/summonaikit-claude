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
# Seis inertes con NOMBRE distinto: el reparto del shard se verifica por
# identidad, no por cantidad (CodeRabbit, PR #101). El driver imprime el nombre
# de cada mutacion que procesa, asi que con nombres unicos se puede exigir la
# union exacta y la interseccion vacia; con seis `inerte` solo se podia contar,
# y un selector que repitiera una y omitiera otra habria sumado seis igual.
mut_in_a() { cat; }
mut_in_b() { cat; }
mut_in_c() { cat; }
mut_in_d() { cat; }
mut_in_e() { cat; }
mut_in_f() { cat; }
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

# ------------------------------------ 5) shard de CI: la union son TODAS (2026-08-29)
# `SAIKIT_MUT_SHARD=i/N` reparte las 111 mutaciones entre N jobs paralelos porque
# este archivo solo se llevaba ~6 de los 6.9 min del CI. Lo que hay que candar no
# es la velocidad: es que la union de las N partes sea la lista ENTERA. Un shard
# que perdiera mutaciones seria un candado que deja de correr sin que nadie se
# entere — la misma falla silenciosa que esta bateria existe para evitar.
#
# Barato como el resto del archivo: el catalogo son mutaciones INERTES, que el
# driver rechaza antes de correr un solo caso; lo que se cuenta es cuantas nombro
# cada parte.
cat_seis='G1|in_a|a
G1|in_b|b
G1|in_c|c
G1|in_d|d
G1|in_e|e
G1|in_f|f'
# Por IDENTIDAD, no por cantidad: el driver nombra cada mutacion que procesa.
nombres_de() {  # $1 = i/N  -> los nombres que proceso esa parte, uno por linea
  SAIKIT_MUT_SHARD="$1" correr_driver "$cat_seis" "$tmp/lib.sh" \
    | grep -oE 'FAIL: in_[a-f]' | sed 's/^FAIL: //' | sort
}
n1="$(nombres_de 1/3)"; n2="$(nombres_de 2/3)"; n3="$(nombres_de 3/3)"

caso "la union de los 3 shards == la lista entera, mutacion por mutacion"
union="$(printf '%s\n%s\n%s\n' "$n1" "$n2" "$n3" | grep -c .)"
distintas="$(printf '%s\n%s\n%s\n' "$n1" "$n2" "$n3" | sort -u | grep -c .)"
esperadas="$(printf 'in_a\nin_b\nin_c\nin_d\nin_e\nin_f\n')"
obtenidas="$(printf '%s\n%s\n%s\n' "$n1" "$n2" "$n3" | sort -u)"
[ "$obtenidas" = "$esperadas" ] || malo "la union no son las 6 esperadas: [$(printf '%s' "$obtenidas" | tr '\n' ' ')]"
# Cardinalidad Y unicidad: si un selector repitiera una y omitiera otra, la
# union seguiria sumando 6 pero con una duplicada — por eso se comparan las dos.
[ "$union" -eq 6 ] || malo "los 3 shards procesaron $union mutaciones, esperaba 6"
[ "$distintas" -eq 6 ] || malo "hay mutaciones repetidas entre shards: $distintas distintas de $union procesadas"

caso "los shards no se pisan entre si (interseccion vacia)"
for par in "1/3:2/3 $n1|$n2" "1/3:3/3 $n1|$n3" "2/3:3/3 $n2|$n3"; do
  etiqueta="${par%% *}"; lados="${par#* }"
  izq="${lados%%|*}"; der="${lados##*|}"
  comunes="$(comm -12 <(printf '%s\n' "$izq" | sort) <(printf '%s\n' "$der" | sort) | grep -c .)"
  [ "$comunes" -eq 0 ] || malo "$etiqueta comparten $comunes mutacion(es)"
done

caso "un shard corre SOLO su parte, no la lista entera"
[ "$(printf '%s\n' "$n1" | grep -c .)" -lt 6 ] || malo "el shard 1/3 corrio las 6: el filtro no se aplico"
for x in "1/3:$n1" "2/3:$n2" "3/3:$n3"; do
  [ "$(printf '%s\n' "${x#*:}" | grep -c .)" -gt 0 ] || malo "el shard ${x%%:*} quedo sin mutaciones"
done

caso "shard con forma invalida => corta con exit 2 y no corre nada"
salida="$(SAIKIT_MUT_SHARD='dos' correr_driver "$cat_seis" "$tmp/lib.sh")"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 con un shard invalido, dio $rc"
printf '%s' "$salida" | grep -q 'SAIKIT_MUT_SHARD invalido' || malo "no nombra el motivo: $salida"
printf '%s' "$salida" | grep -q 'la mutacion no cambio nada' && malo "corrio mutaciones con un shard invalido"

caso "shard fuera de rango => corta con exit 2"
salida="$(SAIKIT_MUT_SHARD='4/3' correr_driver "$cat_seis" "$tmp/lib.sh")"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 con 4/3, dio $rc"
printf '%s' "$salida" | grep -q 'fuera de rango' || malo "no nombra el motivo: $salida"

caso "un shard que queda VACIO no reporta verde"
salida="$(SAIKIT_MUT_SHARD='9/9' correr_driver 'G1|inerte|unica' "$tmp/lib.sh")"; rc=$?
[ "$rc" -ne 0 ] || malo "un shard vacio cerro en verde: $salida"
printf '%s' "$salida" | grep -qi 'vacio' || malo "no dice que quedo vacio: $salida"

if [ "$fail" -ne 0 ]; then
  echo "test_gate_mutations_guards: FAIL" >&2
  exit 1
fi
echo "test_gate_mutations_guards: OK"
