#!/usr/bin/env bash
# Task 2.1 — la fuente del hook vive en el repo: el archivo VIVO byte a byte,
# mas un marcador de identidad en linea fija.
#
# Por que un marcador y no el hash del archivo entero: el hash cambia con CADA
# edicion legitima, asi que no sirve para responder "esto es nuestro o del
# vendor?". Y esa es exactamente la pregunta que el instalador de la 2.2 tiene
# que contestar antes de sobrescribir nada (tres estados: nuestro / vendor
# conocido / desconocido) y la que quality-kit necesita para saltear el archivo
# en vez de re-parchearlo (2.3). Es la Core Rule 5 del spec.
#
# Como se verifica la equivalencia, y por que en dos mitades:
#
#   1) BYTE A BYTE contra el archivo vivo: quitarle la linea del marcador tiene
#      que devolver el vivo exacto. Es la prueba mas fuerte posible de la
#      primera mitad del enunciado y cuesta un `cmp`. Si pasa, no queda margen
#      para que el comportamiento difiera: son los mismos bytes.
#   2) COMPORTAMIENTO contra la linea base: el marcador SI es una diferencia
#      real, y que un comentario sea inerte es una suposicion razonable — este
#      repo las mide en vez de suponerlas. Una corrida del arnes de la 1.2
#      contra la fuente lo demuestra en todos los escenarios.
#
# La otra mitad de la transitividad (que la linea base siga describiendo al
# VIVO) la cubre `test_golden_baseline.sh`. Entre los dos queda afirmado
# fuente == vivo, que es lo que pide la DoD. Se hace asi, y no corriendo el
# arnes dos veces —una por hook—, porque cada corrida cuesta ~1.6 min en
# Windows y la segunda no agregaria ninguna afirmacion que el `cmp` de 1) no de
# ya, mas fuerte y gratis.
#
# En una maquina sin el hook vivo, la mitad 1) se reporta `unknown` y no cuenta
# como falla (Core Rule 2): un rojo ahi seria una alarma falsa. La mitad 2)
# igual corre, porque la linea base es un artefacto del propio repo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
fuente="$repo/hooks/summonaikit-harness.sh"
arnes="$repo/tools/golden-harness.sh"
base="$repo/tests/golden/baseline.txt"
escenarios="$repo/tests/fixtures/escenarios"
vivo="${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"

# La linea es FIJA para que el instalador (2.2) y el skip de quality-kit (2.3)
# puedan mirarla sin leer el archivo entero ni depender de que nadie edite mas
# abajo. La 1 es del shebang: un marcador antes de el romperia la ejecucion.
MARCADOR_LINEA=2
MARCADOR_PREFIJO='# SAIKIT-CLAUDE-OWNED '
MARCADOR_RE='^# SAIKIT-CLAUDE-OWNED summonaikit-claude [^[:space:]]+$'

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-2-1-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------- 1) la fuente esta en el repo
caso "la fuente del hook existe en hooks/summonaikit-harness.sh"
if [ ! -f "$fuente" ] || [ ! -r "$fuente" ]; then
  malo "no hay fuente legible en $fuente"
  # Sin fuente no hay nada que afirmar: seguir seria comprobar el vacio y los
  # casos de abajo pasarian por no tener contra que fallar.
  echo "test_hook_source: FAIL" >&2
  exit 1
fi

# ---------------------------------------------------------- 2) el marcador
caso "el shebang sigue siendo la primera linea"
primera="$(sed -n '1p' "$fuente")"
[ "$primera" = '#!/usr/bin/env bash' ] \
  || malo "la linea 1 deberia ser el shebang y es: '$primera'"

caso "el marcador esta en la linea $MARCADOR_LINEA y respeta el formato declarado"
linea_marcador="$(sed -n "${MARCADOR_LINEA}p" "$fuente")"
printf '%s\n' "$linea_marcador" | grep -Eq "$MARCADOR_RE" \
  || malo "la linea $MARCADOR_LINEA no es el marcador esperado: '$linea_marcador'"

caso "el marcador es detectable por un grep de UNA linea (lo que hara el instalador)"
grep -q "^$MARCADOR_PREFIJO" "$fuente" \
  || malo "un grep de una sola linea no encuentra el marcador"

# Dos marcadores volverian ambigua la version que declara el archivo, que es
# justo el dato con el que la 2.2 decide si reparar o reemplazar.
caso "el marcador aparece UNA sola vez en todo el archivo"
n_marcador="$(awk -v p="^$MARCADOR_PREFIJO" '$0 ~ p { n++ } END { print n+0 }' "$fuente")"
[ "$n_marcador" = "1" ] || malo "esperaba exactamente 1 marcador, hay $n_marcador"

