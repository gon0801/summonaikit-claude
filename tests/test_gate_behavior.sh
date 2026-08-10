#!/usr/bin/env bash
# Task 1.3 — la semantica ACTUAL del gate, afirmada caso por caso.
#
# La Task 1.2 dejo una GRABACION del comportamiento del hook: detecta que algo
# cambio, pero no dice que. Esta bateria dice que. Cada gate del hook tiene por
# lo menos un caso que pasa y uno que bloquea, y cada caso nombra la condicion
# que ejercita.
#
# Los casos viven en `tests/lib/gate_cases.sh` porque los consumen DOS baterias
# con veredictos opuestos: esta (todos verdes contra el hook vivo) y
# `tests/test_gate_mutations.sh` (al menos uno rojo contra un hook con la
# condicion de un gate rota). La segunda es la que prueba que esta sirve.
#
# En una maquina donde el hook vivo no existe no hay nada que afirmar: se
# reporta `unknown` y no se cuenta como falla (Core Rule 2). Un rojo ahi seria
# una alarma falsa que entrena a ignorar el test.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_gate_behavior: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_gate_behavior")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

fail=0

# --------------------------------------------------- el indice tiene que cerrar
# Un caso definido pero no listado NO CORRE, y la bateria seguiria verde
# reportando menos cobertura de la que cree tener. Se compara la lista contra
# las funciones realmente definidas antes de correr nada.
definidos="$(declare -F | sed 's/^declare -f //' | grep '^caso_' | sort)"
listados="$(todos_los_casos | tr ' ' '\n' | grep -v '^$' | sort)"

huerfanos="$(comm -23 <(printf '%s\n' "$definidos") <(printf '%s\n' "$listados"))"
fantasmas="$(comm -13 <(printf '%s\n' "$definidos") <(printf '%s\n' "$listados"))"
repetidos="$(printf '%s\n' "$listados" | uniq -d)"

if [ -n "$huerfanos" ]; then
  printf '    FAIL: casos definidos que no estan en ninguna lista (no corren):\n%s\n' "$huerfanos" >&2
  fail=1
fi
if [ -n "$fantasmas" ]; then
  printf '    FAIL: casos listados que no existen como funcion:\n%s\n' "$fantasmas" >&2
  fail=1
fi
if [ -n "$repetidos" ]; then
  printf '    FAIL: casos listados mas de una vez:\n%s\n' "$repetidos" >&2
  fail=1
fi

# ------------------------------------------------------------------- la corrida
HOOK_BAJO_PRUEBA="$vivo"
if ! lab_init; then
  echo "test_gate_behavior: FAIL — no se pudo montar el banco de pruebas" >&2
  exit 1
fi
trap 'lab_fin' EXIT

for gate in $GATES; do
  printf '  gate %s\n' "$gate"
  for caso in $(casos_de_gate "$gate"); do
    if correr_caso "$caso"; then
      printf '    ok: %s\n' "$caso"
    else
      printf '    ROJO: %s\n' "$caso" >&2
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "test_gate_behavior: FAIL" >&2
  exit 1
fi
echo "test_gate_behavior: OK"
