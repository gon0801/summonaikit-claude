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
#   --instalar <repo> --host codex     coloca un shim en <repo>/.codex/hooks/ (el
#                                      .ps1 del perfil lo prefiere; no toca configs)
#   --instalar <repo> --host grok      escribe <repo>/.grok/hooks/saikit-capture.json
#                                      (Grok SI corre hooks de proyecto, tras trust
#                                      del folder) — cada handler lleva el env map
#                                      SUMMONAIKIT_HOOK_TARGET=grok para medir si llega
#   --cosechar <repo>                  lista lo capturado y recuerda como sacarlo
#   --quitar <repo>                    saca el registro de captura (Claude, zcode,
#                                      codex o grok segun --host, o inferido por la marca)
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
#   - Se registra SOLO en un proyecto descartable. NUNCA en
#     `~/.claude/settings.json`: ahi vive el gate. En zcode se appendea al
#     user-config; en codex/grok se colocan archivos propios en <repo>/.codex
#     y <repo>/.grok — los perfiles `~/.codex` y `~/.grok` no se tocan.
#   - El repo destino no puede resolver al perfil ($HOME/.claude*, $HOME/.zcode*
#     ni $HOME/.grok*).
#   - Fail-open siempre. Un hook de captura que rompe la sesion que estamos
#     observando no sirve para observar nada.
#   - Lo capturado puede traer rutas y texto del turno real: revisarlo ANTES de
#     copiarlo a un fixture. Los fixtures no llevan credenciales.
set -u

modo=""
destino=""
host=""
cap_id=""
dest_id_arg=""
only_cwd=""
cap_dir=""
tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instalar) modo="instalar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --cosechar) modo="cosechar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --quitar)   modo="quitar";   destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    # H1 (hallazgo de CodeRabbit en el PR#2, abierto hasta 2026-08-13): con el
    # flag al final `${2:-}` quedaba vacio y el `host="${host:-claude}"` de mas
    # abajo lo convertia en 'claude'. Un typo en el flag NO fallaba: capturaba
    # el host equivocado y se descubria con la captura vacia, o sea quemando una
    # sesion con el operador adelante. Se exige `-n "$2"` ademas del conteo,
    # porque `--host ""` volveria a caer en el mismo default.
    --host)
      { [ $# -ge 2 ] && [ -n "$2" ]; } || {
        echo "capture-payloads: --host requiere un valor ('claude', 'zcode', 'codex' o 'grok')" >&2
        exit 2; }
      host="$2"; shift 2 ;;
    --saikit-capture-id) cap_id="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    # H2: identificador del destino, para que el config compartido de zcode
    # distinga instalaciones. El modo hook lo ignora, igual que --saikit-capture-id.
    --saikit-dest) dest_id_arg="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --only-cwd) only_cwd="${2:-}";  [ $# -ge 2 ] && shift 2 || shift ;;
    --capture-dir) cap_dir="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --tag)      tag="${2:-}";       [ $# -ge 2 ] && shift 2 || shift ;;
    -h|--help)  sed -n '2,49p' "$0"; exit 0 ;;
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
    # Grok manda el envelope en camelCase (`hookEventName`), no en snake. Sin
    # este fallback todos los eventos de Grok colisionarian en "sin-evento" y
    # la captura no serviria para nada. El snake sigue ganando si llega.
    [ -n "$evento" ] || evento="$(printf '%s' "$crudo" | tr '\n' ' ' \
      | sed -n 's/.*"hookEventName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
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
    # Task 6.1: SUMMONAIKIT_HOOK_TARGET/PHASE van por NOMBRE. La entrada
    # `SUMMONAIKIT` que habia solo matcheaba una variable llamada exactamente
    # asi: el regex ancla el `=` inmediatamente despues, asi que
    # SUMMONAIKIT_HOOK_TARGET NUNCA se capturaba. En zcode daba igual (ahi el
    # TARGET no llega, A10); en codex es el dato que la DoD pide medir.
    # Task 7.1: GROK_HOOK_EVENT/GROK_SESSION_ID/GROK_WORKSPACE_ROOT por NOMBRE
    # (D2 cuelga de medirlas). El prefijo GROK_ queda FUERA por la misma razon
    # que ZCODE_: volcaria GROK_API_KEY. `CLAUDECODE` ya esta en la lista y
    # contesta la otra mitad de D2 (si Grok la setea, hay colision que cerrar).
    env | grep -E '^(PWD|TERM|CLAUDECODE|SUMMONAIKIT|SUMMONAIKIT_HOOK_TARGET|SUMMONAIKIT_HOOK_PHASE|ZCODE_PROJECT_DIR|ZCODE_SESSION_ID|CLAUDE_PROJECT_DIR|CLAUDE_SESSION_ID|GROK_HOOK_EVENT|GROK_SESSION_ID|GROK_WORKSPACE_ROOT)=' \
      > "$salida/$base.env" 2>/dev/null || true
  } >/dev/null 2>&1
  exit 0
