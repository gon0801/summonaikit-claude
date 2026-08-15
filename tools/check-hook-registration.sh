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
    --settings|--local-settings|--hook-name|--zcode-config|--codex-hooks-json|--codex-wrapper)
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
if [ $((VIO_CLAUDE + VIO_ZCODE + VIO_CODEX)) -gt 1 ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — --settings, --zcode-config y --codex-hooks-json son mutuamente excluyentes."
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
                if ejecuta(str(entrada.get("command", "")), hook):
                    entrada_ejecuta = True
                    registradas.add(fase)
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
  if ! grep -q 'summonaikit-harness\.sh' "$CODEX_WRAPPER"; then
    reportar "[summonaikit] WRAPPER DE CODEX: existe pero NO nombra summonaikit-harness.sh ($CODEX_WRAPPER)."
    reportar "              El segundo eslabon de la cadena registro -> wrapper -> hook esta cortado."
  fi
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
exit 0
