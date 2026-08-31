#!/usr/bin/env bash
# saikit-decision.sh — append seguro a una fila del rastro de decisiones
# (Task 17.3 / D12).
#
# QUE HACE. Agrega UNA fila a `.saikit/decisiones/<task>.tsv` con el contrato de
# columnas del plan:
#
#   cuando|etapa|decision|por_que|evidencia|resultado
#
# El rastro es el registro de que cada task dejo decisiones legibles en espanol,
# para que el lead las audite sin abrir el codigo. Esta herramienta es la unica
# via de escritura: una fila se agrega COMPLETA, bajo candado, y con los campos
# de texo redactados — un token pegado en una explicacion sale `[REDACTED]`.
#
# Uso:
#   bash tools/saikit-decision.sh --append --task <id> --etapa <etapa> \
#        --decision <texto> --por-que <texto> --evidencia <texto> \
#        --resultado <descriptor>
#   bash tools/saikit-decision.sh --check  --task <id>
#   bash tools/saikit-decision.sh --help
#
# Opciones:
#   --append        agrega una fila (es la operacion de escritura).
#   --check         valida SOLO el archivo existente; no escribe nada.
#   --task <id>     cual archivo (el nombre es <dir>/<task>.tsv). Obligatorio.
#   --etapa <v>     columna etapa (estructura, NO se redacta).
#   --decision <v>  columna decision (texto libre; se redacta).
#   --por-que <v>   columna por_que (texto libre; se redacta).
#   --evidencia <v> columna evidencia (texto libre; se redacta).
#   --resultado <v> "ok" si no hay seguimiento, o un descriptor corto. NO se
#                   redacta: es estructural.
#   --cuando <ts>   sello de tiempo; default `date -u +%Y-%m-%dT%H:%M:%SZ`.
#   --dir <path>    donde viven los tsv; default `.saikit/decisiones` bajo la
#                   raiz del repo (git rev-parse --show-toplevel, o pwd si no).
#
# REGLAS DE VALIDACION (REPORT, NO REPARAR). Esta herramienta JAMAS "arregla" un
# tsv mal escrito: si el archivo existe y esta mal, lo dice y sale 2 sin tocar
# un byte. Asi un rastro manoseado a mano no se silicona en silencio.
#   - El encabezado (primera linea no comentario, no vacia) tiene que ser
#     EXACTAMENTE `cuando|etapa|decision|por_que|evidencia|resultado`.
#   - Cada linea de datos (no comentario, no vacia, tras el encabezado) tiene
#     que tener EXACTAMENTE 6 campos separados por `|`.
#   - Ningun valor de `--decision/--por-que/--evidencia/--etapa/--resultado`
#     puede contener `|` literal (romperia el conteo de campos).
#   - Las lineas que empiezan con `#` y las vacias se permiten como marcadores
#     de seccion (p.ej. `# --- Atencion ---`) y se saltean en la validacion.
#
# CANDADO. El append se serializa con un candado portable via `mkdir` (atomico
# en POSIX y MSYS): `$dir/.saikit-decision-<task>.lock`. Dos escrituras
# concurrentes no parten una fila: la segunda espera (o limpia un candado
# huerfano cuyo pid no esta vivo) hasta adquirirlo. Tras ~3 s reporta
# "no se pudo adquirir el candado" y sale 3. Un trap libera el candado al
# salir, para que un exit (aun por error) no lo deje plantado.
#
# POSTURA DE FALLA: report y exit 2 ante un tsv malformado; exit 3 si el
# candado no se adquiere. La escritura de una fila SIEMPRE es una sola linea
# completa; la creacion del archivo (con encabezado) ocurre bajo el mismo
# candado.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/lib/redactar.sh"
if [ ! -r "$lib" ]; then
  printf 'saikit-decision: no se encontro la lib de redaccion: %s\n' "$lib" >&2
  exit 2
fi
. "$lib"

HEADER='cuando|etapa|decision|por_que|evidencia|resultado'

TASK=""; ETAPA=""; DECISION=""; POR_QUE=""; EVIDENCIA=""; RESULTADO=""
CUANDO=""; DIR=""; MODO=""; candado_propio=0

uso() {
  sed -n '2,80p' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --append)    MODO="append"; shift ;;
    --check)     MODO="check"; shift ;;
    --task)      TASK="${2:-}"; shift 2 ;;
    --etapa)     ETAPA="${2:-}"; shift 2 ;;
    --decision)  DECISION="${2:-}"; shift 2 ;;
    --por-que)   POR_QUE="${2:-}"; shift 2 ;;
    --evidencia) EVIDENCIA="${2:-}"; shift 2 ;;
    --resultado) RESULTADO="${2:-}"; shift 2 ;;
    --cuando)    CUANDO="${2:-}"; shift 2 ;;
    --dir)       DIR="${2:-}"; shift 2 ;;
    -h|--help)   uso; exit 0 ;;
    *)           printf 'saikit-decision: opcion desconocida: %s\n' "$1" >&2; uso >&2; exit 2 ;;
  esac
