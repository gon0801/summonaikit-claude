#!/usr/bin/env bash
# Task 1.2 — la linea base guardada sigue describiendo al archivo VIVO.
#
# Este es el test que da el valor: re-correr el arnes contra el hook vivo tiene
# que dar el MISMO resultado que quedo grabado. Cuando deje de darlo, el hook
# vivo cambio de comportamiento — y eso es exactamente lo que hay que enterarse
# antes de reemplazarlo (Phase 2), no despues.
#
# Dos aclaraciones que hacen honesto al veredicto:
#
#   - En una maquina donde el hook vivo no existe no hay NADA que comparar. Eso
#     se reporta `unknown` y no se cuenta como falla (Core Rule 2): un rojo ahi
#     seria una alarma falsa que entrena a ignorar el test. Lo que si se
#     verifica en ese caso es que la linea base guardada no este vacia.
#
#   - Un cambio de IDENTIDAD del hook (otro sha) no es una falla por si mismo:
#     la Phase 2.1 lo va a cambiar a proposito. Lo que falla es un cambio de
#     COMPORTAMIENTO. Se reporta la diferencia de identidad como nota.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
arnes="$repo/tools/golden-harness.sh"
base="$repo/tests/golden/baseline.txt"
escenarios="$repo/tests/fixtures/escenarios"
if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_golden_baseline: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
# Puede resolver a la fuente del repo si el vivo no esta. La linea base se grabo
# contra el vivo, y la Task 2.1 midio que la fuente es ese mismo archivo byte a
# byte mas el marcador de la linea 2 — asi que comparar contra ella sigue
# afirmando lo mismo. El aviso de cual se uso lo emite el resolvedor.
vivo="$(resolver_hook_bajo_prueba "$repo" "test_golden_baseline")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

fail=0
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# La linea base es el artefacto: si esta vacia o no cubre los escenarios, el
# test podria salir verde comparando nada contra nada.
if [ ! -s "$base" ]; then
  malo "no hay linea base guardada en tests/golden/baseline.txt"
else
  n_base="$(grep -c '^=== escenario ' "$base" 2>/dev/null || echo 0)"
  n_dir="$(find "$escenarios" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l)"
  if [ "$n_base" -lt 1 ]; then
    malo "la linea base no registra ningun escenario"
  elif [ "$n_base" != "$n_dir" ]; then
    malo "la linea base cubre $n_base escenarios y en disco hay $n_dir: esta desactualizada"
  fi
fi

# El hook vivo corre en cada turno; el arnes NUNCA debe escribir ahi. Se mira
# el estado real (solo leer, jamas escribir) para poder decirlo, no para
# suponerlo.
#
# Esta observacion NO decide el veredicto del test: el state real es
# compartido, y una sesion de otro proyecto armando el gate mientras esto corre
# lo cambiaria sin que el arnes tenga nada que ver. Un rojo ahi seria una
# alarma falsa. La prueba dura del aislamiento es hermetica y esta en
# `test_golden_harness.sh` (el arnes no escribe ni al lado del hook que
# ejercita); aca se reporta lo observado y se sigue.
estado_vivo="$(dirname "$vivo")/state"
listar_estado_vivo() { find "$estado_vivo" -type f 2>/dev/null | sort; }
antes_vivo="$(listar_estado_vivo)"

salida="$(bash "$arnes" --hook "$vivo" --scenarios "$escenarios" --baseline "$base" --check 2>&1)"
rc=$?
case "$rc" in
  0) : ;;
  2) echo "$salida"; malo "el arnes no pudo observar (unknown); revisar la salida de arriba" ;;
  *) printf '%s\n' "$salida" | head -60 >&2
     malo "el hook VIVO ya no se comporta como la linea base grabada (exit $rc)" ;;
esac

if [ "$antes_vivo" != "$(listar_estado_vivo)" ]; then
  echo "test_golden_baseline: nota — el state real del hook cambio durante la corrida."
  echo "                      Puede ser otra sesion armando el gate. Si se repite sin"
  echo "                      otra sesion activa, revisar el aislamiento del arnes."
fi

if [ "$fail" -ne 0 ]; then
  echo "test_golden_baseline: FAIL" >&2
  exit 1
fi
echo "test_golden_baseline: OK"