fi

# -------------------------------------------------- validar host y destino
# Se conserva el default para el caso "no se paso el flag"; el flag SIN valor ya
# murio arriba (H1), asi que este `:-` ya no puede enmascarar un error.
host="${host:-claude}"
case "$host" in
  claude|zcode|codex|grok) ;;
  *) echo "capture-payloads: --host acepta 'claude', 'zcode', 'codex' o 'grok' (dio '$host')" >&2
     exit 2 ;;
esac

if [ -z "$destino" ]; then
  echo "capture-payloads: falta el repo descartable destino" >&2
  exit 2
fi

# La ruta se resuelve FISICA (`pwd -P`). Con la logica, un enlace simbolico que
# apunte al perfil pasaba el filtro: `cd` lo sigue pero `pwd` imprime el nombre
# del enlace, asi que el destino real quedaba escondido detras del alias. Todo
# el valor de esta herramienta es no tocar el perfil vivo; el chequeo tiene que
# mirar donde se escribe de verdad. zcode suma $HOME/.zcode* (donde vive su
# config de usuario) y grok $HOME/.grok* (hooks y agents globales) al mismo
# criterio.
destino_real="$(cd "$destino" 2>/dev/null && pwd -P)"
home_real="$(cd "$HOME" 2>/dev/null && pwd -P)"

if [ -z "$destino_real" ]; then
  echo "capture-payloads: el destino no existe o no se puede entrar: $destino" >&2
  exit 2
fi

case "$destino_real" in
  "$home_real"|"$home_real"/.claude*|"$home_real"/.zcode*|"$home_real"/.grok*)
    echo "capture-payloads: me niego a tocar el perfil real." >&2
    echo "                  pedido: $destino" >&2
    echo "                  resuelve a: $destino_real" >&2
    echo "                  La captura va en un repo descartable, no donde vive el gate/config." >&2
    exit 2
    ;;
esac

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
capturador="$aqui/capture-payloads.sh"

# H2: identificador del destino para el user-config COMPARTIDO de zcode.
# Es un NUMERO a proposito (cksum del path fisico), no el path: se pasa a jq por
# --arg, y jq.exe es nativo, asi que MSYS convertiria un path POSIX a forma
# Windows y el match fallaria en silencio -- la misma trampa que el caso z1
# documenta al extraer el dest DESDE jq en vez de pasarselo. Un numero no se
# convierte. Limite declarado: dos destinos que resuelvan al mismo `pwd -P`
# siguen colisionando; no es alcanzable en la practica y no se cubre.
dest_id="$(printf '%s' "$destino_real" | cksum | cut -d' ' -f1)"

