#!/usr/bin/env bash
# check-hook-registration.sh — verifica que el hook siga REGISTRADO.
#
# El modo de falla mas silencioso del sistema: `settings.json` deja de apuntar
# al hook. El archivo puede estar intacto, con su marcador y su contenido
# correcto, y el gate simplemente no existir. Todo lo demas que hay verifica
# CONTENIDO; esto verifica el REGISTRO.
#
# Contrato de salida (Core Rule 1, fail-open): SIEMPRE exit 0. Corre en
# SessionStart y un verificador que rompe el arranque es peor que no tenerlo.
# El resultado se comunica por texto, no por exit code.
#
# Core Rule 2 (`not_observed != absent`): si el settings no se puede leer o
# parsear, se reporta `unknown`. NUNCA se afirma que el registro falta a partir
# de no haberlo podido mirar — seria exactamente la alarma falsa que haria que
# el operador deje de creerle al aviso.
#
# Uso:
#   bash tools/check-hook-registration.sh
#   bash tools/check-hook-registration.sh --settings <path> [--local-settings <path>]
#   bash tools/check-hook-registration.sh --zcode-config <user-config>   (Task 5.4)
#   bash tools/check-hook-registration.sh --codex-hooks-json <hooks.json> (Task 6.5)
#   bash tools/check-hook-registration.sh --grok-hooks-dir <dir>         (Task 7.5)
#   bash tools/check-hook-registration.sh --dsh-home <dir>               (Phase 15)
set -u

HOOK_NAME='summonaikit-harness.sh'
SETTINGS="${HOME:-}/.claude/settings.json"
LOCAL_SETTINGS=''
# Task 5.4: la SEGUNDA forma de registro (hooks.events.*) vive en el user-config
# de zcode y es mutuamente exclusiva con --settings. VIO_* detecta si el operador
# paso uno, el otro o ambos (ambos => unknown, fail-open: corre en SessionStart).
ZCODE_USER_CONFIG=''
VIO_CLAUDE=0
VIO_ZCODE=0
# Task 6.5: la TERCERA forma. En Codex el registro (hooks.json) nombra al
# WRAPPER (.ps1) y el wrapper nombra al hook: la afirmacion se vuelve indirecta
# y se parte en DOS separadas — (a) el registro nombra al wrapper; (b) el
# wrapper existe y nombra al hook — porque colapsarlas esconderia cual de las
# dos se rompio.
CODEX_HOOKS_JSON=''
CODEX_WRAPPER=''
VIO_CODEX=0
# Task 7.5: la CUARTA forma. En Grok el registro es un JSON propio
# (<dir>/summonaikit.json) cuyo command nombra al hook DIRECTAMENTE en forma
# PowerShell ('& "bash.exe" "hook"'). Tres afirmaciones separadas: (1) el JSON
# nombra al hook en una linea que no solo imprima; (2) el hook que nombra
# existe y lleva el marcador de linea 2; (3) el matcher de PostToolUse cubre
# spawn_subagent o su alias Task (7.1 midio ambos nombres).
GROK_HOOKS_DIR=''
VIO_GROK=0
# Phase 15: la QINTA forma. dsh no se registra por archivo de hooks: el plugin
# se compone en <dsh-home>/cordis.patch.yml entre marcas propias. El verificador
# de dsh hace afirmaciones sobre el HOOK (existe + marcador), el DIR del plugin
# (4 archivos) y la ENTRADA del patch (bloque entre marcas con el hook: y las 4
# personas subagent_<rol>). --bash es la ruta del bash.exe para leer el hook.
DSH_HOME=''
DSH_BASH=''
VIO_DSH=0

reportar() { printf '%s\n' "$*"; }

# Un flag sin valor hacia fallar `shift 2` SIN consumir nada, y el `while`
# giraba para siempre: medido con `timeout`, rc=124 (Task 0.4). No era un exit
# code equivocado — era un cuelgue, en un script que corre en cada SessionStart.
#
# Se sale con 0 y no con error a proposito: el contrato de este archivo es salir
# 0 SIEMPRE (fail-open, Core Rule 1) y comunicar por texto, y sus dos llamadores
# —el instalador y el heal— lo asumen. Una invocacion que no se pudo atender es
# exactamente `unknown`: no se miro nada, y no se afirma nada.
while [ $# -gt 0 ]; do
  case "$1" in
    --settings|--local-settings|--hook-name|--zcode-config|--codex-hooks-json|--codex-wrapper|--grok-hooks-dir|--dsh-home|--bash)
      if [ $# -lt 2 ]; then
        reportar "[summonaikit] REGISTRO DEL HOOK: unknown — falta el valor de $1; no se verifico nada."
        reportar "              No se afirma que el registro falte: no se pudo mirar."
        exit 0
      fi
      case "$1" in
        --settings)        SETTINGS="$2"; VIO_CLAUDE=1 ;;
        --local-settings)  LOCAL_SETTINGS="$2" ;;
        --hook-name)       HOOK_NAME="$2" ;;
        --zcode-config)    ZCODE_USER_CONFIG="$2"; VIO_ZCODE=1 ;;
        --codex-hooks-json) CODEX_HOOKS_JSON="$2"; VIO_CODEX=1 ;;
        --codex-wrapper)   CODEX_WRAPPER="$2" ;;
        --grok-hooks-dir)  GROK_HOOKS_DIR="$2"; VIO_GROK=1 ;;
        --dsh-home)        DSH_HOME="$2"; VIO_DSH=1 ;;
        --bash)            DSH_BASH="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)        sed -n '2,22p' "$0"; exit 0 ;;
    *)                shift ;;
  esac
