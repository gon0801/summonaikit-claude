#!/usr/bin/env bash
# Guardia de integridad de filas en Plans.md (revision de la Task 1.5).
#
# Por que existe este test. La fila de la Task 1.5 documentaba un fixture
# cuyo campo de ruta decodificaba con un salto de linea adentro — y la propia
# celda contenia ESE MISMO salto de linea, literal, partiendo la fila en dos
# lineas fisicas de la tabla Markdown (la linea 40 arrancaba `| 1.5 | ...` y
# terminaba a mitad de celda con un backtick abierto; la 41 era la mitad de
# abajo, con las celdas reales `| 1.4 | cc:完了 [a9e9fb0] |`). La Task 1.5
# estaba cerrada desde 2026-08-10, pero cualquier herramienta que lee el
# ledger linea a linea (el contador TODO del banner de sesion, encuestas de
# fase) la reportaba como pendiente: nada validaba la ESTRUCTURA de las filas,
# solo el contenido de los fixtures que describian.
#
# Que valida. Dos firmas, sin exigir numero exacto de celdas (las celdas
# meten `|` legitimos adentro de backticks a proposito):
#   1) toda linea que arranca `| N.M ` (una fila de tarea) tiene que TERMINAR
#      en `|`. Si no, se corto a mitad de celda.
#   2) ninguna linea que NO arranca con `|` puede terminar en `|` y contener
#      un marcador de status (`cc:` / `pm:` / `blocked`) — esa combinacion es
#      la firma de la mitad de ABAJO de una fila partida.
#
# Core Rule 4: solo lectura sobre el arbol del repo real. Los casos que
# ejercitan el detector usan fixtures sinteticos en el sandbox; el ultimo caso
# lee el Plans.md real del repo (solo lectura) porque ese es el guardia que
# esta tarea pide.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# chequear_ledger ARCHIVO
# Imprime una linea por violacion encontrada ("NUMERO: motivo -> texto"), y
# nada si el archivo esta entero. No exige numero exacto de celdas.
chequear_ledger() {
  awk '
    {
      raw = $0
      line = raw
      gsub(/\r$/, "", line)                       # tolera CRLF
      es_fila_tarea = (line ~ /^\| *[0-9]+\.[0-9]+ /)
      arranca_pipe  = (line ~ /^\|/)
      termina_pipe  = (line ~ /\|$/)
      if (es_fila_tarea) {
        if (!termina_pipe) {
          print NR ": fila de tarea no termina en | -> " line
        }
      } else if (!arranca_pipe) {
        if (termina_pipe && line ~ /(cc:|pm:|blocked)/) {
          print NR ": linea sin | inicial, con marcador de status y | final (mitad de una fila partida) -> " line
        }
      }
    }
  ' "$1"
}

# ------------------------------------------------------------- sinteticos
caso "una fila de tarea completa en una sola linea => sin violaciones"
f="$SANDBOX/ok.md"
printf '| 1.1 | contenido con `codigo` y | pipes | adentro de backticks | - | cc:完了 [abcdef0] |\n' > "$f"
out="$(chequear_ledger "$f")"
[ -z "$out" ] || malo "fila completa marcada como violacion: $out"

caso "una fila de tarea partida en dos lineas (el bug real) => se detectan ambas mitades"
f="$SANDBOX/roto.md"
{
  printf '| 1.5 | texto antes del salto - `\n'
  printf '` texto despues del salto | 1.4 | cc:完了 [a9e9fb0] |\n'
} > "$f"
out="$(chequear_ledger "$f")"
printf '%s\n' "$out" | grep -q '^1:' || malo "no senala la primera mitad (linea 1): $out"
printf '%s\n' "$out" | grep -q '^2:' || malo "no senala la segunda mitad (linea 2): $out"
n_viol="$(printf '%s\n' "$out" | grep -c .)"
[ "$n_viol" = 2 ] || malo "esperaba exactamente 2 violaciones, hubo $n_viol: $out"

caso "la misma fila ya arreglada (una sola linea) => sin violaciones"
f="$SANDBOX/arreglado.md"
printf '| 1.5 | texto antes del salto - `\\n` texto despues del salto | 1.4 | cc:完了 [a9e9fb0] |\n' > "$f"
out="$(chequear_ledger "$f")"
[ -z "$out" ] || malo "fila ya arreglada sigue marcada como violacion: $out"

caso "encabezado y separador de tabla no son filas de tarea => sin violaciones"
f="$SANDBOX/header.md"
{
  printf '| Task | Contenido | DoD | Depends | Status |\n'
  printf '|------|------|-----|---------|--------|\n'
} > "$f"
out="$(chequear_ledger "$f")"
[ -z "$out" ] || malo "encabezado/separador marcados como violacion: $out"

caso "archivo sin ninguna fila de tarea => sin violaciones (no es lo mismo que cobertura cero)"
f="$SANDBOX/vacio.md"
printf '# Solo un titulo\n\nProsa que no es tabla.\n' > "$f"
out="$(chequear_ledger "$f")"
[ -z "$out" ] || malo "archivo sin filas marcado como violacion: $out"

# ------------------------------------------------------------- el ledger real
caso "el Plans.md real del repo no tiene ninguna fila de tarea partida"
unknown=0
if [ -f "$repo/Plans.md" ]; then
  out="$(chequear_ledger "$repo/Plans.md")"
  if [ -n "$out" ]; then
    while IFS= read -r l; do malo "Plans.md:$l"; done <<< "$out"
  fi
else
  echo "  UNKNOWN: no existe $repo/Plans.md, no se pudo mirar" >&2
  unknown=1
fi

if [ "$fail" -ne 0 ]; then
  echo "test_plans_ledger: FAIL" >&2
  exit 1
fi
# Un unknown NO es un OK — la leccion de la PROPIA Task 1.5, reproducida en su
# primera version de esta guardia (la atrapo el verifier de la revision): sin
# Plans.md que mirar, esto salia 0 y run.sh lo publicaba como PASS. Exit 3 es
# el codigo que tests/run.sh cuenta aparte como "no se pudo verificar"; un
# fallo real (arriba) sigue mandando sobre un unknown.
if [ "$unknown" -ne 0 ]; then
  echo "test_plans_ledger: UNKNOWN" >&2
  exit 3
fi
echo "test_plans_ledger: OK"