# ---------------- filtros jq para el user-config de zcode (idempotentes) ----
# has_tag/add_unless: appendean una entrada solo si su tag no esta ya presente
# (idempotencia por entrada, no por conteo). ours/strip: --quitar saca solo lo
# que lleva el marker de propiedad `saikit-capture-id 5.1`, deja los ajenos.
# El regex usa 5[.]1 (punto literal) en vez de 5\.1 para no mezclar escapes de
# bash y de jq: una sola capa, sin backslashes.
JQ_INSTALL='
def mine: (.command // "") | contains("--saikit-dest " + $destid + " ");
def has_tag(ev; t):
  any( (.hooks.events[ev] // [])[] ;
       any( (.hooks // [])[] ; (mine and ((.command // "") | test("saikit-capture-id 5[.]1.*--tag " + t + "$"))) ) );
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
def ours: any((.hooks // [])[];
  (((.command // "") | test("saikit-capture-id 5[.]1"))
   and ((.command // "") | contains("--saikit-dest " + $destid + " "))));
def strip(arr): ((arr // []) | map(select(ours | not)));
if ((.hooks // {}) | has("events")) then
  .hooks.events.UserPromptSubmit = strip(.hooks.events.UserPromptSubmit)
  | .hooks.events.PostToolUse = strip(.hooks.events.PostToolUse)
  | .hooks.events.Stop = strip(.hooks.events.Stop)
else . end
'

# Resolver un bash.exe de Windows para los comandos registrados (user-config
# de zcode; JSON de grok, cuyo runner spawnea powershell.exe — Task 7.1).
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
  printf '"%s" "%s" --saikit-capture-id 5.1 --saikit-dest %s --only-cwd "%s" --capture-dir "%s" --tag %s' \
    "$1" "$capturador" "$dest_id" "$destino_real" "$destino_real/capturas" "$2"
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
          --arg tools_cmd "$cmd_tools" --arg stop_cmd "$cmd_stop" \
          --arg destid "$dest_id" "$JQ_INSTALL" \
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

  # Hallazgo 4 (revision cruzada kimi, 2026-08-13): estas dos cuentas grepeaban
  # `saikit-capture-id 5.1` sobre el config ENTERO, que es compartido, asi que
  # el resumen sumaba los destinos ajenos y mentia justo en el caso multi-repo
  # que el fix H2 acaba de arreglar. Se cuenta por destino, con el mismo
  # identificador que decide el borrado. Misma familia que el unknown publicado
  # como PASS de la Task 1.5: el defecto estaba en el REPORTE, no en la accion.
  n_antes="$(grep -c -- "saikit-dest $dest_id " "$user_config" 2>/dev/null || true)"
  tmp_new="$(mktemp)" || exit 2
  if ! jq --arg destid "$dest_id" "$JQ_QUITAR" "$user_config" > "$tmp_new"; then
    echo "capture-payloads: jq fallo al quitar; el config queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$user_config" || {
    echo "capture-payloads: no pude escribir $user_config" >&2; exit 2; }
  n_despues="$(grep -c -- "saikit-dest $dest_id " "$user_config" 2>/dev/null || true)"
  rm -f "$marca"
  echo "Quitadas entradas de captura (saikit-capture-id 5.1) de $user_config"
  echo "  antes: $n_antes   despues: $n_despues   (los hooks ajenos quedan intactos)"
}

# ------------------------------------------------------ Task 6.1: codex ----
# En codex la captura es COLOCACION DE ARCHIVO, no mutacion de config, y esa es
# la diferencia entera con zcode. Medido: ~/.codex/hooks/summonaikit-harness.ps1
# resuelve su hook con `git rev-parse --show-toplevel` y PREFIERE
# <repo>/.codex/hooks/summonaikit-harness.sh cuando existe. Entonces alcanza con
# dejar el shim ahi: el registro de ~/.codex/hooks.json, que ya cubre las 3
# fases, lo invoca solo. El config del operador no se toca en ningun momento —
# su cksum es parte de la evidencia de la tarea. Tampoco hace falta jq.
codex_shim_path() { printf '%s/.codex/hooks/summonaikit-harness.sh' "$destino_real"; }

codex_install() {
  local shim
  # Hallazgo 2 (revision cruzada kimi, 2026-08-13): `git rev-parse` falla IGUAL
  # si git no esta instalado que si el directorio no es un repo, y el mensaje
  # de abajo acusaba al destino. Core Rule 2 en chiquito: no se afirma ausencia
  # de lo que no se pudo mirar. Se separan los dos casos antes de preguntar.
  command -v git >/dev/null 2>&1 || {
    echo "capture-payloads: no encontre git en el PATH." >&2
    echo "                  No se pudo determinar si el destino es un repo: eso es 'no se pudo mirar'," >&2
    echo "                  no 'se miro y no lo es'. El destino queda intacto." >&2
    exit 2; }
  ( cd "$destino_real" && git rev-parse --show-toplevel >/dev/null 2>&1 ) || {
    echo "capture-payloads: el destino tiene que ser un repo git." >&2
    echo "                  El .ps1 de codex resuelve su hook con git rev-parse --show-toplevel;" >&2
    echo "                  sin repo el shim queda puesto y NO corre nunca: una captura que miente." >&2
    exit 2; }
  shim="$(codex_shim_path)"
  if [ -e "$shim" ] && ! grep -q -- '--saikit-capture-id 6.1' "$shim" 2>/dev/null; then
    echo "capture-payloads: $shim existe y no lo escribi yo — no lo toco." >&2
    exit 2; fi
  umask 077
  mkdir -p "$(dirname "$shim")" 2>/dev/null || exit 2
  # Las capturas se crean ya ignoradas, antes del primer payload (mismo motivo
  # que en el camino Claude: si no, el .gitignore llega despues del archivo con
  # el contenido del turno).
  mkdir -p "$destino_real/capturas" 2>/dev/null || true
  printf '*\n' > "$destino_real/capturas/.gitignore" 2>/dev/null || true
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Shim de captura (Task 6.1), escrito por tools/capture-payloads.sh.\n'
    printf '# Lo invoca ~/.codex/hooks/summonaikit-harness.ps1, que prefiere esta ruta\n'
    printf '# sobre la del perfil cuando el cwd resuelve a un repo git.\n'
    printf '# La fase sale del ENV (el .ps1 la setea), no del payload: si codex no emite\n'
    printf '# hook_event_name, el capturador nombraria las 3 fases "sin-evento" y\n'
    printf '# colisionarian en un solo prefijo. El --tag es lo que las separa.\n'
    printf '#\n'
    printf '# Hallazgo 3 (revision cruzada kimi, 2026-08-13): el fail-open del modo hook\n'
    printf '# NO cubre a este shim. Si el repo que lo instalo se mueve o se borra, el\n'
    printf '# exec moria con 127 en CADA fase y rompia los turnos del host. El shim\n'
    printf '# tiene que ser fail-open por si mismo: si el capturador no esta, calla y sale 0.\n'
    printf '[ -f "%s" ] || exit 0\n' "$capturador"
    printf 'exec bash "%s" \\\n' "$capturador"
    printf '  --saikit-capture-id 6.1 \\\n'
    printf '  --tag "${SUMMONAIKIT_HOOK_PHASE:-sin-fase}" \\\n'
    printf '  --capture-dir "%s/capturas" \\\n' "$destino_real"
    printf '  --only-cwd "%s"\n' "$destino_real"
  } > "$shim" || { echo "capture-payloads: no pude escribir $shim" >&2; exit 2; }
  bash -n "$shim" 2>/dev/null || {
    echo "capture-payloads: el shim generado no parsea; lo saco antes de que rompa un turno" >&2
    rm -f "$shim"; exit 2; }
  echo "Shim de captura en $shim"
  echo "  ~/.codex/hooks.json NO se toco: el .ps1 ya prefiere esta ruta."
  echo "Ahora: sesion NUEVA de codex en $destino_real, turno -saikit que delegue + un bash."
  echo "Los payloads caen en $destino_real/capturas/"
}

codex_quitar() {
  local shim
  shim="$(codex_shim_path)"
  if [ ! -e "$shim" ]; then
    echo "No hay shim de captura en $shim (nada que quitar)"
    return 0
  fi
  grep -q -- '--saikit-capture-id 6.1' "$shim" 2>/dev/null || {
    echo "capture-payloads: $shim no lo escribi yo — no lo borro." >&2
    exit 2; }
  rm -f "$shim" || { echo "capture-payloads: no pude borrar $shim" >&2; exit 2; }
  echo "Shim de captura quitado de $shim"
}

# ------------------------------------------------------ Task 7.1: grok ----
# Grok SI corre hooks de proyecto (<repo>/.grok/hooks/*.json) tras el trust del
# folder — el override que zcode no tenia. Entonces la captura es colocacion de
# archivo, como codex, pero con DOS archivos propios: el JSON de registro y la
# marca. El JSON lo escribe este script ENTERO (no es append a un archivo
# ajeno): si existe y no lleva el capture-id 7.1, se planta sin tocarlo.
#
# Dos decisiones deliberadas, ambas al servicio de las preguntas de la 7.1:
#
# 1) Cada handler lleva "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" }. Claude no
#    propaga el prefijo VAR=val del comando (A10); el env map de Grok es de
#    primer nivel en el handler (doc). Si llega de verdad al proceso del hook
#    es una de las 11 preguntas — por eso va en TODOS los handlers.
#
# 2) PostToolUse se registra TRES veces con --tag distinto: matcher estilo
#    Claude (Bash|Edit|Write|Task), matcher con los nombres nativos
#    (run_terminal_command|search_replace|spawn_subagent) y SIN matcher. Si solo
#    dispara la nativa, el alias NO expande; si disparan alias y nativa, si; si
#    solo la sin-matcher, ninguna de las dos matchea. La 6.1 dejo esa
#    distincion en unknown por no registrar la variante a tiempo — no dos veces.
grok_json_path() { printf '%s/.grok/hooks/saikit-capture.json' "$destino_real"; }
grok_marca()     { printf '%s/.grok/.capture-payloads-owned' "$destino_real"; }

# Escape minimo para meter un string dentro de JSON (los comandos llevan
# comillas alrededor de las rutas con espacios, como bash.exe en Program Files).
grok_json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Comando de hook para una tag. MEDIDO (Task 7.1, probe de 4 formas de comando):
# en Windows Grok 1.0.3 corre los commands con powershell.exe (lo logea:
# `xai_grok_config::shell: Windows shell: powershell.exe`). Consecuencias:
#   - `"C:/.../bash.exe" "script" args` (forma zcode) NO parsea: en PowerShell un
#     string quoted es una expresion, no una invocacion — exit 1 sin correr nada.
#   - `bash -c '...'` funciona pero depende de que `bash` resuelva en el PATH.
#   - La forma que invoca al bash.exe correcto SIN depender del PATH es el call
#     operator: `& "<bash.exe>" "<script>" args`.
# --only-cwd contiene por si el trust del folder sobrevive a la captura: fuera
# del descartable el hook calla.
grok_hook_cmd() {  # $1=bash_win  $2=tag
  printf '& "%s" "%s" --saikit-capture-id 7.1 --only-cwd "%s" --capture-dir "%s" --tag %s' \
    "$1" "$capturador" "$destino_real" "$destino_real/capturas" "$2"
}

grok_install() {
  local json marca bash_win
  json="$(grok_json_path)"
  marca="$(grok_marca)"
  bash_win="$(zcode_bash_win)" || {
    echo "capture-payloads: no encontre un bash.exe de Windows para registrar el hook" >&2
    exit 2; }
  if [ -e "$json" ] && ! grep -q -- '--saikit-capture-id 7.1' "$json" 2>/dev/null; then
    echo "capture-payloads: $json existe y no lo escribi yo — no lo toco." >&2
    exit 2; fi
  umask 077
  mkdir -p "$(dirname "$json")" || exit 2
  # Las capturas se crean ya ignoradas, antes del primer payload (mismo motivo
  # que en los otros hosts: si no, el .gitignore llega despues del archivo con
  # el contenido del turno).
  mkdir -p "$destino_real/capturas" 2>/dev/null || true
  printf '*\n' > "$destino_real/capturas/.gitignore" 2>/dev/null || true

  local c_ups c_ptu_alias c_ptu_native c_ptu_all c_ptuf c_sub c_stop
  c_ups="$(grok_json_esc "$(grok_hook_cmd "$bash_win" ups)")"
  c_ptu_alias="$(grok_json_esc "$(grok_hook_cmd "$bash_win" ptu-alias)")"
  c_ptu_native="$(grok_json_esc "$(grok_hook_cmd "$bash_win" ptu-native)")"
  c_ptu_all="$(grok_json_esc "$(grok_hook_cmd "$bash_win" ptu-all)")"
  c_ptuf="$(grok_json_esc "$(grok_hook_cmd "$bash_win" ptuf)")"
  c_sub="$(grok_json_esc "$(grok_hook_cmd "$bash_win" sub)")"
  c_stop="$(grok_json_esc "$(grok_hook_cmd "$bash_win" stop)")"

  cat > "$json" <<JSON
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "$c_ups", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash|Edit|Write|Task",
        "hooks": [ { "type": "command", "command": "$c_ptu_alias", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] },
      { "matcher": "run_terminal_command|search_replace|spawn_subagent",
        "hooks": [ { "type": "command", "command": "$c_ptu_native", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] },
      { "hooks": [ { "type": "command", "command": "$c_ptu_all", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] }
    ],
    "PostToolUseFailure": [
      { "hooks": [ { "type": "command", "command": "$c_ptuf", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] }
    ],
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "$c_sub", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$c_stop", "timeout": 15,
                     "env": { "SUMMONAIKIT_HOOK_TARGET": "grok" } } ] }
    ]
  }
}
JSON

  # Red de seguridad: un JSON que no parsea dejaria el registro roto en un repo
  # donde Grok lo va a leer en cada turno. Se valida si hay jq; si no hay, la
  # plantilla es fija y el test la valida en el sandbox.
  if command -v jq >/dev/null 2>&1 && ! jq -e . "$json" >/dev/null 2>&1; then
    echo "capture-payloads: el JSON generado no parsea; lo saco antes de que rompa un turno" >&2
    rm -f "$json"; exit 2
  fi
  printf 'owner=tools/capture-payloads.sh\nhost=grok\ntask=7.1\ncwd=%s\ninstalled=%s\n' \
    "$destino_real" "$(date +%Y%m%d-%H%M%S)" > "$marca" || exit 2
  echo "Registro de captura en $json"
  echo "  7 entradas con --saikit-capture-id 7.1: UPS, PostToolUse x3 (alias/nativo/sin-matcher),"
  echo "  PostToolUseFailure, SubagentStart, Stop. Todas con env SUMMONAIKIT_HOOK_TARGET=grok."
  echo "  Repo descartable: $destino_real (capturas en $destino_real/capturas/)"
  echo "  Falta el trust del folder (grok: /hooks-trust o trusted_folders.toml) y una sesion NUEVA."
}

grok_quitar() {
  local json marca
  json="$(grok_json_path)"
  marca="$(grok_marca)"
  [ -f "$marca" ] || {
    echo "capture-payloads: no hay marca de captura grok en $marca (nada que quitar)" >&2
    exit 2; }
  if [ -e "$json" ]; then
    grep -q -- '--saikit-capture-id 7.1' "$json" 2>/dev/null || {
      echo "capture-payloads: $json ya no lleva el capture-id 7.1 — no lo borro." >&2
      echo "                  Alguien lo cambio despues del install; revisarlo a mano." >&2
      exit 2; }
    rm -f "$json" || { echo "capture-payloads: no pude borrar $json" >&2; exit 2; }
  fi
  rm -f "$marca"
  echo "Quitado el registro de captura grok ($json) y la marca."
  echo "  Las capturas quedan en $destino_real/capturas/ (no se borran: son la evidencia)."
}

case "$modo" in
  instalar)
    if [ "$host" = "zcode" ]; then
      zcode_install
    elif [ "$host" = "codex" ]; then
      codex_install
    elif [ "$host" = "grok" ]; then
      grok_install
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
    # Inferir el host si no se paso --host: la marca de cada host lo dice
    # (.zcode => zcode, .grok => grok; codex no tiene marca, usa --host).
    if [ "$host" = "claude" ] && [ -f "$destino_real/.zcode/.capture-payloads-owned" ]; then
      host="zcode"
    fi
    if [ "$host" = "claude" ] && [ -f "$destino_real/.grok/.capture-payloads-owned" ]; then
      host="grok"
    fi
    if [ "$host" = "zcode" ]; then
      zcode_quitar
    elif [ "$host" = "codex" ]; then
      codex_quitar
    elif [ "$host" = "grok" ]; then
      grok_quitar
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