done

# Task 5.4: --zcode-config y --settings son mutuamente excluyentes (cada host
# registra en su propio archivo). Mezclarlos no tiene sentido y leer la forma
# equivocada daria silencio o INCOMPLETO falsos. Fail-open: unknown, exit 0.
# Task 7.5: --grok-hooks-dir entra en la misma regla. Phase 15: --dsh-home igual.
if [ $((VIO_CLAUDE + VIO_ZCODE + VIO_CODEX + VIO_GROK + VIO_DSH)) -gt 1 ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — --settings, --zcode-config, --codex-hooks-json, --grok-hooks-dir y --dsh-home son mutuamente excluyentes."
  reportar "              Cada host registra en su propio archivo; no se verifico nada."
  reportar "              No se afirma que el registro falte: no se pudo mirar."
  exit 0
fi
MODO="claude"
if [ "$VIO_ZCODE" -gt 0 ]; then
  MODO="zcode"
  SETTINGS="$ZCODE_USER_CONFIG"
  LOCAL_SETTINGS=''
fi
# Task 6.5 (modo codex): el archivo que se lee es hooks.json (misma forma
# hooks.<Fase> que Claude, medido en el registro vivo) y lo que se busca en los
# commands es el WRAPPER, no el hook. El wrapper por defecto es el que la
# cadena real usa: <dir del hooks.json>/hooks/summonaikit-harness.ps1.
if [ "$VIO_CODEX" -gt 0 ]; then
  MODO="codex"
  SETTINGS="$CODEX_HOOKS_JSON"
  LOCAL_SETTINGS=''
  [ -n "$CODEX_WRAPPER" ] || CODEX_WRAPPER="$(dirname "$CODEX_HOOKS_JSON")/hooks/summonaikit-harness.ps1"
  HOOK_NAME="$(basename "$CODEX_WRAPPER")"
fi
# Task 7.5 (modo grok): el archivo que se lee es summonaikit.json dentro del
# dir de hooks; sin flag, el default del perfil (~/.grok/hooks). El command
# nombra al hook directamente — no hay wrapper intermedio como en codex — asi
# que la segunda afirmacion mira al propio hook (existencia + marcador).
if [ "$VIO_GROK" -gt 0 ]; then
  MODO="grok"
  [ -n "$GROK_HOOKS_DIR" ] || GROK_HOOKS_DIR="${HOME:-}/.grok/hooks"
  SETTINGS="$GROK_HOOKS_DIR/summonaikit.json"
  LOCAL_SETTINGS=''
fi

# Phase 15 (modo dsh): el plugin se compone en <dsh-home>/cordis.patch.yml entre
# marcas; no hay archivo de hooks/proxy que parsear con python. Se verifica con
# una rama propia (no el parser de settings de abajo, que es de la forma claude).
# Contrato de salida identico: SIEMPRE exit 0 (fail-open), reporta por texto.
parch_dsh() {
  [ "$VIO_DSH" -gt 0 ] || return 0
  local home="${DSH_HOME:-${HOME:-}/.dsh}" hook ddir patch hook_win
  local p_start p_end bloque rol n_roles rebanada falla=0
  hook="$home/hooks/summonaikit-harness.sh"
  ddir="$home/profiles/node_modules/@summonaikit/dsh-gate"
  patch="$home/cordis.patch.yml"
  # El instalador escribe hook: en forma WINDOWS (C:/...), porque dsh (Node)
  # lee la config del plugin; el name: es el NOMBRE del paquete (@summonaikit/
  # dsh-gate), no una ruta. El hook existe en la ruta nativa ($home, MSYS /c/...);
  # para comparar hook: se usa la forma Windows. (PR #91: el turno vivo revelo
  # que el name: por ruta C:/... no lo importa dsh, y que /c/ no coincidia.)
  hook_win="$(printf '%s' "$home/hooks/summonaikit-harness.sh")"
  if command -v cygpath >/dev/null 2>&1; then
    case "$hook_win" in
      [A-Za-z]:/*) : ;;                    # ya es Windows con barra adelante
      [A-Za-z]:\\*) hook_win="$(printf '%s' "$hook_win" | sed 's|\\|/|g')" ;;
      *) hook_win="$(cygpath -m "$hook" 2>/dev/null || printf '%s' "$hook")" ;;
    esac
  fi
  # 1) Hook existe y lleva el marcador de linea 2.
  if [ ! -e "$hook" ]; then
    reportar "[summonaikit] HOOK DE DSH: no existe ($hook)."
    falla=1
  elif [ ! -f "$hook" ] || [ ! -r "$hook" ]; then
    reportar "[summonaikit] HOOK DE DSH: unknown — existe pero no se pudo leer ($hook)."
  elif ! sed -n '2p' "$hook" | grep -Eq '^# SAIKIT-CLAUDE-OWNED summonaikit-claude [^[:space:]]+$'; then
    reportar "[summonaikit] HOOK DE DSH: no lleva el marcador de propiedad en la linea 2 ($hook)."
    falla=1
  fi
  # 2) El dir del plugin tiene los 4 archivos que el patch declara.
  for f in index.js translate.js spawn-hook.js package.json; do
    if [ ! -e "$ddir/$f" ]; then
      reportar "[summonaikit] PLUGIN DE DSH: falta $f ($ddir/$f)."
      falla=1
    fi
  done
  # 3) El patch del profile lleva el bloque entre marcas con el id del gate, el
  #    name: del plugin, hook: apuntando al hook, bash: presente, y las 4
  #    personas distinctas subagent_<rol> (cada una con nombre, toolName y
  #    persona:). M2/CODE (HIGH codex+glm r1 PR #88): antes solo contaba lineas
  #    `toolName: subagent_`, lo que pasaba con 4 veces el mismo rol, sin \
  #    id:/name:/bash:, o con un bloque que YAML no aplicaria.
  if [ ! -e "$patch" ]; then
    reportar "[summonaikit] PATCH DE DSH: no existe ($patch)."
    falla=1
  elif [ ! -r "$patch" ]; then
    reportar "[summonaikit] PATCH DE DSH: unknown — no se pudo leer ($patch)."
  else
    p_start="$(grep -n '^# >>> summonaikit-gate START' "$patch" | head -1 | cut -d: -f1)"
    p_end="$(grep -n '^# <<< summonaikit-gate END' "$patch" | head -1 | cut -d: -f1)"
    if [ -z "$p_start" ] || [ -z "$p_end" ] || [ "$p_end" -le "$p_start" ]; then
      reportar "[summonaikit] PATCH DE DSH: falta la entrada entre marcas summonaikit-gate ($patch)."
      falla=1
    else
      bloque="$(sed -n "${p_start},${p_end}p" "$patch")"
      printf '%s' "$bloque" | grep -q "id: summonaikit-gate" || {
        reportar "[summonaikit] PATCH DE DSH: falta el id: summonaikit-gate ($patch)."; falla=1; }
      printf '%s' "$bloque" | grep -qF "name: '@summonaikit/dsh-gate'" || {
        reportar "[summonaikit] PATCH DE DSH: el name: no es el paquete del plugin (@summonaikit/dsh-gate)."; falla=1; }
      printf '%s' "$bloque" | grep -qF "hook: '$hook_win'" || {
        reportar "[summonaikit] PATCH DE DSH: la entrada no apunta al hook ($hook_win)."; falla=1; }
      printf '%s' "$bloque" | grep -qE 'bash: ' || {
        reportar "[summonaikit] PATCH DE DSH: falta la config bash: del plugin."; falla=1; }
      # Cada rol: un bloque `- id: subagent_<rol>` con name:, toolName: y persona:
      # PROPIOS. Se recorta la rebanada del rol (hasta el proximo '- id:' o la
      # marca END) para no cruzar personas de otros roles (M2/qwen r1 PR #88):
      # antes se gripeaba todo el bloque, asi que UNA persona bastaba para los 4.
      for rol in implementer verifier reviewer adversary; do
        # rebanada = lineas desde `- id: subagent_<rol>` hasta la siguiente
        # `- id:` (o el final del bloque). awk con estado: dentro=1 al ver el id
        # del rol; se corta en la siguiente linea con el patron `- id:`.
        rebanada="$(printf '%s' "$bloque" | awk -v r="$rol" '
          /^[[:space:]]*-[[:space:]]id: subagent_/ {
            if (dentro) exit                 # siguiente id del rol => fin de esta rebanada
            if ($0 ~ ("subagent_" r "$")) dentro=1   # es EL rol buscado
            next
          }
          /^[[:space:]]*-[[:space:]]id: / { if (dentro) exit; next }
          dentro { print }
        ')"
        # Conteo de apariciones del id del rol (para detectar duplicados).
        n_roles="$(printf '%s' "$bloque" | grep -c "^[[:space:]]*-[[:space:]]id: subagent_$rol$")"
        if [ "$n_roles" -eq 0 ]; then
          reportar "[summonaikit] PATCH DE DSH: falta la persona subagent_$rol."; falla=1; continue
        fi
        if [ "$n_roles" -gt 1 ]; then
          reportar "[summonaikit] PATCH DE DSH: subagent_$rol duplicado ($n_roles veces)."; falla=1; continue
        fi
        if [ -z "$rebanada" ]; then
          reportar "[summonaikit] PATCH DE DSH: bloque de subagent_$rol vacio."; falla=1; continue
        fi
        printf '%s' "$rebanada" | grep -qE "name: '@deepseek-ai/dsh-tool-subagent'" || {
          reportar "[summonaikit] PATCH DE DSH: subagent_$rol sin name: dsh-tool-subagent."; falla=1; }
        printf '%s' "$rebanada" | grep -qE "toolName: subagent_$rol" || {
          reportar "[summonaikit] PATCH DE DSH: subagent_$rol sin toolName."; falla=1; }
        printf '%s' "$rebanada" | grep -q "persona: |-" || {
          reportar "[summonaikit] PATCH DE DSH: subagent_$rol sin persona."; falla=1; }
      done
    fi
  fi
  return 0
}
if [ "$VIO_DSH" -gt 0 ]; then
  parch_dsh
  exit 0
fi

# El local por defecto es HERMANO del settings dado, no el del HOME real: si no,
# apuntar `--settings` a un fixture igual leeria el settings.local.json de
# verdad (Core Rule 4). En modo zcode no hay local (un solo user-config).
if [ "$MODO" = "claude" ] && [ -z "$LOCAL_SETTINGS" ]; then
  LOCAL_SETTINGS="$(dirname "$SETTINGS")/settings.local.json"
fi

python_bin=''
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then python_bin="$c"; break; fi
done

if [ -z "$python_bin" ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — no hay interprete python para leer el settings."
  reportar "              No se afirma que el registro falte: no se pudo mirar."
  exit 0
fi

resultado="$("$python_bin" - "$SETTINGS" "$LOCAL_SETTINGS" "$HOOK_NAME" "$MODO" <<'PY' 2>/dev/null
import json, re, shlex, sys

settings, local, hook = sys.argv[1], sys.argv[2], sys.argv[3]
modo = sys.argv[4] if len(sys.argv) > 4 else "claude"

# Nombrar el hook no es ejecutarlo: `echo summonaikit-harness.sh` contaba como
# registro y el verificador callaba aunque el gate no corriera en ninguna fase
# (Task 0.4). Se descarta el comando cuyo programa solo IMPRIME.
#
# Limite declarado: esto NO parsea shell. Lo que este archivo verifica es el
# REGISTRO —que el settings nombre el hook donde corresponde—, no que el
# comando vaya a ejecutarlo de verdad; un comando suficientemente retorcido que
# lo mencione sin correrlo puede seguir contando. Cubrir eso pedia interpretar
# shell, que es mas riesgo del que evita.
SOLO_IMPRIMEN = {"echo", "printf", "true", "false", ":", "#", "rem"}
ASIGNACION = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

def ejecuta(comando, hook):
    if hook not in comando:
        return False
    # Por SEGMENTO, no por comando entero: mirar solo el primer token dejaba
    # `echo algo && bash .../summonaikit-harness.sh` como NO registrado, que es
    # la direccion peligrosa del error — una alarma falsa en cada SessionStart
    # sobre un registro que si existe. Basta con que UN segmento lo ejecute.
    segmentos = re.split(r"&&|\|\||;|\|", comando)
    return any(_segmento_ejecuta(s, hook) for s in segmentos)


def _segmento_ejecuta(segmento, hook):
    if hook not in segmento:
        return False
    try:
        tokens = shlex.split(segmento, posix=True)
    except ValueError:
        # Comillas sin cerrar: no se pudo tokenizar. Se cuenta igual, que es la
        # postura de siempre — ante lo que no se pudo mirar, no se acusa.
        return True
    i = 0
    while i < len(tokens) and ASIGNACION.match(tokens[i]):
        i += 1
    if i >= len(tokens):
        return True
    programa = tokens[i].replace("\\", "/").rsplit("/", 1)[-1].lower()
    return programa not in SOLO_IMPRIMEN
# Las fases que el gate necesita para funcionar. Si falta cualquiera, el hook
# existe pero deja de correr en ese punto del turno.
ESPERADAS = ["UserPromptSubmit", "PostToolUse", "Stop"]

# Matcher de PostToolUse (Task 3.7 / CORRECCION 2): un subagente que solo use
# herramientas fuera del matcher (Read/Grep/Glob) no genera ningun evento para
# el gate y su rol no se registra, aunque haya corrido. El verificador REPORTA
# si el matcher no cubre la herramienta de delegacion (`Agent`); no edita el
# registro (la via de arreglarlo es settings.json, fuera de este tool).
def _matcher_cubre(m, modo):
    # PostToolUse sin matcher o "*" => pega a todo (cubre Agent). Cualquier otra
    # cosa se prueba como regex del host contra el literal "Agent". Si el regex
    # no compila => (no cubre, no compila) y arriba se vuelve `unknown`.
    if m is None or m == "" or m == "*":
        return (True, True)
    try:
        rx = re.compile(m)
    except re.error:
        return (False, False)
    # Task 7.5 (grok): la tool de delegacion es spawn_subagent y el matcher
    # 'Task' la atrapa por alias (7.1 midio AMBAS cosas: el despacho emitia
    # PostToolUse y ptu-alias='...|Task' disparo). Cubre cualquiera de las dos.
    if modo == "grok":
        if rx.search("spawn_subagent") is not None or rx.search("Task") is not None:
            return (True, True)
        return (False, True)
    if rx.search("Agent") is not None:
        return (True, True)
    # Task 5.4: en zcode el alias Task<->Agent (medido 5.1) hace que un matcher
    # 'Task' SI vea los eventos de la herramienta Agent. Asi 'Task' solo cubre y
    # no es alarma falsa. En Claude NO: ahi el matcher literal no tiene alias.
    if modo == "zcode" and rx.search("Task") is not None:
        return (True, True)
    return (False, True)

registradas, leidos, ilegibles = set(), [], []
# (matcher_str, cubre, compila) por cada grupo de PostToolUse que ejecuta el hook.
ptu_matchers = []
# Task 7.5 (grok): las rutas de hook que el JSON NOMBRA en commands que
# ejecutan. La afirmacion (b) las mira desde bash (existencia + marcador).
# Se extraen por regex y NO con shlex: en posix-mode shlex la barra invertida
# es escape y una ruta Windows ('C:\...\summonaikit-harness.sh') llegaria
# mangleada a la verificacion de existencia.
hook_paths = []

def _hook_paths(comando):
    # r2/CodeRabbit: la forma medida cita la ruta del hook ENTRE COMILLAS, y
    # una ruta con espacios ('C:/Users/John Doe/...') partida en el espacio
    # daria un falso 'NO existe'. Se extrae PRIMERO la porcion quoteda; el
    # fallback sin comillas cubre los commands estilo Claude.
    q = re.findall(r'"([^"]*summonaikit-harness\.sh)"', comando)
    if q:
        return q
    return re.findall(r'[^\s"&|;]+summonaikit-harness\.sh', comando)
# Task 5.4 (modo zcode): enabled != JSON true => los hooks de archivo no corren;
# y un matcher en el grupo de UserPromptSubmit/Stop es error (el match value ahi
# es texto/preview, no tool name). Solo se observan si el archivo se leyo.
enabled_mal = False
fases_con_matcher = []

for path in (settings, local):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        continue
    except Exception:
        ilegibles.append(path)
        continue
    leidos.append(path)
    hooks_root = data.get("hooks")
    if not isinstance(hooks_root, dict):
        continue
    if modo == "zcode":
        # hooks.enabled debe ser JSON true o los hooks de archivo no corren
        # (guia del CLI). Solo se afirma si el archivo se leyo: ilegible ya se
        # fue por la rama de arriba y arriba se reporta unknown, no esto.
        if hooks_root.get("enabled") is not True:
            enabled_mal = True
        events = hooks_root.get("events")
        iterable = events.items() if isinstance(events, dict) else []
    else:
        iterable = hooks_root.items()
    for fase, grupos in iterable:
        if not isinstance(grupos, list):
            continue
        for grupo in grupos:
            if not isinstance(grupo, dict):
                continue
            entrada_ejecuta = False
            for entrada in grupo.get("hooks", []) or []:
                if not isinstance(entrada, dict):
                    continue
                comando = str(entrada.get("command", ""))
                if ejecuta(comando, hook):
                    entrada_ejecuta = True
                    registradas.add(fase)
                    # Task 7.5: token que termina en el nombre del hook, sin
                    # comillas/operadores alrededor — la ruta que el registro
                    # nombra de verdad. Limites declarados: no expande $VARS
                    # ni resuelve relativos; con un command sano sobra.
                    if modo == "grok":
                        for tok in _hook_paths(comando):
                            if tok not in hook_paths:
                                hook_paths.append(tok)
            # El matcher vive en el GRUPO, no en la entrada. Solo importa para
            # PostToolUse y solo si el grupo ejecuta el hook. Task 6.5: en modo
            # codex el advisory de Agent NO aplica — 6.1 midio que el rol llega
            # por los eventos INTERNOS del subagente (que entran como Bash) y
            # que el despacho de spawn_agent quedo `unknown` (0 eventos, sin
            # distinguir "no emite" de "lo filtra el matcher"): un advisory
            # sobre eso seria una alarma sin medicion detras.
            if entrada_ejecuta and fase == "PostToolUse" and modo != "codex":
                m = grupo.get("matcher", "")
                if m is None:
                    m = ""
                cubre, compila = _matcher_cubre(m, modo)
                ptu_matchers.append((m, cubre, compila))
            # Task 5.4: en zcode, UPS/Stop con la clave 'matcher' presente (aun
            # vacia, r2.4) es el error que la DoD nombra: el match value ahi es
            # el texto del prompt / la preview, no el nombre de la herramienta.
            if entrada_ejecuta and modo == "zcode" and fase in ("UserPromptSubmit", "Stop"):
                if "matcher" in grupo:
                    fases_con_matcher.append(fase)

faltantes = [f for f in ESPERADAS if f not in registradas]

# Cobertura del matcher de Agent: solo se afirma si PostToolUse esta registrado
# y se observo al menos un grupo. Si PTU falta, el reporte de fase faltante ya
# lo cubre y no se apila un segundo diagnostico de matcher.
if "PostToolUse" in registradas and ptu_matchers:
    if any(c for _, c, _ in ptu_matchers):
        matcher_estado = "covered"
    elif all(k for _, _, k in ptu_matchers) and not ilegibles:
        matcher_estado = "uncovered"
    else:
        matcher_estado = "unknown"
else:
    matcher_estado = "sin-ptu"

# Task 10.6: SessionStart se afirma SEPARADO y NO entra en ESPERADAS. El gate
# funciona sin esa fase — lo unico que se pierde son las reglas permanentes, que
# son una mejora y no un requisito. Meterla en ESPERADAS haria que TODO install
# existente se reporte "INCOMPLETO — el gate NO corre", que es exactamente la
# alarma falsa que la Task 0.4 prohibe.
print(json.dumps({
    "session_registrada": ("SessionStart" in registradas),
    "faltantes": faltantes,
    "leidos": leidos,
    "ilegibles": ilegibles,
    "matcher_estado": matcher_estado,
    "matchers_obs": [m for m, _, _ in ptu_matchers],
    "enabled_mal": enabled_mal,
    "fases_con_matcher": sorted(set(fases_con_matcher)),
    "hook_paths": hook_paths,
}))
PY
)"

if [ -z "$resultado" ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — fallo el lector de settings."
  reportar "              No se afirma que el registro falte: no se pudo mirar."
  exit 0
fi

faltantes="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(" ".join(json.load(sys.stdin)["faltantes"]))' 2>/dev/null)"
leidos="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(len(json.load(sys.stdin)["leidos"]))' 2>/dev/null)"
ilegibles="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(" ".join(json.load(sys.stdin)["ilegibles"]))' 2>/dev/null)"
matcher_estado="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(json.load(sys.stdin).get("matcher_estado","sin-ptu"))' 2>/dev/null)"
matchers_obs="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(" ".join(json.load(sys.stdin).get("matchers_obs",[])))' 2>/dev/null)"
enabled_mal="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(json.load(sys.stdin).get("enabled_mal",False))' 2>/dev/null)"
fases_con_matcher="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(" ".join(json.load(sys.stdin).get("fases_con_matcher",[])))' 2>/dev/null)"
session_registrada="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print(json.load(sys.stdin).get("session_registrada",False))' 2>/dev/null)"
hook_paths="$(printf '%s' "$resultado" | "$python_bin" -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("hook_paths",[])))' 2>/dev/null)"

# Task 10.6 — afirmacion SEPARADA, y advisory: sin SessionStart el gate corre
# igual; lo que no llega son las reglas permanentes, que valen arme o no el
# turno. Solo aplica a Claude: es el unico host donde se MIDIO que esa fase
# acepta additionalContext y que el texto llega al modelo.
reportar_session_rules() {
  [ "$MODO" = "claude" ] || return 0
  [ "$session_registrada" = "True" ] && return 0
  reportar "[summonaikit] REGLAS PERMANENTES: SessionStart no esta registrado."
  reportar "              El gate NO depende de esto y sigue corriendo igual: lo que se pierde"
  reportar "              son las reglas que valen en toda sesion, arme o no el turno con -saikit."
  reportar "              Se arregla en settings.json: agregar el hook en SessionStart, sin matcher."
}

# Reporta el hueco del matcher de Agent cuando PostToolUse esta registrado pero
# su matcher no cubre 'Agent' (Task 3.7 / CORRECCION 2): un subagente read-only
# (Read/Grep/Glob) no generaria ningun evento para el gate. No edita el registro
# — la via de arreglarlo es settings.json, fuera de este tool. fail-open: exit 0.
reportar_matcher() {
  if [ "$matcher_estado" = "uncovered" ]; then
    if [ "$MODO" = "grok" ]; then
      # Task 7.5: en grok la delegacion es spawn_subagent (medido 7.1) y el
      # alias que la atrapa es Task; 'Agent' a secas no esta medido como alias
      # de nada en este host, asi que el aviso nombra los dos que cuentan.
      reportar "[summonaikit] REGISTRO DEL HOOK: el matcher de PostToolUse no cubre 'spawn_subagent' (ni su alias 'Task')."
      reportar "              matcher observado: ${matchers_obs:-(sin matcher)}"
      reportar "              Efecto: la delegacion de subagentes no genera eventos para el gate"
      reportar "              y el rol no se registra, aunque el subagente haya corrido."
      reportar "              Se arregla en summonaikit.json: agregar spawn_subagent o Task al matcher."
      return 0
    fi
    reportar "[summonaikit] REGISTRO DEL HOOK: el matcher de PostToolUse no cubre 'Agent'."
    reportar "              matcher observado: ${matchers_obs:-(sin matcher)}"
    reportar "              Efecto: un subagente que solo use herramientas fuera del matcher"
    reportar "              (Read/Grep/Glob) no genera ningun evento para el gate y su rol no"
    reportar "              se registra, aunque haya corrido. Se arregla en settings.json:"
    reportar "              agregar 'Agent' al matcher de PostToolUse."
  elif [ "$matcher_estado" = "unknown" ]; then
    reportar "[summonaikit] REGISTRO DEL HOOK: unknown — no se pudo determinar si el matcher"
    reportar "              de PostToolUse cubre 'Agent' (algun matcher no compila como regex o"
    reportar "              algun settings esta ilegible). No se afirma ausencia."
  fi
}

# Task 6.5 (modo codex) — la afirmacion (b), SEPARADA de (a): el wrapper existe
# y nombra al hook. Corre en todos los desenlaces de (a) porque es independiente:
# el registro puede estar perfecto con el wrapper roto, y al reves. Ausente es
# OBSERVADO (se afirma); ilegible es unknown (no se acusa).
reportar_wrapper_codex() {
  [ "$MODO" = "codex" ] || return 0
  if [ ! -e "$CODEX_WRAPPER" ]; then
    reportar "[summonaikit] WRAPPER DE CODEX: no existe ($CODEX_WRAPPER)."
    reportar "              La cadena es registro -> wrapper -> hook: el registro puede estar perfecto"
    reportar "              y el hook no correr igual. Afirmacion separada de la del registro a proposito."
    return 0
  fi
  if [ ! -f "$CODEX_WRAPPER" ] || [ ! -r "$CODEX_WRAPPER" ]; then
    reportar "[summonaikit] WRAPPER DE CODEX: unknown — existe pero no se pudo leer ($CODEX_WRAPPER)."
    reportar "              No se afirma que no nombre al hook: no se pudo mirar."
    return 0
  fi
  # Greptile P1 (PR #23): la mencion tiene que vivir en una LINEA DE CODIGO —
  # un wrapper viejo que solo la conserve en un comentario PowerShell (`#...`)
  # pasaba como valido y el checker callaba con la cadena rota. Mismo criterio
  # que la 0.4 en los settings: nombrar el hook no es ejecutarlo. Limite
  # declarado (el mismo que ejecuta() declara para shell): esto NO parsea
  # PowerShell — una mencion dentro de un string de diagnostico en una linea
  # de codigo sigue contando; cubrir eso pedia interpretar PowerShell, que es
  # mas riesgo del que evita.
  if ! grep -v '^[[:space:]]*#' "$CODEX_WRAPPER" | grep -q 'summonaikit-harness\.sh'; then
    reportar "[summonaikit] WRAPPER DE CODEX: existe pero NO nombra summonaikit-harness.sh en ninguna linea de codigo ($CODEX_WRAPPER)."
    reportar "              (Una mencion solo en comentarios no cuenta: nombrar el hook no es ejecutarlo.)"
    reportar "              El segundo eslabon de la cadena registro -> wrapper -> hook esta cortado."
  fi
}

# Task 7.5 (modo grok) — la afirmacion (2), SEPARADA de la (1): el hook que el
# JSON nombra EXISTE y lleva el marcador de la linea 2. Corre en todos los
# desenlaces de la (1) porque es independiente: el registro puede estar
# perfecto con el hook borrado, y al reves. Ausente es OBSERVADO (se afirma);
# ilegible es unknown (no se acusa). Si el JSON no se pudo leer, no hay rutas
# nombradas y esta afirmacion no dice nada (Core Rule 2).
reportar_hook_grok() {
  [ "$MODO" = "grok" ] || return 0
  [ -n "$hook_paths" ] || return 0
  local p p_norm
  # r2/CodeRabbit: la lista viaja separada por SALTOS DE LINEA y se itera con
  # read — un `for p in $hook_paths` la volveria a partir en los espacios y
  # una ruta 'C:/Users/John Doe/...' daria falsos 'NO existe'.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # La forma medida del command lleva la ruta con barras normales; una forma
    # Windows con backslashes se normaliza para poder mirarla desde bash.
    p_norm="$(printf '%s' "$p" | sed 's|\\|/|g')"
    if [ ! -e "$p_norm" ]; then
      reportar "[summonaikit] HOOK DE GROK: el JSON nombra $p y NO existe."
      reportar "              La cadena es JSON -> hook: el registro puede estar perfecto y el hook no correr."
      reportar "              Afirmacion separada del registro a proposito."
      continue
    fi
    if [ ! -f "$p_norm" ] || [ ! -r "$p_norm" ]; then
      reportar "[summonaikit] HOOK DE GROK: unknown — $p existe pero no se pudo leer."
      reportar "              No se afirma que le falte el marcador: no se pudo mirar."
      continue
    fi
    if ! sed -n '2p' "$p_norm" | grep -Eq '^# SAIKIT-CLAUDE-OWNED summonaikit-claude [^[:space:]]+$'; then
      reportar "[summonaikit] HOOK DE GROK: $p no lleva el marcador de propiedad en la linea 2."
      reportar "              Un hook que el instalador no reconoce como suyo no se repara ni se quita:"
      reportar "              revisarlo, y si es de otro, no instalar encima."
    fi
  done <<GROK_HOOK_PATHS
$hook_paths
GROK_HOOK_PATHS
  return 0
}

# Task 5.4 (modo zcode): los hooks de archivo no corren sin hooks.enabled:true.
reportar_enabled_zcode() {
  reportar "[summonaikit] REGISTRO DEL HOOK: hooks.enabled no es true en el user-config de zcode."
  reportar "              Los hooks de archivo no corren sin enabled:true (guia del CLI, medido)."
}

# Task 5.4 (modo zcode): matcher en el grupo de UserPromptSubmit/Stop es error.
reportar_matcher_ups_stop() {
  reportar "[summonaikit] REGISTRO DEL HOOK: $fases_con_matcher lleva 'matcher' en el user-config de zcode."
  reportar "              El matcher de UserPromptSubmit/Stop se prueba contra el TEXTO del prompt"
  reportar "              / la preview de la respuesta, no contra el nombre de la herramienta:"
  reportar "              un matcher ahi nunca matchea como en Claude. Sacarlo (DoD 5.4)."
}

# Ningun archivo legible: no se observo nada. No es lo mismo que estar ausente.
if [ "${leidos:-0}" = "0" ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — ningun settings legible."
  reportar "              buscado en: $SETTINGS"
  reportar "                          $LOCAL_SETTINGS"
  [ -n "$ilegibles" ] && reportar "              ilegible(s): $ilegibles"
  reportar "              No se afirma que el registro falte: no se pudo mirar."
  reportar_wrapper_codex
  reportar_hook_grok
  exit 0
fi

if [ -z "$faltantes" ]; then
  # Registro completo. Silencio salvo el matcher (hueco real cuando PostToolUse
  # no cubre Agent) o un settings ilegible. Un aviso en cada arranque sin nada
  # que decir es como se entrena a un operador a ignorarlos.
  [ -n "$ilegibles" ] && reportar "[summonaikit] REGISTRO DEL HOOK: completo, pero hay settings ilegible(s) (unknown): $ilegibles"
  [ "$enabled_mal" = "True" ] && reportar_enabled_zcode
  [ -n "$fases_con_matcher" ] && reportar_matcher_ups_stop
  reportar_matcher
  reportar_session_rules
  reportar_wrapper_codex
  reportar_hook_grok
  exit 0
fi

# Faltan fases, pero hubo algo que NO se pudo leer: esas fases podrian estar
# registradas justo ahi. Afirmar que el gate no corre seria exactamente la
# alarma falsa que entrena al operador a ignorar el aviso (Core Rule 2,
# Task 0.4). Solo se puede afirmar ausencia cuando se leyo TODO.
if [ -n "$ilegibles" ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — falta(n) $faltantes en lo que SI se pudo leer,"
  reportar "              pero hay settings ilegible(s) que podrian registrarlas: $ilegibles"
  reportar "              No se afirma que el gate deje de correr: esa parte no se pudo mirar."
  reportar "              revisar: $SETTINGS"
  reportar_wrapper_codex
  reportar_hook_grok
  exit 0
fi

# Fase(s) faltante(s) con todo legible: el gate no corre en esas fases. Si
# PostToolUse SI esta registrado y su matcher no cubre Agent, es un hueco
# independiente que se reporta tambien (no se apila si PTU es la que falta:
# ahi matcher_estado es sin-ptu y reportar_matcher no imprime).
reportar "[summonaikit] REGISTRO DEL HOOK INCOMPLETO — el gate NO corre en: $faltantes"
reportar "              El archivo del hook puede estar perfecto: esto es el registro, no el contenido."
reportar "              revisar: $SETTINGS"
[ "$enabled_mal" = "True" ] && reportar_enabled_zcode
[ -n "$fases_con_matcher" ] && reportar_matcher_ups_stop
reportar_session_rules
reportar_matcher
reportar_wrapper_codex
reportar_hook_grok
exit 0
