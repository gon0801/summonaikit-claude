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
    salida="${SAIKIT_CAPTURE_DIR:-$PWD/capturas}"
    mkdir -p "$salida" 2>/dev/null || true
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

case "$(cd "$destino" 2>/dev/null && pwd)" in
  "$HOME"|"$HOME/.claude"*)
    echo "capture-payloads: me niego a tocar el perfil real ($destino)." >&2
    echo "                  La captura va en un repo descartable, no donde vive el gate." >&2
    exit 2
    ;;
esac

settings="$destino/.claude/settings.json"
aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
capturador="$aqui/capture-payloads.sh"

case "$modo" in
  instalar)
    mkdir -p "$destino/.claude" || exit 2
    if [ -e "$settings" ]; then
      echo "capture-payloads: ya existe $settings — no lo piso." >&2
      echo "                  Agregar a mano los 3 bloques y volver a correr --cosechar." >&2
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
    echo "Registrado en $settings"
    echo "Ahora: arrancar una sesion NUEVA de Claude Code en $destino y hacer un turno -saikit completo."
    echo "Los payloads caen en $destino/capturas/ (o en \$SAIKIT_CAPTURE_DIR)."
    ;;
  cosechar)
    salida="${SAIKIT_CAPTURE_DIR:-$destino/capturas}"
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
    if [ -f "$settings" ] && grep -q 'capture-payloads.sh' "$settings"; then
      rm -f "$settings"
      echo "Quitado $settings"
    else
      echo "No hay registro de captura en $settings (nada que quitar)"
    fi
    ;;
esac
