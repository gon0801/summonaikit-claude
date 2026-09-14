#!/usr/bin/env bash
# 21.5 — Preflight canónico del recibo (batería dedicada).
#
# Corre el corpus común G9 (tests/lib/preflight_cases.sh): mismo veredicto
# y misma causa entre preflight y Stop, dinámicos nombrados, sin efectos,
# sin gramática paralela, divergencia roja. La misma lista corre en verde
# dentro de test_gate_behavior.sh (G9) y contra hook mutado en
# test_gate_mutations.sh; este archivo es la evidencia etiquetada 21.5.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"
. "$here/lib/preflight_cases.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_preflight_21_5: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_preflight_21_5")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

HOOK_BAJO_PRUEBA="$vivo"
if ! lab_init "$vivo"; then
  echo "test_preflight_21_5: FAIL — no se pudo montar el banco de pruebas" >&2
  exit 1
fi
trap 'lab_fin' EXIT

fail=0
for caso in $CASOS_G9; do
  if correr_caso "$caso"; then
    printf '    ok: %s\n' "$caso"
  else
    printf '    ROJO: %s\n' "$caso" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "test_preflight_21_5: FAIL" >&2
  exit 1
fi
echo "test_preflight_21_5: OK"
