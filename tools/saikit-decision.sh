#!/usr/bin/env bash
: <<'SAIKIT_MARCA'
---
saikit_owned: summonaikit-claude
---
SAIKIT_MARCA
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
#   --check         valida el archivo existente. Para leer un snapshot estable
#                   (no una fila a medio escribir, hallazgo 17.8-c) adquiere el
#                   MISMO candado que el append, asi que necesita escritura en
#                   $DIR (para el dir de candado); si el candado no se adquiere
#                   en ~3 s sale 3. No modifica el tsv (REPORT, NO REPARAR).
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
# Token de adquisicion: al obtener el candado se escribe "$$:<nonce>". El nonce
# (generado por adquisicion) identifica UNA posesion, para que liberar_candado
# conozca su propio candado y no le borre el de otro (hallazgo 17.8-a).
lock_nonce=""; lock_dir=""

uso() {
  sed -n '/^# saikit-decision.sh/,/^set -u/{ /^#/p; }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --append)    MODO="append"; shift ;;
    --check)     MODO="check"; shift ;;
    --task|--etapa|--decision|--por-que|--evidencia|--resultado|--cuando|--dir)
      # El bug de la Task 0.4, que este repo ya pago una vez: `shift 2` con un
      # solo argumento no consume nada y el while gira para siempre (medido
      # aca tambien: rc=124 por timeout). Un flag con valor EXIGE el valor.
      if [ $# -lt 2 ]; then
        printf 'saikit-decision: %s exige un valor\n' "$1" >&2; exit 2
      fi
      # kimi #11: `--etapa --decision` asignaba "--decision" como VALOR de
      # etapa y seguia — un tipeo corrompia la fila en silencio.
      case "$2" in --*)
        # El valor NO se repite crudo (CodeRabbit, PR #130): `--task --token=secreto`
        # matchea esta rama y el diagnostico lo volcaba a stderr — el mismo pecado
        # que este commit cierra en el veto de --task.
        printf 'saikit-decision: %s recibio otro flag como valor (empieza con --)\n' "$1" >&2; exit 2 ;;
      esac
      case "$1" in
        --task)      TASK="$2" ;;
        --etapa)     ETAPA="$2" ;;
        --decision)  DECISION="$2" ;;
        --por-que)   POR_QUE="$2" ;;
        --evidencia) EVIDENCIA="$2" ;;
        --resultado) RESULTADO="$2" ;;
        --cuando)    CUANDO="$2" ;;
        --dir)       DIR="$2" ;;
      esac
      shift 2 ;;
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
# --task es un NOMBRE de archivo con contrato (cross-review kimi+qwen):
# charset seguro y acotado, no vacio, sin rutas — y SIN forma de secreto,
# porque el nombre acaba commiteado en .saikit/decisiones/ y la redaccion de
# campos no lo cubre (un `--task ghp_abc` creaba `ghp_abc.tsv` en el repo).
# El patron `..` es deliberadamente conservador: tambien rechaza `release..2`
# — un falso positivo aceptable frente a una ruta que se escapa.
# Los mensajes NO repiten el valor crudo: si el valor ES un secreto, el error
# no puede ser la via por la que se imprime.
if [ -z "$TASK" ]; then
  printf 'saikit-decision: --task no puede ser vacio\n' >&2
  exit 2
