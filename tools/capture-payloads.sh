#!/usr/bin/env bash
# capture-payloads.sh — capturar los payloads REALES que el host le manda al
# hook por stdin, para refrescar los fixtures de `tests/fixtures/escenarios`.
#
# Por que existe: los fixtures del repo siguen la forma real de los eventos y
# sus campos salen de transcripts reales, pero no son una captura cruda. Esta
# herramienta cierra esa distancia cuando haga falta, sin que nadie tenga que
# reconstruir el procedimiento de memoria.
#
# Por que NO se corrio al armar los fixtures: el host fotografía los hooks al
# arrancar la sesion. Un hook agregado a mitad de sesion no corre hasta la
# proxima, asi que la captura necesita una sesion nueva — un paso manual, con
# una persona adelante.
#
# Modos:
#   --instalar <repo>                  registra el hook en <repo>/.claude/settings.json
#                                      (Claude; el original)
#   --instalar <repo> --host zcode     appendea 5 entradas de captura en el
#                                      USER-CONFIG de zcode (~/.zcode/cli/config.json)
#                                      — el override de proyecto NO corre en este CLI
#   --cosechar <repo>                  lista lo capturado y recuerda como sacarlo
#   --quitar <repo>                    saca el registro de captura (Claude o zcode
#                                      segun --host, o inferido por la marca)
#   (sin modo, con stdin)              ESTE archivo actuando de hook: guarda el payload
#
# Flags del modo hook (las pone --instalar --host zcode; fail-open siempre):
#   --saikit-capture-id 5.1            marker de propiedad (lo ignora el modo hook)
#   --only-cwd <dir>                   si pwd -P del proceso != pwd -P de <dir>, no escribe
#                                      (otras sesiones del host no filtran un turno)
#   --capture-dir <dir>                equivale a SAIKIT_CAPTURE_DIR
#   --tag <nombre>                     entra en el nombre del archivo
#
# Reglas duras:
#   - Se registra SOLO en un proyecto descartable (Claude) o appendeando en el
#     user-config de zcode. NUNCA en `~/.claude/settings.json`: ahi vive el gate.
#   - El repo destino no puede resolver al perfil ($HOME/.claude* ni $HOME/.zcode*).
#   - Fail-open siempre. Un hook de captura que rompe la sesion que estamos
#     observando no sirve para observar nada.
#   - Lo capturado puede traer rutas y texto del turno real: revisarlo ANTES de
#     copiarlo a un fixture. Los fixtures no llevan credenciales.
set -u

modo=""
destino=""
host=""
cap_id=""
only_cwd=""
cap_dir=""
tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instalar) modo="instalar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --cosechar) modo="cosechar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --quitar)   modo="quitar";   destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --host)     host="${2:-}";     [ $# -ge 2 ] && shift 2 || shift ;;
    --saikit-capture-id) cap_id="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --only-cwd) only_cwd="${2:-}";  [ $# -ge 2 ] && shift 2 || shift ;;
    --capture-dir) cap_dir="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --tag)      tag="${2:-}";       [ $# -ge 2 ] && shift 2 || shift ;;
    -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
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
    salida="${cap_dir:-${SAIKIT_CAPTURE_DIR:-$PWD/capturas}}"

    # --only-cwd: contencion por host. El user-config de zcode es global, asi
    # que el hook dispara en TODAS las sesiones; si el proceso no esta corriendo
    # en el repo descartable, no escribe (no filtra un turno ajeno).
    if [ -n "$only_cwd" ]; then
      aqui="$(pwd -P)"
      want="$(cd "$only_cwd" 2>/dev/null && pwd -P)"
      if [ "$aqui" != "$want" ]; then
        exit 0
      fi
    fi

    mkdir -p "$salida" 2>/dev/null || true
    # Red de contencion contra el commit accidental: la carpeta se ignora a si
    # misma aunque nadie se acuerde de tocar el .gitignore del repo.
    [ -f "$salida/.gitignore" ] || printf '*\n' > "$salida/.gitignore" 2>/dev/null || true
    crudo="$(cat)"
    evento="$(printf '%s' "$crudo" | tr '\n' ' ' \
      | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$evento" ] || evento="sin-evento"
    tagnorm="${tag:+-$tag}"

    # Escritura atomica y sin pisado (hallazgo 4 del plan): dos tools del mismo
    # turno pueden correr a la vez. NO numerar con find|wc -l; mktemp da un
    # nombre unico y mv -n no pisa. El orden de cosecha es `sort` del nombre.
    tmp="$(mktemp "$salida/XXXXXX" 2>/dev/null)" || exit 0
    if ! printf '%s' "$crudo" > "$tmp" 2>/dev/null; then
      rm -f "$tmp"; exit 0
    fi
    base="${evento}${tagnorm}-$(basename "$tmp")"
    if ! mv -n "$tmp" "$salida/$base.json" 2>/dev/null; then
      rm -f "$tmp"; exit 0
    fi

    # Dump del entorno del hook: allowlist CERRADA, nunca prefijo ZCODE/CLAUDE_
    # (R2.1: ese prefijo volcaria ZCODE_API_KEY / *_SECRET / *_TOKEN). Se
    # agrega por NOMBRE si hace falta otra senal de host, no por prefijo.
    env | grep -E '^(PWD|TERM|CLAUDECODE|SUMMONAIKIT|ZCODE_PROJECT_DIR|ZCODE_SESSION_ID|CLAUDE_PROJECT_DIR|CLAUDE_SESSION_ID)=' \
      > "$salida/$base.env" 2>/dev/null || true
  } >/dev/null 2>&1
  exit 0