done

if [ -z "$MODO" ]; then
  printf 'saikit-decision: falta --append o --check\n' >&2
  uso >&2
  exit 2
fi
if [ -z "$TASK" ]; then
  printf 'saikit-decision: falta --task <id>\n' >&2
  exit 2
fi

if [ -z "$DIR" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  DIR="$repo_root/.saikit/decisiones"
fi
archivo="$DIR/$TASK.tsv"

# ---------------------------------------------------------------- validacion
# Sale 2 (sin tocar el archivo) al primer problema; 0 si esta bien formado.
validar_archivo() {
  local f="$1"
  [ -f "$f" ] || return 0   # no existe: nada que validar (append lo crea)

  local primera="" linea num=0 campos corta
  while IFS= read -r linea || [ -n "$linea" ]; do
    num=$((num + 1))
    case "$linea" in ''|\#*) continue ;; esac
    if [ -z "$primera" ]; then
      primera="$linea"
      continue
    fi
    campos="$(printf '%s' "$linea" | awk -F'|' '{print NF}')"
    if [ "$campos" != "6" ]; then
      corta="$(printf '%s' "$linea" | cut -d'|' -f1 | cut -c1-20)"
      printf 'TSV malformado: linea %s (%s...) tiene %s columnas, se esperaban 6\n' "$num" "$corta" "$campos" >&2
      exit 2
    fi
    # "Filas completas": el resultado (que define la seccion Atencion via != ok)
    # no puede quedar vacio — el append lo prohibe, y --check tiene que juzgar
    # con el mismo criterio. Un `|` final (campo 6 vacio) es una fila incompleta.
    ult="$(printf '%s' "$linea" | cut -d'|' -f6)"
    if [ -z "$ult" ]; then
      corta="$(printf '%s' "$linea" | cut -d'|' -f1 | cut -c1-20)"
      printf 'TSV malformado: linea %s (%s...) tiene el resultado (columna 6) vacio\n' "$num" "$corta" >&2
      exit 2
    fi
  done < "$f"

  if [ -z "$primera" ]; then
    printf 'TSV invalido: %s no tiene encabezado (se esperaba: %s)\n' "$f" "$HEADER" >&2
    exit 2
  fi
  if [ "$primera" != "$HEADER" ]; then
    printf 'TSV invalido: el encabezado de %s no es el esperado.\n' "$f" >&2
    printf '  esperado: %s\n' "$HEADER" >&2
    printf '  hallado:  %s\n' "$primera" >&2
    exit 2
  fi
  return 0
}

liberar_candado() {
  if [ "$candado_propio" -ne 1 ]; then return 0; fi
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
}

adquirir_candado() {
  lock_dir="$DIR/.saikit-decision-$TASK.lock"
  local intentos=0 pid_guardado vivo
  while [ "$intentos" -lt 60 ]; do
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s' "$$" > "$lock_dir/pid" 2>/dev/null
      candado_propio=1
      trap 'liberar_candado' EXIT
      return 0
    fi
    # El dir existe. Solo se considera huerfano si su pid esta escrito y murio:
    # sin pid legible (otro proceso lo acaba de crear o esta por escribirlo) NO
    # se toca — rmdirlo ahi seria robarle el candado a alguien que ya lo tiene,
    # y seria la puerta a partir una fila. En lo ambiguo se espera y se reintenta.
    pid_guardado=""; vivo=0
    if [ -f "$lock_dir/pid" ]; then
      pid_guardado="$(cat "$lock_dir/pid" 2>/dev/null || true)"
      if [ -n "$pid_guardado" ] && kill -0 "$pid_guardado" 2>/dev/null; then
        vivo=1
      elif [ -n "$pid_guardado" ]; then
        vivo=0   # pid escrito pero muerto: huerfano, se limpia y se reintenta
      else
        vivo=1   # pid ilegible/vacio: no es evidencia de huerfano, esperar
      fi
    else
      # Sin pid: o un writer a mitad del mkdir+pid (microsegundos) o un huerfano
      # (writer muerto ANTES de escribir el pid — un SIGKILL en esa ventana no
      # corre el trap). Se distingue por la EDAD del dir: un recien creado tiene
      # mtime fresco; uno que lleva >2s sin pid es un huerfano (un writer vivo
      # escribe el pid en microsegundos). Reclamarlo no arriesga partir una fila:
      # el rmdir solo funciona sobre un dir VACIO (sin pid); si el writer vivo
      # siguiera ahi, ya habria escrito el pid y el rmdir fallaria. Si `stat` no
      # esta disponible se espera (direccion segura: jamás reclamar a ciegas).
      dir_m="$(stat -c %Y "$lock_dir" 2>/dev/null || echo "$(date +%s)")"
      if [ $(( $(date +%s) - dir_m )) -gt 2 ]; then
        vivo=0   # huerfano sin pid y viejo: se limpia y se reintenta
      else
        vivo=1
      fi
    fi
    if [ "$vivo" -ne 1 ]; then
      # Huerfano con pid muerto: el dir NO esta vacio (tiene el pid), asi que un
      # rmdir pelado fallaria y el candado quedaria clavado para siempre. Se saca
      # el pid y recien entonces el dir. Es la MISMA limpieza que liberar_candado.
      rm -f "$lock_dir/pid" 2>/dev/null || true
      rmdir "$lock_dir" 2>/dev/null || true
    fi
    sleep 0.05
    intentos=$((intentos + 1))
  done
  printf 'no se pudo adquirir el candado\n' >&2
  exit 3
}

# ---------------------------------------------------------------- --check
if [ "$MODO" = "check" ]; then
  if [ ! -f "$archivo" ]; then
    printf 'TSV invalido: no existe %s\n' "$archivo" >&2
    exit 2
  fi
  validar_archivo "$archivo" || exit $?
  exit 0
fi

# ---------------------------------------------------------------- --append
if [ "$MODO" = "append" ]; then
  # Los campos libres no pueden llevar el separador NI un salto de linea: un `|`
  # rompe el conteo de 6 campos, y un \n o \r parte la fila en dos lineas
  # fisicas (viola "sin partir una fila"). Se validan los seis campos.
  # `cuando` se valida aca tambien (si viene de --cuando; el default de la fecha
  # jamas trae `|` ni salto, y vacio pasa): sin esta guardia un --cuando mal
  # formado escribiria una fila de 7 campos que el propio tool no validaria.
  for par in "cuando:$CUANDO" "etapa:$ETAPA" "decision:$DECISION" "por-que:$POR_QUE" "evidencia:$EVIDENCIA" "resultado:$RESULTADO"; do
    nombre="${par%%:*}"
    valor="${par#*:}"
    case "$valor" in
      *\|*) printf 'saikit-decision: --%s no puede contener el separador "|"\n' "$nombre" >&2; exit 2 ;;
      *$'\n'*|*$'\r'*) printf 'saikit-decision: --%s no puede contener un salto de linea (partiria la fila)\n' "$nombre" >&2; exit 2 ;;
    esac
  done
  # "Filas completas": el resultado (que define la seccion Atencion via != ok) y
  # la decision (el contenido de la fila) no pueden quedar vacios. Sin esta
  # guardia, un --resultado vacio escribia una fila de 6 campos pero SIN valor
  # que contar, contradiciendo el contrato de "agrega filas completas".
  if [ -z "$RESULTADO" ]; then
    printf 'saikit-decision: --resultado no puede quedar vacio (es el resultado de la decision)\n' >&2
    exit 2
  fi
  if [ -z "$DECISION" ]; then
    printf 'saikit-decision: --decision no puede quedar vacio\n' >&2
    exit 2
  fi

  if [ -z "$CUANDO" ]; then
    CUANDO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi

  mkdir -p "$DIR" 2>/dev/null || { printf 'saikit-decision: no se pudo crear %s\n' "$DIR" >&2; exit 2; }
  adquirir_candado

  if [ ! -f "$archivo" ]; then
    if ! printf '%s\n' "$HEADER" > "$archivo"; then
      printf 'saikit-decision: no se pudo crear %s\n' "$archivo" >&2
      exit 2
    fi
  fi
  validar_archivo "$archivo" || exit $?

  # Redactar SOLO los campos de texto libre; etapa y resultado son estructurales.
  DECISION_R="$(redactar "$DECISION")"
  POR_QUE_R="$(redactar "$POR_QUE")"
  EVIDENCIA_R="$(redactar "$EVIDENCIA")"

  fila="${CUANDO}|${ETAPA}|${DECISION_R}|${POR_QUE_R}|${EVIDENCIA_R}|${RESULTADO}"
  # La escritura se VERIFICA: sin esto, un fallo de I/O (disco lleno, permisos,
  # ruta que es un directorio) dejaba la fila sin escribir pero el tool seguia y
  # reportaba "registrado" con exit 0 — una fila del rastro que nunca llego al
  # disco y se daba por registrada. El rastro existe para dejar evidencia, asi
  # que escribir mal es un fallo duro (exit 2), no un "aviso" en stderr.
  if ! printf '%s\n' "$fila" >> "$archivo"; then
    printf 'saikit-decision: no se pudo escribir %s\n' "$archivo" >&2
    exit 2
  fi

  linea="$(wc -l < "$archivo" | tr -d ' ')"
  printf 'registrado: %s (linea %s)\n' "$TASK" "$linea"
  exit 0
fi
