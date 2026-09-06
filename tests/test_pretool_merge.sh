#!/usr/bin/env bash
# 18.11 / D24 — driver acotado del guardia PreToolUse (merge a pelo).
# Rojo/verde de esta fila: NO corre test_gate_behavior entero.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_pretool_merge: unknown — falta tests/lib/hook_bajo_prueba.sh" >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_pretool_merge")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

fail=0

# Pin de produccion: tools/MANIFEST.sha256 tiene que coincidir con el script.
# Un pin viejo niega el hatch canonico (falso positivo = HIGH).
repo="$(cd "$here/.." && pwd)"
pin="$repo/tools/MANIFEST.sha256"
script="$repo/tools/saikit-merge.sh"
if [ ! -f "$pin" ] || [ ! -f "$script" ]; then
  printf '    FAIL: falta tools/MANIFEST.sha256 o tools/saikit-merge.sh (pin de hatch)\n' >&2
  fail=1
else
  real="$(sha256sum "$script" | cut -c1-64)"
  esperado="$(awk -F '\t' '/^#/ {next} $2=="saikit-merge.sh" {print $1; exit}' "$pin")"
  if [ "$real" != "$esperado" ]; then
    printf '    FAIL: pin de saikit-merge.sh desactualizado (real=%s pin=%s)\n' "$real" "$esperado" >&2
    fail=1
  fi
fi

HOOK_BAJO_PRUEBA="$vivo"
if ! lab_init; then
  echo "test_pretool_merge: FAIL — no se pudo montar el banco de pruebas" >&2
  exit 1
fi
trap 'lab_fin' EXIT

for caso in $CASOS_G7; do
  if correr_caso "$caso"; then
    printf '    ok: %s\n' "$caso"
  else
    printf '    ROJO: %s\n' "$caso" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "test_pretool_merge: FAIL" >&2
  exit 1
fi
echo "test_pretool_merge: OK"