fi

# -------------------------------------------------- validar host y destino
host="${host:-claude}"
if [ "$host" != "claude" ] && [ "$host" != "zcode" ]; then
  echo "capture-payloads: --host solo acepta 'zcode' (dio '$host')" >&2
  exit 2
fi

if [ -z "$destino" ]; then
  echo "capture-payloads: falta el repo descartable destino" >&2
  exit 2
fi

# La ruta se resuelve FISICA (`pwd -P`). Con la logica, un enlace simbolico que
# apunte al perfil pasaba el filtro: `cd` lo sigue pero `pwd` imprime el nombre
# del enlace, asi que el destino real quedaba escondido detras del alias. Todo
# el valor de esta herramienta es no tocar el perfil vivo; el chequeo tiene que
# mirar donde se escribe de verdad. zcode suma $HOME/.zcode* (donde vive su
# config de usuario) al mismo criterio.
destino_real="$(cd "$destino" 2>/dev/null && pwd -P)"
home_real="$(cd "$HOME" 2>/dev/null && pwd -P)"

if [ -z "$destino_real" ]; then
  echo "capture-payloads: el destino no existe o no se puede entrar: $destino" >&2
  exit 2
fi

case "$destino_real" in
  "$home_real"|"$home_real"/.claude*|"$home_real"/.zcode*)
    echo "capture-payloads: me niego a tocar el perfil real." >&2
    echo "                  pedido: $destino" >&2
    echo "                  resuelve a: $destino_real" >&2
    echo "                  La captura va en un repo descartable, no donde vive el gate/config." >&2
    exit 2
    ;;
esac

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
capturador="$aqui/capture-payloads.sh"

