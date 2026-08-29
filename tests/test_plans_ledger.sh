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
# Que valida. Tres firmas:
#   1) toda linea que arranca `| N.M ` (una fila de tarea) tiene que TERMINAR
#      en `|`. Si no, se corto a mitad de celda.
#   2) ninguna linea que NO arranca con `|` puede terminar en `|` y contener
#      un marcador de status (`cc:` / `pm:` / `blocked`) — esa combinacion es
#      la firma de la mitad de ABAJO de una fila partida.
#   3) toda fila de tarea tiene EXACTAMENTE 5 celdas (6 separadores), contando
#      solo los `|` sin escapar.
#
# La firma 3 se agrego el 2026-08-29 (CodeRabbit, PR #104) y CORRIGE una
# premisa falsa que este mismo archivo afirmaba: decia que las celdas "meten
# `|` legitimos adentro de backticks a proposito" y por eso no exigia numero
# de celdas. No son legitimos. El parser de tablas de GFM parte la fila por
# `|` ANTES de mirar los backticks: un `|` sin escapar adentro de un code span
# igual abre una celda nueva. Medido en el ledger: la fila 17.3 renderizaba
# con 10 columnas donde debia tener 5, y parte de su DoD caia en la celda
# equivocada — el ledger se leia mal sin que nada lo dijera. La forma correcta
# adentro de una celda es `\|`, que GFM resuelve a un `|` literal.
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
# nada si el archivo esta entero. Firmas 1 y 2 (filas partidas); el numero de
# celdas lo mira `chequear_columnas`, aparte, porque son fallas distintas: una
# rompe el archivo, la otra lo deja valido pero renderizando mal.
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

# chequear_columnas ARCHIVO
# Firma 3: toda fila de tarea tiene exactamente 5 celdas. Se cuentan los `|`
# SIN escapar — `\|` es la forma correcta de meter un pipe literal adentro de
# una celda y no abre columna. Imprime una linea por fila mal formada.
#
# Solo mira filas de tarea (`| N.M `): el encabezado y el separador de la
# tabla tienen su propia forma, y la prosa del archivo no es tabla.
chequear_columnas() {
  awk '
    {
      line = $0
      gsub(/\r$/, "", line)                       # tolera CRLF
      if (line !~ /^\| *[0-9]+\.[0-9]+ /) next
      sin_escapar = line
      gsub(/\\\|/, "", sin_escapar)               # los `\|` no abren columna
      n = gsub(/\|/, "", sin_escapar)
      if (n != 6) {
        print NR ": la fila tiene " (n - 1) " celdas (esperaba 5); hay un | sin escapar adentro de una celda -> " substr(line, 1, 120)
      }
    }
  ' "$1"
}

# ------------------------------------------------------------- sinteticos
caso "una fila de tarea completa en una sola linea => sin violaciones"
f="$SANDBOX/ok.md"
# Los pipes de adentro de la celda van escapados (`\|`), que es la forma que
# GFM resuelve a un `|` literal. Antes esta fixture los ponia pelados "adentro
# de backticks" como si fuera legitimo; no lo es (ver la cabecera, firma 3).
printf '| 1.1 | contenido con `a\\|b\\|c` adentro | - | - | cc:完了 [abcdef0] |\n' > "$f"
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

# --------------------------------------------- firma 3: numero de celdas
caso "fila de 5 celdas con pipes escapados adentro => sin violaciones"
f="$SANDBOX/col_ok.md"
printf '| 2.1 | columnas `a\\|b\\|c` en el texto | `x\\|y` en el DoD | - | cc:TODO |\n' > "$f"
out="$(chequear_columnas "$f")"
[ -z "$out" ] || malo "la fila bien formada se marco como violacion: $out"

caso "fila con un | sin escapar adentro de un code span => se detecta (el bug de la 17.3)"
f="$SANDBOX/col_roto.md"
printf '| 2.2 | columnas `cuando|etapa|decision` en el texto | DoD | - | cc:TODO |\n' > "$f"
out="$(chequear_columnas "$f")"
[ -n "$out" ] || malo "una fila con pipes pelados adentro de backticks paso como buena"
printf '%s\n' "$out" | grep -q '^1:' || malo "no senala la linea 1: $out"
printf '%s\n' "$out" | grep -q '7 celdas' || malo "no dice cuantas celdas quedaron (esperaba 7): $out"

caso "encabezado, separador y prosa no son filas de tarea => sin violaciones de columnas"
f="$SANDBOX/col_header.md"
{
  printf '| Task | Contenido | DoD | Depends | Status |\n'
  printf '|------|------|-----|---------|--------|\n'
  printf 'Prosa con un | suelto que no es tabla.\n'
} > "$f"
out="$(chequear_columnas "$f")"
[ -z "$out" ] || malo "encabezado/separador/prosa marcados como violacion de columnas: $out"

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
  caso "el Plans.md real del repo: toda fila de tarea tiene 5 celdas"
  out="$(chequear_columnas "$repo/Plans.md")"
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
