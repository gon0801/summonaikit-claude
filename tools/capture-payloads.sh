#!/usr/bin/env bash
# capture-payloads.sh — capturar los payloads REALES que Claude Code le manda
# al hook por stdin, para refrescar los fixtures de `tests/fixtures/escenarios`.
#
# Por que existe: los fixtures del repo siguen la forma real de los eventos y
# sus campos salen de transcripts reales, pero no son una captura cruda. Esta
# herramienta cierra esa distancia cuando haga falta, sin que nadie tenga que
# reconstruir el procedimiento de memoria.
#
# Por que NO se corrio al armar los fixtures: Claude Code fotografia los hooks
# al arrancar la sesion. Un hook agregado a mitad de sesion no corre hasta la
# proxima, asi que la captura necesita una sesion nueva — un paso manual, con
# una persona adelante.
#
# Modos:
#   --instalar <repo>   registra el hook de captura en <repo>/.claude/settings.json
#   --cosechar <repo>   lista lo capturado y recuerda como sacarlo
#   --quitar <repo>     saca el registro de captura
#   (sin modo, con stdin)  ESTE archivo actuando de hook: guarda el payload
#
# Reglas duras:
#   - Se registra SOLO en el settings de un proyecto descartable. NUNCA en
#     `~/.claude/settings.json`: ahi vive el registro del gate de verdad.
#   - Fail-open siempre. Un hook de captura que rompe la sesion que estamos
#     observando no sirve para observar nada.
#   - Lo capturado puede traer rutas y texto del turno real: revisarlo ANTES de
#     copiarlo a un fixture. Los fixtures no llevan credenciales.
set -u

modo=""
destino=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instalar) modo="instalar"; destino="${2:-}"; shift 2 ;;
    --cosechar) modo="cosechar"; destino="${2:-}"; shift 2 ;;
    --quitar)   modo="quitar";   destino="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    *)          shift ;;
  esac
done

# ------------------------------------------------ modo hook: guardar el stdin
if [ -z "$modo" ]; then
  {
    # Lo capturado es el payload CRUDO de un turno real: puede traer el texto
    # del prompt, rutas del perfil y lo que haya pasado por una linea de
    # comando. Se escribe solo para el dueno.
    umask 077
    salida="${SAIKIT_CAPTURE_DIR:-$PWD/capturas}"
    mkdir -p "$salida" 2>/dev/null || true
    # Red de contencion contra el commit accidental: la carpeta se ignora a si
    # misma aunque nadie se acuerde de tocar el .gitignore del repo.
    [ -f "$salida/.gitignore" ] || printf '*\n' > "$salida/.gitignore" 2>/dev/null || true
    crudo="$(cat)"
    evento="$(printf '%s' "$crudo" | tr '\n' ' ' \
      | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$evento" ] || evento="sin-evento"
    n="$(find "$salida" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    printf '%s' "$crudo" > "$salida/$(printf '%03d' "$((n + 1))")-$evento.json" 2>/dev/null || true
  } >/dev/null 2>&1
  exit 0
fi

if [ -z "$destino" ]; then
  echo "capture-payloads: falta el repo destino" >&2
  exit 2
fi

# La ruta se resuelve FISICA (`pwd -P`). Con la logica, un enlace simbolico que
# apunte al perfil pasaba el filtro: `cd` lo sigue pero `pwd` imprime el nombre
# del enlace, asi que el destino real quedaba escondido detras del alias. Todo
# el valor de esta herramienta es no tocar el perfil vivo; el chequeo tiene que
# mirar donde se escribe de verdad.
destino_real="$(cd "$destino" 2>/dev/null && pwd -P)"
home_real="$(cd "$HOME" 2>/dev/null && pwd -P)"

if [ -z "$destino_real" ]; then
  echo "capture-payloads: el destino no existe o no se puede entrar: $destino" >&2
  exit 2
fi

case "$destino_real" in
  "$home_real"|"$home_real"/.claude*)
    echo "capture-payloads: me niego a tocar el perfil real." >&2
    echo "                  pedido: $destino" >&2
    echo "                  resuelve a: $destino_real" >&2
    echo "                  La captura va en un repo descartable, no donde vive el gate." >&2
    exit 2
    ;;
esac

settings="$destino_real/.claude/settings.json"
# Marca de propiedad: sin esto, `--quitar` no borra nada. Ver el modo quitar.
propio="$destino_real/.claude/.capture-payloads-owned"
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
capturador="$aqui/capture-payloads.sh"

case "$modo" in
  instalar)
    umask 077
    mkdir -p "$destino_real/.claude" || exit 2
    if [ -e "$settings" ]; then
      echo "capture-payloads: ya existe $settings — no lo piso." >&2
      echo "                  Agregar a mano los 3 bloques y volver a correr --cosechar." >&2
      echo "                  OJO: si los agregas a mano, --quitar NO va a borrar ese" >&2
      echo "                  archivo (no es mio); hay que sacar los bloques igual de a mano." >&2
      exit 2
    fi
    cat > "$settings" <<JSON
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash \\"$capturador\\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "bash \\"$capturador\\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \\"$capturador\\"" } ] }
    ]
  }
}
JSON
    printf 'creado por tools/capture-payloads.sh --instalar\n' > "$propio" || exit 2
    # La carpeta de capturas se crea ACA, ya ignorada: si esperara al primer
    # payload, el .gitignore llegaria despues que el archivo con el contenido
    # del turno.
    mkdir -p "$destino_real/capturas" 2>/dev/null || true
    printf '*\n' > "$destino_real/capturas/.gitignore" 2>/dev/null || true
    echo "Registrado en $settings"
    echo "Ahora: arrancar una sesion NUEVA de Claude Code en $destino_real y hacer un turno -saikit completo."
    echo "Los payloads caen en $destino_real/capturas/ (o en \$SAIKIT_CAPTURE_DIR)."
    ;;
  cosechar)
    salida="${SAIKIT_CAPTURE_DIR:-$destino_real/capturas}"
    if [ ! -d "$salida" ]; then
      echo "capture-payloads: todavia no hay capturas en $salida"
      echo "                  Si la sesion ya corrio, revisar que se haya arrancado DESPUES de --instalar."
      exit 2
    fi
    find "$salida" -maxdepth 1 -type f -name '*.json' | sort
    echo
    echo "Revisar el contenido antes de copiarlo: puede traer rutas y texto del turno real."
    ;;
  quitar)
    # Solo se borra lo que ESTE script creo, y eso lo dice la marca de
    # propiedad, no el contenido. Un settings.json que menciona esta
    # herramienta puede ser un archivo del usuario donde el mismo pego los
    # bloques a mano — borrarlo entero se lleva puesta toda su configuracion.
    # Mismo criterio que el instalador del proyecto (tres estados, no dos):
    # mio => lo saco; ajeno => no lo toco y lo digo.
    if [ ! -f "$settings" ]; then
      echo "No hay settings de captura en $settings (nada que quitar)"
    elif [ -f "$propio" ]; then
      rm -f "$settings" "$propio"
      echo "Quitado $settings (lo habia creado yo)"
    elif grep -q 'capture-payloads.sh' "$settings"; then
      echo "capture-payloads: $settings tiene el hook de captura pero NO lo cree yo." >&2
      echo "                  No lo borro: puede tener configuracion tuya." >&2
      echo "                  Sacar a mano los bloques que llaman a capture-payloads.sh." >&2
      exit 2
    else
      echo "No hay registro de captura en $settings (nada que quitar)"
    fi
    ;;
esac
