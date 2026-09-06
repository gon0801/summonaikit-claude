#!/usr/bin/env bash
# tests/test_trail_gate.sh — Stop full-lane exige cita de trail/blast o TRAIL SKIP.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_trail_gate: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_trail_gate")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

if [ -z "${TMPDIR:-}" ] || [ -z "${HOME:-}" ]; then
  _box="$(mktemp -d "${TMPDIR:-/tmp}/saikit-trail-box-XXXXXX")" || exit 1
  mkdir -p "$_box/home" "$_box/tmp"
  export HOME="$_box/home" USERPROFILE="$_box/home" TMPDIR="$_box/tmp"
fi

fail=0
caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; lab_limpiar_estado; limpiar_saikit; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

if ! lab_init "$vivo"; then
  echo "test_trail_gate: FAIL — no se pudo montar el banco de pruebas" >&2
  exit 1
fi
trap 'lab_fin' EXIT

for c in $CASOS_G8; do
  caso "$c"
  "$c"
  fin_caso "$c"
done

if [ "$fail" -ne 0 ]; then
  echo "test_trail_gate: FAIL" >&2
  exit 1
fi
echo "test_trail_gate: OK"