fi
case "$TASK" in
  */*|*\\*|..*|*..*|.*)
    printf 'saikit-decision: --task no admite rutas ni nombres ocultos (/, \\, .. o punto inicial)\n' >&2
    exit 2 ;;
  ghp_*|github_pat_*|gho_*|sk-*|AKIA*|xoxb-*|xoxp-*)
    printf 'saikit-decision: --task tiene forma de secreto; el nombre se commitea y no se redacta\n' >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    printf 'saikit-decision: --task solo admite [A-Za-z0-9._-]\n' >&2
    exit 2 ;;
esac
archivo="$DIR/$TASK.tsv"

# ---------------------------------------------------------------- validacion
# Sale 2 (sin tocar el archivo) al primer problema; 0 si esta bien formado.
validar_archivo() {
  local f="$1"
  local CR; CR="$(printf '\r')"
  [ -f "$f" ] || return 0   # no existe: nada que validar (append lo crea)

  # La ULTIMA fila tiene que terminar en salto de linea. Si el archivo no termina
  # en \n, la fila final esta INCOMPLETA — tipicamente un append cortado por
  # SIGKILL/ENOSPC, o un archivo externo sin el \n final — y esa fila parcial se
  # "pegaria" a la siguiente cuando alguien escriba despues; el check la daria
  # por buena (hallazgo 17.8-b). Se reporta malformado, no se da por buena ni se
  # repara. El `tail -c 1` da \n => la sustitución de comando lo recorta y queda
  # vacio; cualquier otro byte queda y se detecta. Un archivo vacio (0 bytes)
  # deja `-s` falso y se saltea (lo juzga el encabezado abajo).
  if [ -s "$f" ] && [ -n "$(tail -c 1 "$f" 2>/dev/null)" ]; then
    printf 'TSV malformado: %s no termina en salto de linea (fila final incompleta)\n' "$f" >&2
    exit 2
  fi

  local primera="" linea num=0 campos corta
  while IFS= read -r linea || [ -n "$linea" ]; do
    num=$((num + 1))
    # Un CR embebido parte el contrato de "una fila = una linea" a medias:
    # --append lo veta, y --check juzga con el MISMO criterio (codex #7).
    # $CR se computa una vez fuera del loop (kimi #8: un fork por linea son
    # ~28 ms cada uno en MSYS, medido en AGENTS.md).
    case "$linea" in *"$CR"*)
      printf 'TSV malformado: linea %s trae retorno de carro\n' "$num" >&2
      exit 2 ;;
    esac
    # Las lineas '#' NO se saltan (grok #8 / codex #6): saltarlas dejaba
    # inyectar filas que --check jamas miraba. El unico texto especial es la
    # primera linea, que debe ser el encabezado; lo vacio sigue tolerado.
    case "$linea" in '') continue ;; esac
    if [ -z "$primera" ]; then
      primera="$linea"
      continue
    fi
    case "$linea" in \#*)
      printf 'TSV malformado: linea %s es un comentario inyectado (no se admiten)\n' "$num" >&2
      exit 2 ;;
    esac
    campos="$(printf '%s' "$linea" | awk -F'|' '{print NF}')"
    if [ "$campos" != "6" ]; then
      corta="$(redactar "$(printf '%s' "$linea" | cut -d'|' -f1)" | cut -c1-20)"
      printf 'TSV malformado: linea %s (%s...) tiene %s columnas, se esperaban 6\n' "$num" "$corta" "$campos" >&2
      exit 2
    fi
    # "Filas completas": el resultado (que define la seccion Atencion via != ok)
    # no puede quedar vacio — el append lo prohibe, y --check tiene que juzgar
    # con el mismo criterio. Un `|` final (campo 6 vacio) es una fila incompleta.
    ult="$(printf '%s' "$linea" | cut -d'|' -f6)"
    if [ -z "$ult" ]; then
      corta="$(redactar "$(printf '%s' "$linea" | cut -d'|' -f1)" | cut -c1-20)"
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

# Punto de suspension SOLO bajo test (SAIKIT_DECISION_TEST=1). Permite a un test
# de concurrencia detener el tool en un punto conocido y orquestar la carrera con
# determinismo (precedente de la 0.4: un bucle se midio con timeout y rc=124).
# Sin el guard, o sin SAIKIT_DECISION_TEST_DIR, es un no-op: PRODUCCION INTACTA.
# El control es por archivo con el PID del proceso ($$), asi un test sabe por
# PID a quien detuvo: el tool escribe at-<knee>.$$ y espera go-<knee>.$$.
test_knee() {
  [ "${SAIKIT_DECISION_TEST:-}" = "1" ] || return 0
  local knee="$1" d="${SAIKIT_DECISION_TEST_DIR:-}"
  [ -n "$d" ] || return 0
  mkdir -p "$d" 2>/dev/null || true
  touch "$d/at-$knee.$$" 2>/dev/null || true
  # Espera ACOTADA (fail-fast): si el go nunca aparece (test mal orquestado, o un
  # env de test presente sin el go), no gira infinito agarrado del candado — sale
  # 2 y el trap libera. Un bucle sin tope colgaba el tool indefinidamente.
  local cont=0
  while [ ! -e "$d/go-$knee.$$" ] && [ "$cont" -lt 500 ]; do sleep 0.01; cont=$((cont + 1)); done
  # Timeout REAL: solo si el cont llego al tope Y el go SIGUE ausente. Si el go
  # aparecio justo en la ultima ventana (cont==500), no es un fallo: se suelta
  # normal. Se limpia el at y se sale 2 (el trap libera el candado); no gire.
  if [ "$cont" -ge 500 ] && [ ! -e "$d/go-$knee.$$" ]; then
    rm -f "$d/at-$knee.$$" 2>/dev/null || true
    printf 'saikit-decision: knee %s sin liberar en ~5s (test mal orquestado)\n' "$knee" >&2
    exit 2
  fi
  rm -f "$d/go-$knee.$$" "$d/at-$knee.$$" 2>/dev/null || true
}

# Suelta SOLO el candado propio. Se re-lee el token y se compara con el OWNER
# ("$$:$lock_nonce"): si en el ínterin el candado fue reclamado por otro (otro
# pid/nonce), NO se toca — el trap EXIT de un proceso no le borra el candado al
# otro (hallazgo 17.8-a). Antes, el trap borraba sin mirar y, tras la carrera
# ABA, los dos terminaban con candado_propio=1 y se destrozaban el lock mutuo.
liberar_candado() {
  if [ "$candado_propio" -ne 1 ]; then return 0; fi
  local token=""
  token="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [ "$token" = "$$:$lock_nonce" ]; then
    rm -f "$lock_dir/pid" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  candado_propio=0
}

adquirir_candado() {
  lock_dir="$DIR/.saikit-decision-$TASK.lock"
  local intentos=0 pid_guardado vivo dueno
  # 18.22: mtime del dir de candado portable — `stat -c %Y` es GNU y en BSD
  # devuelve vacio, que por el fallback anterior significaba edad 0: el huerfano
  # sin pid JAMAS se reclamaba en macOS (medido: test_saikit_decision). Mismo
  # molde que mtime_de de tools/install-hook.sh. Vacio = no medible: el caller
  # conserva el fail-safe declarado (edad 0 => esperar, nunca reclamar a ciegas).
  _edad_dir() {  # $1 = ruta -> epoch mtime por stdout, o vacio
    local _m
    _m="$(stat -c %Y "$1" 2>/dev/null)" && { printf '%s' "$_m"; return 0; }
    _m="$(stat -f %m "$1" 2>/dev/null)" && { printf '%s' "$_m"; return 0; }
    return 1
  }
  while [ "$intentos" -lt 60 ]; do
    if mkdir "$lock_dir" 2>/dev/null; then
      # Somos el dueno. Se escribe el token y se VERIFICA que llego (hallazgo c:
      # antes se tragaba el fallo y quedaba un lock SIN pid que nadie podia
      # reclamar de forma segura). Si la escritura falla, esta adquisicion no es
      # un lock valido: se suelta (el dir es nuestro) y se reintenta.
      lock_nonce="$RANDOM${RANDOM}${RANDOM}"
      if ! printf '%s:%s' "$$" "$lock_nonce" > "$lock_dir/pid" 2>/dev/null; then
        rmdir "$lock_dir" 2>/dev/null || true
        sleep 0.05; intentos=$((intentos + 1)); continue
      fi
      candado_propio=1
      trap 'liberar_candado' EXIT
      test_knee hold
      return 0
    fi
    # El dir existe. Se lee el dueno. Si esta escrito y vivo => esperar. Si esta
    # escrito y muerto => huerfano candidato. Sin pid: o un writer a mitad del
    # mkdir+pid (microsegundos) o un huerfano muerto ANTES de escribir el pid;
    # se distingue por la EDAD del dir (un writer vivo escribe el pid en
    # microsegundos). Portabilidad (hallazgo d + 18.22): el mtime sale de
    # _edad_dir (GNU stat, si no BSD); donde NINGUNO pueda medir, el fallback
    # deja edad 0, que es "nunca reclamar" — fail-safe declarado: en un sistema
    # sin stat medible no se reclama un huerfano a ciegas, se espera (mejor
    # bloquear 3s que partir una fila).
    vivo=0
    dueno="$(cat "$lock_dir/pid" 2>/dev/null || true)"
    if [ -n "$dueno" ]; then
      pid_guardado="${dueno%%:*}"
      if [ -n "$pid_guardado" ] && kill -0 "$pid_guardado" 2>/dev/null; then
        vivo=1
      fi
    else
      dir_m="$(_edad_dir "$lock_dir")"
      [ -n "$dir_m" ] || dir_m="$(date +%s)"
      if [ $(( $(date +%s) - dir_m )) -le 2 ]; then
        vivo=1
      fi
    fi
    if [ "$vivo" -eq 0 ]; then
      # RE-VERIFICACION y RECLAMACION. La decision de "huerfano" vino de un read
      # de arriba; entre ese read y este punto OTRO pudo readquirir el lock (la
      # carrera ABA del hallazgo a). Por eso, justo antes de tocar, se RE-LEE el
      # token y SOLO se reclama si el dueno sigue muerto. Limitacion declarada
      # (best-effort, candado sin mutex): el re-read (cat) y el rm son dos
      # operaciones no atomicas, asi que media una ventana de microsegundos en la
      # que un tercero que re-adquiera pareceria "vivo" recien despues del cat —
      # en la practica es inalcanzable (requiere que otro reclaimer haga
      # rm+rmdir+mkdir+write en esa ventana), pero NO es una garantia dura. Si
      # este reclamante eliminara un pid re-adquirido, el rm+rmdir de abajo
      # puede fallar (rmdir sobre dir no vacio) y el otro quedaria como dueno.
      # La reclamacion es rm del pid + rmdir del dir vacio. Se elige sin `mv` a
      # proposito: si nos matan entre el rm y el rmdir, el dir queda VACIO y el
      # reclamo por edad lo toma (~2 s despues de que envejece) — self-heal.
      # Con un `mv` del pid adentro del dir (la version anterior) un kill en esa
      # ventana dejaba `pid.reclaim.<pid>` en el dir, que lo volvia NO-vacio
      # para siempre y clavaba el candado. El rm+rmdir no tiene ese wedge.
      dueno="$(cat "$lock_dir/pid" 2>/dev/null || true)"
      if [ -n "$dueno" ]; then
        pid_guardado="${dueno%%:*}"
        if [ -n "$pid_guardado" ] && kill -0 "$pid_guardado" 2>/dev/null; then
          vivo=1
        else
          # Sigue siendo huerfano (re-verificado). rm del pid + rmdir del dir
          # vacio: si en el ínterin OTRO re-creo el dir con pid, el rmdir falla
          # (no vacio) y se espera — nunca se le borra el candado a un vivo.
          rm -f "$lock_dir/pid" 2>/dev/null || true
          rmdir "$lock_dir" 2>/dev/null || true
        fi
      else
        # Dir vacio y viejo (huerfano sin pid). rmdir pelado: si en el instante
        # OTRO acaba de re-crearlo con pid, el rmdir falla (no vacio) y se espera.
        rmdir "$lock_dir" 2>/dev/null || true
      fi
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
  # --check adquiere el candado para leer un snapshot estable: sin el, podia
  # leer una fila a medio escribir y reportar "malformado" falso (hallazgo
  # 17.8-c). Necesita escritura en $DIR (el dir de candado); si el candado no se
  # adquiere en ~3 s sale 3 (contencion o $DIR sin escritura), sin tocar un
  # byte. El trap de liberar_candado lo suelta al salir (aun por exit 2), asi un
  # --check sobre un archivo malformado no deja el candado puesto.
  adquirir_candado || exit $?
  validar_archivo "$archivo" || exit $?
  liberar_candado
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

  # Se redactan TODOS los campos (cross-review codex #2). La version anterior
  # decia "etapa y resultado son estructurales" — era una intencion, no una
  # regla: nada los restringe a un vocabulario, asi que un secreto pegado ahi
  # viajaba en claro al archivo commiteado.
  CUANDO_R="$(redactar "$CUANDO")"
  ETAPA_R="$(redactar "$ETAPA")"
  DECISION_R="$(redactar "$DECISION")"
  POR_QUE_R="$(redactar "$POR_QUE")"
  EVIDENCIA_R="$(redactar "$EVIDENCIA")"
  RESULTADO_R="$(redactar "$RESULTADO")"

  fila="${CUANDO_R}|${ETAPA_R}|${DECISION_R}|${POR_QUE_R}|${EVIDENCIA_R}|${RESULTADO_R}"

  # APPEND ATOMICO — diseño declarado con su tradeoff. La fila se escribe con UNA
  # sola escritura (`printf >>` con O_APPEND = una unica write(2), atomica para
  # filas cortas en un archivo local) y se VERIFICA por delta de tamaño: si
  # SIGKILL/ENOSPC corta la escritura a medias, el archivo no crece los bytes
  # esperados y se reporta — nunca se dice "registrado" por una fila que no llego
  # entera (hallazgo b). Tradeoff: esto DETECTA y falla cerrado (exit 2), pero NO
  # revierte los bytes parciales (un append no se deshace in place); la fila
  # truncada queda visible y le pega el guardia de validar_archivo (que ya juzgo
  # la ultima fila terminada en \n) al proximo append. Es deteccion + rechazo,
  # no reparacion.
  antes="$(wc -c < "$archivo" | tr -d ' ')"
  if ! printf '%s\n' "$fila" >> "$archivo"; then
    printf 'saikit-decision: no se pudo escribir %s\n' "$archivo" >&2
    exit 2
  fi
  despues="$(wc -c < "$archivo" | tr -d ' ')"
  # ${#fila} cuenta CARACTERES; el archivo guarda BYTES. El rastro es en espanol
  # (acentos), asi que el largo de la fila se mide en bytes, no en caracteres.
  len_fila="$(LC_ALL=C printf '%s' "$fila" | wc -c | tr -d ' ')"
  esperado=$((antes + len_fila + 1))   # +1 por el salto final
  if [ "$despues" -ne "$esperado" ]; then
    printf 'saikit-decision: escritura incompleta en %s (se esperaban %s bytes, hay %s)\n' "$archivo" "$esperado" "$despues" >&2
    exit 2
  fi

  linea="$(wc -l < "$archivo" | tr -d ' ')"
  printf 'registrado: %s (linea %s)\n' "$TASK" "$linea"
  exit 0
fi