# ---------------- filtros jq para el user-config de zcode (idempotentes) ----
# has_tag/add_unless: appendean una entrada solo si su tag no esta ya presente
# (idempotencia por entrada, no por conteo). ours/strip: --quitar saca solo lo
# que lleva el marker de propiedad `saikit-capture-id 5.1`, deja los ajenos.
# El regex usa 5[.]1 (punto literal) en vez de 5\.1 para no mezclar escapes de
# bash y de jq: una sola capa, sin backslashes.
JQ_INSTALL='
def has_tag(ev; t):
  any( (.hooks.events[ev] // [])[] ;
       any( (.hooks // [])[] ; ((.command // "") | test("saikit-capture-id 5[.]1.*--tag " + t + "$")) ) );
def add_unless(ev; cmd; matcher; t):
  if has_tag(ev; t) then .
  else .hooks.events[ev] = ((.hooks.events[ev] // []) +
    [ (if matcher == "" then {} else {matcher: matcher} end)
      + { hooks: [ { type: "command", command: cmd, timeout: 15 } ] } ])
  end;
add_unless("UserPromptSubmit"; $ups_cmd;   "";                     "ups")
| add_unless("PostToolUse";     $task_cmd;  "Task";                 "task")
| add_unless("PostToolUse";     $agent_cmd; "Agent";                "agent")
| add_unless("PostToolUse";     $tools_cmd; "Bash|Edit|Write|Read"; "tools")
| add_unless("Stop";            $stop_cmd;  "";                     "stop")
'
JQ_QUITAR='
def ours: any((.hooks // [])[]; ((.command // "") | test("saikit-capture-id 5[.]1")));
def strip(arr): ((arr // []) | map(select(ours | not)));
if ((.hooks // {}) | has("events")) then
  .hooks.events.UserPromptSubmit = strip(.hooks.events.UserPromptSubmit)
  | .hooks.events.PostToolUse = strip(.hooks.events.PostToolUse)
  | .hooks.events.Stop = strip(.hooks.events.Stop)
else . end
'

# Resolver un bash.exe de Windows para registrar en el user-config de zcode.
# NUNCA persistir /usr/bin/bash ni la salida cruda de `command -v bash`: en
# MSYS son rutas virtuales que Node resuelve con ENOENT (R2.5 del plan).
zcode_bash_win() {
  local cand b bw
  for cand in \
    "C:/Program Files/Git/bin/bash.exe" \
    "C:/Program Files (x86)/Git/bin/bash.exe" \
    "C:/Program Files/Git/usr/bin/bash.exe"; do
    if [ -f "$cand" ]; then printf '%s' "$cand"; return 0; fi
  done
  if b="$(command -v bash 2>/dev/null)" && [ -n "$b" ] && command -v cygpath >/dev/null 2>&1; then
    bw="$(cygpath -w "$b" 2>/dev/null)" && [ -n "$bw" ] && { printf '%s' "$bw"; return 0; }
  fi
  return 1
}

# Comando de hook para una tag: bash.exe + capturador + flags del modo hook.
# type: command (no process): es la forma que usa el 100% de los hooks del
# config real de zcode, y stdin queda confirmado bajo type:command (cbm lo
# lee asi). Residual del plan resuelto con evidencia, no por fe.
zcode_hook_cmd() {  # $1=bash_win  $2=tag
  printf '"%s" "%s" --saikit-capture-id 5.1 --only-cwd "%s" --capture-dir "%s" --tag %s' \
    "$1" "$capturador" "$destino_real" "$destino_real/capturas" "$2"
}

zcode_install() {
  command -v jq >/dev/null 2>&1 || {
    echo "capture-payloads: --host zcode requiere jq (no encontrado)" >&2; exit 2; }
  local user_config bash_win uc_dir ts bak
  user_config="${SAIKIT_ZCODE_USER_CONFIG:-$HOME/.zcode/cli/config.json}"
  [ -f "$user_config" ] || {
    echo "capture-payloads: no existe el user-config de zcode ($user_config)." >&2
    echo "                  No lo creo de cero: el operador ya tiene uno." >&2
    exit 2; }
  bash_win="$(zcode_bash_win)" || {
    echo "capture-payloads: no encontre un bash.exe de Windows para registrar el hook" >&2
    exit 2; }

  umask 077
  # 1) repo descartable: capturas ignoradas + marca de propiedad (.zcode, no .claude)
  mkdir -p "$destino_real/capturas" 2>/dev/null || true
  printf '*\n' > "$destino_real/capturas/.gitignore" 2>/dev/null || true
  mkdir -p "$destino_real/.zcode" 2>/dev/null || true
  printf 'owner=tools/capture-payloads.sh\nhost=zcode\ntask=5.1\nuser_config=%s\ncwd=%s\ninstalled=%s\n' \
    "$user_config" "$destino_real" "$(date +%Y%m%d-%H%M%S)" \
    > "$destino_real/.zcode/.capture-payloads-owned" || exit 2

  # 2) backup FUERA del dest git, hermano del user-config (R2.2: no adentro de un repo git)
  uc_dir="$(cd "$(dirname "$user_config")" 2>/dev/null && pwd -P)"
  [ -n "$uc_dir" ] || uc_dir="$(dirname "$user_config")"
  mkdir -p "$uc_dir/saikit-backups" || {
    echo "capture-payloads: no pude crear $uc_dir/saikit-backups" >&2; exit 2; }
  ts="$(date +%Y%m%d-%H%M%S)"
  bak="$uc_dir/saikit-backups/config.$ts.bak"
  cp "$user_config" "$bak" || { echo "capture-payloads: fallo el backup" >&2; exit 2; }
  cmp -s "$user_config" "$bak" || {
    echo "capture-payloads: el backup no calza con el original; no toco el config" >&2
    exit 2; }

  # 3) aviso fuerte si los hooks no estan habilitados (no lo reescribo: es suyo)
  if ! jq -e '.hooks.enabled == true' "$user_config" >/dev/null 2>&1; then
    echo "capture-payloads: ADVERTENCIA: .hooks.enabled != true en $user_config" >&2
    echo "                  Los hooks de captura NO van a correr hasta arreglarlo." >&2
  fi

  # 4) append idempotente (5 entradas: UPS, PostToolUse x3, Stop)
  local cmd_ups cmd_task cmd_agent cmd_tools cmd_stop tmp_new
  cmd_ups="$(zcode_hook_cmd "$bash_win" ups)"
  cmd_task="$(zcode_hook_cmd "$bash_win" task)"
  cmd_agent="$(zcode_hook_cmd "$bash_win" agent)"
  cmd_tools="$(zcode_hook_cmd "$bash_win" tools)"
  cmd_stop="$(zcode_hook_cmd "$bash_win" stop)"
  tmp_new="$(mktemp)" || { echo "capture-payloads: no pude crear tmp" >&2; exit 2; }
  if ! jq --arg ups_cmd "$cmd_ups" --arg task_cmd "$cmd_task" --arg agent_cmd "$cmd_agent" \
          --arg tools_cmd "$cmd_tools" --arg stop_cmd "$cmd_stop" "$JQ_INSTALL" \
          "$user_config" > "$tmp_new"; then
    echo "capture-payloads: jq fallo al appendear; el config original queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$user_config" || {
    echo "capture-payloads: no pude escribir $user_config" >&2; exit 2; }

  echo "Captura registrada en el user-config: $user_config"
  echo "  5 entradas con --saikit-capture-id 5.1: UserPromptSubmit, PostToolUse x3, Stop."
  echo "  Repo descartable: $destino_real (capturas en $destino_real/capturas/)"
  echo "  Backup: $bak"
  echo "  Sesion NUEVA de zcode en $destino_real, turno -saikit que delegue + un bash."
}

zcode_quitar() {
  command -v jq >/dev/null 2>&1 || {
    echo "capture-payloads: --host zcode requiere jq (no encontrado)" >&2; exit 2; }
  local marca user_config tmp_new n_antes n_despues
  marca="$destino_real/.zcode/.capture-payloads-owned"
  [ -f "$marca" ] || {
    echo "capture-payloads: no hay marca de captura zcode en $marca (nada que quitar)" >&2
    exit 2; }
  user_config="${SAIKIT_ZCODE_USER_CONFIG:-$(grep '^user_config=' "$marca" 2>/dev/null | cut -d= -f2-)}"
  [ -n "$user_config" ] || user_config="$HOME/.zcode/cli/config.json"
  [ -f "$user_config" ] || {
    echo "capture-payloads: no existe el user-config ($user_config)" >&2; exit 2; }

  n_antes="$(grep -c 'saikit-capture-id 5\.1' "$user_config" 2>/dev/null || true)"
  tmp_new="$(mktemp)" || exit 2
  if ! jq "$JQ_QUITAR" "$user_config" > "$tmp_new"; then
    echo "capture-payloads: jq fallo al quitar; el config queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$user_config" || {
    echo "capture-payloads: no pude escribir $user_config" >&2; exit 2; }
  n_despues="$(grep -c 'saikit-capture-id 5\.1' "$user_config" 2>/dev/null || true)"
  rm -f "$marca"
  echo "Quitadas entradas de captura (saikit-capture-id 5.1) de $user_config"
  echo "  antes: $n_antes   despues: $n_despues   (los hooks ajenos quedan intactos)"
}

case "$modo" in
  instalar)
    if [ "$host" = "zcode" ]; then
      zcode_install
    else
      # ----- Claude: settings.json del proyecto descartable (el original) -----
      settings="$destino_real/.claude/settings.json"
      propio="$destino_real/.claude/.capture-payloads-owned"
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
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude bash \\"$capturador\\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude bash \\"$capturador\\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude bash \\"$capturador\\"" } ] }
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
    fi
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
    # Inferir el host si no se paso --host: la marca .zcode dice zcode.
    if [ "$host" = "claude" ] && [ -f "$destino_real/.zcode/.capture-payloads-owned" ]; then
      host="zcode"
    fi
    if [ "$host" = "zcode" ]; then
      zcode_quitar
    else
      # Solo se borra lo que ESTE script creo, y eso lo dice la marca de
      # propiedad, no el contenido. Un settings.json que menciona esta
      # herramienta puede ser un archivo del usuario donde el mismo pego los
      # bloques a mano — borrarlo entero se lleva puesta toda su configuracion.
      settings="$destino_real/.claude/settings.json"
      propio="$destino_real/.claude/.capture-payloads-owned"
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
    fi
    ;;
esac
