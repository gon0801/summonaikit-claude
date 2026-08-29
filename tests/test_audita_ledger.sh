#!/usr/bin/env bash
# Guardia de tools/audita-ledger.sh — el auditor que busca filas en `cc:TODO`
# cuyo trabajo ya esta mergeado.
#
# Por que existe. El auditor nacio porque la fila 16.3 estuvo mergeada y en
# `cc:TODO` durante un dia entero. Al escribirlo se comio DOS falsos positivos
# seguidos, los dos sobre esa misma fila una vez cerrada:
#   1) miraba la linea entera, y el texto de cierre EXPLICA el incidente
#      mencionando `cc:TODO` en prosa;
#   2) miraba la celda de estado completa, y esa mencion vive dentro de la
#      propia celda (el cierre va en la misma celda que el marcador).
# La convencion real del ledger es que la celda de estado ARRANCA con el
# marcador. Un auditor que confunde una mencion con un estado reporta filas
# cerradas como abiertas, y un candado que grita sin razon se apaga: por eso
# los dos falsos positivos tienen caso propio aca.
#
# Core Rule 4: los ledgers son fixtures sinteticos en el sandbox. Los COMMITS
# salen del repo real (solo lectura), porque lo que se prueba es el cruce entre
# un ledger y un historial de verdad — la task 16.3 esta mergeada en
# `origin/master` y sirve de ancla observable.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
auditor="$repo/tools/audita-ledger.sh"

if [ ! -r "$auditor" ]; then
  echo "test_audita_ledger: unknown — no existe $auditor" >&2
  exit 3
fi
# El ancla: una task con commits mergeados en origin/master. Sin origin/master
# (clon sin remoto, checkout shallow) no se puede afirmar nada.
if [ "$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] \
   || ! git -C "$repo" rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
  echo "test_audita_ledger: unknown — sin origin/master legible (o clon shallow); no se pudo mirar" >&2
  exit 3
fi
ancla=16.3
if ! git -C "$repo" log --format='%s' origin/master | grep -qE "^[a-z]+\([^)]*$ancla"; then
  echo "test_audita_ledger: unknown — no hay commits con alcance ($ancla) en origin/master; el ancla ya no sirve" >&2
  exit 3
fi

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/saikit-audit-XXXXXX")" || exit 1
trap 'rm -rf "$sandbox"' EXIT

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

correr() { SAIKIT_LEDGER="$1" bash "$auditor" "$repo" 2>&1; }

encabezado() {
  printf '| Task | Contenido | DoD | Depends | Status |\n'
  printf '|------|------|-----|---------|--------|\n'
}

caso "fila en cc:TODO con trabajo ya mergeado => se detecta y se nombra"
f="$sandbox/abierta.md"
{ encabezado; printf '| %s | contenido | DoD | - | cc:TODO |\n' "$ancla"; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' || malo "no reporto la fila abierta: $out"
printf '%s' "$out" | grep -q "fila $ancla" || malo "no nombra la fila $ancla: $out"

caso "la MISMA fila cerrada, cuyo cierre MENCIONA cc:TODO en prosa => no se reporta"
# Falso positivo 1 y 2 juntos: la mencion esta en la linea Y dentro de la celda
# de estado, que es donde va el texto del cierre.
f="$sandbox/cerrada.md"
{ encabezado
  printf '| %s | contenido | DoD | - | cc:完了 [PR #100] — la fila decia `cc:TODO` con el trabajo ya mergeado |\n' "$ancla"
} > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "reporto como abierta una fila cerrada que menciona cc:TODO en su prosa: $out"
printf '%s' "$out" | grep -q 'AUDITORIA DEL LEDGER: OK' || malo "no dijo OK sobre un ledger correcto: $out"

caso "fila en cc:TODO SIN trabajo mergeado => no se reporta (no inventa hallazgos)"
f="$sandbox/pendiente.md"
{ encabezado; printf '| 99.9 | una task que no existe | DoD | - | cc:TODO |\n'; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "invento un hallazgo sobre una task sin commits: $out"

caso "celda con pipes escapados adentro => el estado se lee igual"
f="$sandbox/escapes.md"
{ encabezado; printf '| %s | columnas `a\\|b\\|c` | DoD con `x\\|y` | - | cc:TODO |\n' "$ancla"; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q "fila $ancla" || malo "los pipes escapados le tapan el estado: $out"

caso "sin referencia con la cual comparar => unknown (exit 3), no un OK"
f="$sandbox/abierta.md"
SAIKIT_LEDGER="$f" SAIKIT_LEDGER_REF='saikit/no-existe-esta-ref' bash "$auditor" "$repo" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] || malo "esperaba exit 3 sin referencia, dio $rc"
out="$(SAIKIT_LEDGER="$f" SAIKIT_LEDGER_REF='saikit/no-existe-esta-ref' bash "$auditor" "$repo" 2>&1)"
printf '%s' "$out" | grep -q 'unknown' || malo "no dijo unknown: $out"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "afirmo un hallazgo sin poder mirar: $out"

caso "ledger ilegible => unknown (exit 3), no un OK"
SAIKIT_LEDGER="$sandbox/no-existe.md" bash "$auditor" "$repo" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] || malo "esperaba exit 3 con un ledger ilegible, dio $rc"

if [ "$fail" -ne 0 ]; then
  echo "test_audita_ledger: FAIL" >&2
  exit 1
fi
echo "test_audita_ledger: OK"
