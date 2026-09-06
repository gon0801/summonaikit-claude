#!/usr/bin/env bash
: <<'SAIKIT_MARCA'
---
saikit_owned: summonaikit-claude
---
SAIKIT_MARCA
# saikit-blast.sh — escribe el artefacto del blast radius (Task 17.4 / D13).
#
# QUE HACE. Escribe `.saikit/findings/blast-<task>.json` con EL hecho unico por
# el que el cambio es seguro. Es el mecanismo del verifier y el VALIDADOR que la
# DoD ejercita.
#
# Uso:
#   bash tools/saikit-blast.sh --write --task <id> --hecho <texto> \
#        --comando <cmd> --salida <texto> --nivel <1-5>
#   bash tools/saikit-blast.sh --help
#
# Opciones:
#   --write         escribe el artefacto (unica operacion).
#   --task <id>     cual archivo (el nombre es <dir>/blast-<task>.json).
#                   Obligatorio.
#   --hecho <texto> el hecho unico que hace seguro el cambio. Obligatorio.
#   --comando <cmd> comando que prueba el hecho. Obligatorio si nivel >= 4
#                   (un hecho serio sin forma de correrlo es opinion).
#   --salida <texto> salida del comando (recortada + redactada). Opcional; si
#                   viene, jamas se escribe cruda.
#   --nivel <1-5>   nivel del hecho (1 afirmado .. 5 corrido en la superficie
#                   real). Obligatorio.
#   --dir <path>    donde se escribe; default `.saikit/findings` bajo la raiz
#                   del repo (git rev-parse --show-toplevel, o pwd si no).
#
# REDACCION. Todos los campos de texto (hecho, comando, salida) pasan por
# `redactar` de tools/lib/redactar.sh (la FUENTE UNICA). La salida se aplana
# PRIMERO (eliminando CR/LF, no insertando espacios: un key=value partido por un
# salto debe quedar contiguo para que redactar se lo coma entero), luego se
# REDACT, y SOLO al final se recorta a RECORTE caracteres (y se re-redacta el
# string ya recortado): redactar antes de recortar evita que el corte deje un
# fragmento de secreto, y la re-redaccion restaura un marcador que el corte
# pudo partir. El valor que NUNCA llega al archivo es la salida cruda.
#
# POSTURA DE FALLA: exit 2 ante cualquier entrada invalida, sin escribir un
# byte del artefacto; exit 0 + confirmacion si la escritura va en limpio. Una
# escritura fallida (disco lleno, ruta que es un directorio) es exit 2, no un
# aviso en stderr.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/lib/redactar.sh"
if [ ! -r "$lib" ]; then
  printf 'saikit-blast: no se encontro la lib de redaccion: %s\n' "$lib" >&2
  exit 2
fi
. "$lib"

RECORTE=1000

TASK=""; HECHO=""; COMANDO=""; SALIDA=""; NIVEL=""; DIR=""; MODO=""

uso() {
  sed -n '/^# saikit-blast.sh/,/^set -u/{ /^#/p; }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --write)          MODO="write"; shift ;;
    --task|--hecho|--comando|--salida|--nivel|--dir)
      # El bug de la Task 0.4, pago por este repo: `shift 2` con un solo
      # argumento no consume nada y el while gira para siempre. Un flag con
      # valor EXIGE el valor.
      if [ $# -lt 2 ]; then
        printf 'saikit-blast: %s exige un valor\n' "$1" >&2; exit 2
      fi
      # kimi #11: `--etapa --decision` asignaba "--decision" como VALOR. Un
      # flag como valor es un tipeo; el "valor" no se repite crudo (CodeRabbit,
      # PR #130) porque podria ser un secreto.
      case "$2" in --*)
        printf 'saikit-blast: %s recibio otro flag como valor (empieza con --)\n' "$1" >&2; exit 2 ;;
      esac
      case "$1" in
        --task)    TASK="$2" ;;
        --hecho)   HECHO="$2" ;;
        --comando) COMANDO="$2" ;;
        --salida)  SALIDA="$2" ;;
        --nivel)   NIVEL="$2" ;;
        --dir)     DIR="$2" ;;
      esac
      shift 2 ;;
    -h|--help)   uso; exit 0 ;;
    *)           printf 'saikit-blast: opcion desconocida: %s\n' "$1" >&2; uso >&2; exit 2 ;;
  esac
done

if [ -z "$MODO" ]; then
  printf 'saikit-blast: falta --write\n' >&2
  uso >&2
  exit 2
fi
if [ -z "$TASK" ]; then
  printf 'saikit-blast: falta --task <id>\n' >&2
  exit 2
fi
if [ -z "$NIVEL" ]; then
  printf 'saikit-blast: falta --nivel <1-5>\n' >&2
  exit 2
fi