# ------------------------------------- 3) byte a byte contra el archivo vivo
#
# El archivo vivo tiene DOS estados sanos, y cual corresponde depende de si la
# Task 2.4 ya instalo:
#
#   - todavia el del vendor (sin marcador) => `sed '2d'` de la fuente lo devuelve
#     byte a byte. Es la afirmacion con que la Task 2.1 adopto el archivo.
#   - ya instalado el nuestro (con marcador) => la fuente y el vivo son el MISMO
#     archivo, sin quitarle nada.
#
# Escribirlo con un solo caso era correcto hasta el dia del install, y ese dia se
# puso rojo por haber cumplido su proposito. Lo que NO es sano —y por eso sigue
# siendo un FAIL y no una nota— es un vivo que lleve el marcador y difiera de la
# fuente: ahi el perfil quedo desincronizado y hay que correr el instalador.
if [ ! -r "$vivo" ]; then
  echo "test_hook_source: unknown — el hook vivo no esta en esta maquina ($vivo)."
  echo "                  No se afirma que la fuente lo reproduzca byte a byte:"
  echo "                  no se pudo mirar. El caso de comportamiento sigue corriendo."
elif grep -q "^$MARCADOR_PREFIJO" "$vivo"; then
  # Criterio ANCHO (marcador en cualquier linea), el mismo que usa el skip de
  # quality-kit: si el vivo se declara nuestro de cualquier forma, lo que
  # corresponde exigir es igualdad total, no la resta del marcador.
  caso "el vivo ya es el nuestro (Task 2.4 instalada) => identico a la fuente, sin restar nada"
  if ! cmp -s "$fuente" "$vivo"; then
    malo "el hook vivo se declara nuestro pero NO es la fuente del repo: el perfil quedo desincronizado"
    printf '      vivo:   %s bytes\n' "$(wc -c < "$vivo" | tr -d ' ')" >&2
    printf '      fuente: %s bytes\n' "$(wc -c < "$fuente" | tr -d ' ')" >&2
    diff -u "$vivo" "$fuente" 2>/dev/null | head -n 20 >&2
    printf '      se arregla con: bash tools/install-hook.sh\n' >&2
  fi
else
  caso "quitarle el marcador devuelve el archivo vivo, byte a byte"
  sin_marcador="$tmp/sin-marcador.sh"
  sed "${MARCADOR_LINEA}d" "$fuente" > "$sin_marcador"
  if ! cmp -s "$sin_marcador" "$vivo"; then
    malo "la fuente NO es el archivo vivo mas el marcador"
    printf '      vivo:               %s bytes\n' "$(wc -c < "$vivo" | tr -d ' ')" >&2
    printf '      fuente sin marcador: %s bytes\n' "$(wc -c < "$sin_marcador" | tr -d ' ')" >&2
    diff -u "$vivo" "$sin_marcador" 2>/dev/null | head -n 20 >&2
  fi
fi

# --------------------------- 4) el marcador no cambio el COMPORTAMIENTO
caso "el arnes de la 1.2 da la salida grabada tambien con la fuente del repo"
if [ ! -s "$base" ]; then
  malo "no hay linea base en tests/golden/baseline.txt contra que comparar"
else
  salida="$(bash "$arnes" --hook "$fuente" --scenarios "$escenarios" --baseline "$base" --check 2>&1)"
  rc=$?
  case "$rc" in
    0)
      # Que el arnes AVISE del cambio de identidad no es ruido: confirma que el
      # marcador realmente cambio los bytes y que aun asi el veredicto se dio
      # por comportamiento (decision 2 del arnes). Si no avisara, el caso
      # estaria pasando con un archivo que no tiene marcador.
      printf '%s\n' "$salida" | grep -qi 'identidad' \
        || malo "el arnes deberia avisar que la fuente cambio de identidad y no lo dijo: $salida"
      ;;
    2)
      printf '%s\n' "$salida" | head -n 20 >&2
      malo "el arnes no pudo observar (unknown); revisar la salida de arriba"
      ;;
    *)
      printf '%s\n' "$salida" | head -n 60 >&2
      malo "la fuente del repo NO se comporta como la linea base (exit $rc)"
      ;;
  esac
fi

if [ "$fail" -ne 0 ]; then
  echo "test_hook_source: FAIL" >&2
  exit 1
fi
echo "test_hook_source: OK"
