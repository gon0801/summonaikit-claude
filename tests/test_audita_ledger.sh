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
# HERMETICO a proposito: el repo y el ledger son sinteticos, armados en el
# sandbox. La primera version cruzaba contra el `origin/master` del repo real y
# en CI salia `unknown` en cada corrida — el checkout de Actions es shallow. Un
# test permanentemente unknown no protege nada y entrena a ignorar el contador
# de unknowns, que es el mismo defecto que el auditor existe para evitar.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
auditor="$(cd "$here/.." && pwd)/tools/audita-ledger.sh"

if [ ! -r "$auditor" ]; then
  echo "test_audita_ledger: unknown — no existe $auditor" >&2
  exit 3
fi
command -v git >/dev/null 2>&1 || { echo "test_audita_ledger: unknown — no hay git" >&2; exit 3; }

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/saikit-audit-XXXXXX")" || exit 1
trap 'rm -rf "$sandbox"' EXIT

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# --------------------------------------------------- repo sintetico
# Dos tasks "mergeadas" (16.3 sola, y 16.4/16.6 en un mismo alcance con coma,
# que es la forma real que uso el PR #105) y ninguna otra. `origin/master` se
# planta como ref para ejercitar el camino por defecto del auditor.
r="$sandbox/repo"
mkdir -p "$r" || exit 1
git -c init.defaultBranch=master init -q "$r" || { echo "test_audita_ledger: unknown — git init fallo" >&2; exit 3; }
gitr() { git -C "$r" -c user.email='t@example.invalid' -c user.name='t' "$@"; }
gitr commit -q --allow-empty -m 'docs(16.3): principios por rol en los cuatro perfiles' || exit 1
gitr commit -q --allow-empty -m 'feat(16.4,16.6): menu de recetas por manifiesto y alias' || exit 1
gitr commit -q --allow-empty -m 'chore: un commit sin alcance de task' || exit 1
gitr update-ref refs/remotes/origin/master HEAD || exit 1

correr() { SAIKIT_LEDGER="$1" bash "$auditor" "$r" 2>&1; }

encabezado() {
  printf '| Task | Contenido | DoD | Depends | Status |\n'
  printf '|------|------|-----|---------|--------|\n'
}

# --------------------------------------------------- casos
caso "fila en cc:TODO con trabajo ya mergeado => se detecta y se nombra"
f="$sandbox/abierta.md"
{ encabezado; printf '| 16.3 | contenido | DoD | - | cc:TODO |\n'; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' || malo "no reporto la fila abierta: $out"
printf '%s' "$out" | grep -q 'fila 16.3' || malo "no nombra la fila 16.3: $out"

caso "la MISMA fila cerrada, cuyo cierre MENCIONA cc:TODO en prosa => no se reporta"
# Los dos falsos positivos juntos: la mencion esta en la linea Y dentro de la
# celda de estado, que es donde va el texto del cierre.
f="$sandbox/cerrada.md"
{ encabezado
  printf '| 16.3 | contenido | DoD | - | cc:完了 [PR #100] — la fila decia `cc:TODO` con el trabajo ya mergeado |\n'
} > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "reporto como abierta una fila cerrada que menciona cc:TODO en su prosa: $out"
printf '%s' "$out" | grep -q 'AUDITORIA DEL LEDGER: OK' || malo "no dijo OK sobre un ledger correcto: $out"

caso "alcance con coma (feat(16.4,16.6)) => las DOS filas cuentan como mergeadas"
f="$sandbox/coma.md"
{ encabezado
  printf '| 16.4 | contenido | DoD | - | cc:TODO |\n'
  printf '| 16.6 | contenido | DoD | - | cc:TODO |\n'
} > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'fila 16.4' || malo "no vio la 16.4 del alcance con coma: $out"
printf '%s' "$out" | grep -q 'fila 16.6' || malo "no vio la 16.6 del alcance con coma: $out"

caso "fila en cc:TODO SIN trabajo mergeado => no se reporta (no inventa hallazgos)"
f="$sandbox/pendiente.md"
{ encabezado; printf '| 99.9 | una task que nadie empezo | DoD | - | cc:TODO |\n'; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "invento un hallazgo sobre una task sin commits: $out"
printf '%s' "$out" | grep -q 'AUDITORIA DEL LEDGER: OK' || malo "no dijo OK: $out"

caso "celda con pipes escapados adentro => el estado se lee igual"
f="$sandbox/escapes.md"
{ encabezado; printf '| 16.3 | columnas `a\\|b\\|c` | DoD con `x\\|y` | - | cc:TODO |\n'; } > "$f"
out="$(correr "$f")"
printf '%s' "$out" | grep -q 'fila 16.3' || malo "los pipes escapados le tapan el estado: $out"

caso "sin referencia con la cual comparar => unknown (exit 3), no un OK"
f="$sandbox/abierta.md"
out="$(SAIKIT_LEDGER="$f" SAIKIT_LEDGER_REF='saikit/no-existe-esta-ref' bash "$auditor" "$r" 2>&1)"
rc=$?
[ "$rc" = 3 ] || malo "esperaba exit 3 sin referencia, dio $rc"
printf '%s' "$out" | grep -q 'unknown' || malo "no dijo unknown: $out"
printf '%s' "$out" | grep -q 'LEDGER DESACTUALIZADO' && malo "afirmo un hallazgo sin poder mirar: $out"

caso "ledger ilegible => unknown (exit 3), no un OK"
SAIKIT_LEDGER="$sandbox/no-existe.md" bash "$auditor" "$r" >/dev/null 2>&1
rc=$?
[ "$rc" = 3 ] || malo "esperaba exit 3 con un ledger ilegible, dio $rc"

if [ "$fail" -ne 0 ]; then
  echo "test_audita_ledger: FAIL" >&2
  exit 1
fi
echo "test_audita_ledger: OK"