# --task es un NOMBRE de archivo con contrato: mismo criterio que
# saikit-decision.sh — charset seguro y acotado, sin rutas, y sin forma de
# secreto (el nombre acaba en .saikit/findings/). El patron `..` es
# deliberadamente conservador: tambien rechaza `release..2`. Los mensajes NO
# repiten el valor crudo: si el valor ES un secreto, el error no es la via por
# la que se imprime.
case "$TASK" in
  */*|*\\*|..*|*..*|.*)
    printf 'saikit-blast: --task no admite rutas ni nombres ocultos (/, \\, .. o punto inicial)\n' >&2
    exit 2 ;;
  ghp_*|github_pat_*|gho_*|sk-*|AKIA*|xoxb-*|xoxp-*)
    printf 'saikit-blast: --task tiene forma de secreto; el nombre se commitea y no se redacta\n' >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    printf 'saikit-blast: --task solo admite [A-Za-z0-9._-]\n' >&2
    exit 2 ;;
esac

# Nivel entero 1-5, forma canonica de UN digito. `04`/`05` con cero inicial se
# rechazan: un numero JSON no admite cero inicial y `"nivel":04` es invalido
# (hallazgo del adversary). El mensaje no repite el valor: si el valor fuera un
# secreto pegado por error, el error no puede ser la via por la que se imprime.
case "$NIVEL" in
  [1-5]) ;;
  *) printf 'saikit-blast: --nivel debe ser un entero de 1 a 5\n' >&2; exit 2 ;;
esac

# El hecho: obligatorio y no vacio (se recortan los espacios alrededor).
HECHO_T="$(printf '%s' "$HECHO" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ -z "$HECHO_T" ]; then
  printf 'saikit-blast: falta --hecho <texto> (es el hecho que hace seguro el cambio)\n' >&2
  exit 2
fi

# El comando, recortado de espacios: un `--comando "   "` es tan vacio como un
# `--comando ""` y dejaria pasar un "corrido" sin comando util (hallazgo
# repetido del cross-review codex+glm). Para nivel >= 4 tiene que ser algo.
COMANDO_T="$(printf '%s' "$COMANDO" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
if [ "$NIVEL" -ge 4 ] && [ -z "$COMANDO_T" ]; then
  printf 'saikit-blast: nivel >= 4 exige comando (un hecho serio sin forma de correrlo es opinion, no hecho)\n' >&2
  exit 2
fi

if [ -z "$DIR" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  DIR="$repo_root/.saikit/findings"
fi

# ------------------------------------------------------------- procesamiento
# La salida de un comando es multilinea, pero JSON la lleva como UNA linea y
# `redactar` procesa por linea. Se aplana ELIMINANDO los saltos de linea (no
# insertando un espacio): un key=value partido por un salto queda CONTIGUO y
# redactar se lo come entero; insertar un espacio en el salto dejaria la
# continuacion del valor en claro (hallazgo del adversary, MEDIO).
#
# El ORDEN es aplana -> REDACT -> recorta. Redactar ANTES de recortar es lo
# que cierra los dos hallazgos HIGH del adversary: un corte en la mitad de un
# secreto dejaba un fragmento en claro (un `://user:pass@` con el `@` pasado el
# corte — fuga silenciosa para el escaneo) o un prefijo de AWS que dispara el
# escaneo (GATE falso). Redactado el valor entero, el recorte ya no puede
# dejar un trozo de secreto. Hecho y comando se aplanan y se redactan tambien:
# defensa en profundidad — cualquiera de los tres puede llevar un secreto.
flat() { printf '%s' "$1" | tr -d '\r\n'; }

SALIDA_F="$(flat "$SALIDA")"
HECHO_F="$(flat "$HECHO_T")"
COMANDO_F="$(flat "$COMANDO_T")"

SALIDA_R="$(redactar "$SALIDA_F")"
HECHO_R="$(redactar "$HECHO_F")"
COMANDO_R="$(redactar "$COMANDO_F")"

if [ "${#SALIDA_R}" -gt "$RECORTE" ]; then
  SALIDA_R="${SALIDA_R:0:$RECORTE} [recortada]"
  # Re-redacta el string ya recortado: el corte pudo partir un marcador
  # `token=[REDACTED]` en `token=[R`, que el strip del escaneo de la sesion NO
  # descuenta y el regex `=[^[:space:]]` volveria a disparar (GATE falso). Al
  # re-redactar, el `token=[R` vuelve a `token=[REDACTED]` y el escaneo queda
  # descontado; un marcador PELADO (sin `token=`) cortado es estetico, no
  # dispara nada.
  SALIDA_R="$(redactar "$SALIDA_R")"
fi

# Escapado JSON minimo (backslash, comilla y tab) sobre cada valor, y limpieza
# de los demas C0 de control (que no son un caracter valido dentro de un string
# JSON y romperian el "siempre JSON valido"). El recorte suele dejar la salida
# sin salto de linea, pero un tab u otro control que venga en el comando se
# escapa a \t o se quita.
json_escape() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    -e 's/\t/\\t/g' -e 's/[[:cntrl:]]//g'
}

HECHO_J="$(json_escape "$HECHO_R")"
COMANDO_J="$(json_escape "$COMANDO_R")"
SALIDA_J="$(json_escape "$SALIDA_R")"

json="{\"hecho\":\"${HECHO_J}\",\"comando\":\"${COMANDO_J}\",\"salida\":\"${SALIDA_J}\",\"nivel\":${NIVEL}}"

archivo="$DIR/blast-$TASK.json"
mkdir -p "$DIR" 2>/dev/null || { printf 'saikit-blast: no se pudo crear %s\n' "$DIR" >&2; exit 2; }
# Escritura "atomico-ish": a un temporal y luego mv, para no dejar un JSON a
# medio escribir si el proceso muere a la mitad. Ambas escrituras se verifican;
# una escritura fallida es exit 2, no un "registrado".
tmpf="$archivo.tmp.$$"
if ! printf '%s\n' "$json" > "$tmpf"; then
  printf 'saikit-blast: no se pudo escribir %s\n' "$archivo" >&2
  rm -f "$tmpf" 2>/dev/null || true
  exit 2
fi
if ! mv "$tmpf" "$archivo"; then
  printf 'saikit-blast: no se pudo escribir %s\n' "$archivo" >&2
  rm -f "$tmpf" 2>/dev/null || true
  exit 2
fi

printf 'blast: %s nivel %s\n' "$TASK" "$NIVEL"
exit 0
