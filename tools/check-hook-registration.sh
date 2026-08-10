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
set -u

HOOK_NAME='summonaikit-harness.sh'
SETTINGS="${HOME:-}/.claude/settings.json"
LOCAL_SETTINGS=''

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
    --settings|--local-settings|--hook-name)
      if [ $# -lt 2 ]; then
        reportar "[summonaikit] REGISTRO DEL HOOK: unknown — falta el valor de $1; no se verifico nada."
        reportar "              No se afirma que el registro falte: no se pudo mirar."
        exit 0
      fi
      case "$1" in
        --settings)       SETTINGS="$2" ;;
        --local-settings) LOCAL_SETTINGS="$2" ;;
        --hook-name)      HOOK_NAME="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)        sed -n '2,20p' "$0"; exit 0 ;;
    *)                shift ;;
  esac
done

# El local por defecto es HERMANO del settings dado, no el del HOME real: si no,
# apuntar `--settings` a un fixture igual leeria el settings.local.json de
# verdad (Core Rule 4).
if [ -z "$LOCAL_SETTINGS" ]; then
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

resultado="$("$python_bin" - "$SETTINGS" "$LOCAL_SETTINGS" "$HOOK_NAME" <<'PY' 2>/dev/null
import json, re, shlex, sys

settings, local, hook = sys.argv[1], sys.argv[2], sys.argv[3]

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
    try:
        tokens = shlex.split(comando, posix=True)
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

registradas, leidos, ilegibles = set(), [], []

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
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        continue
    for fase, grupos in hooks.items():
        if not isinstance(grupos, list):
            continue
        for grupo in grupos:
            if not isinstance(grupo, dict):
                continue
            for entrada in grupo.get("hooks", []) or []:
                if not isinstance(entrada, dict):
                    continue
                if ejecuta(str(entrada.get("command", "")), hook):
                    registradas.add(fase)

faltantes = [f for f in ESPERADAS if f not in registradas]
print(json.dumps({
    "faltantes": faltantes,
    "leidos": leidos,
    "ilegibles": ilegibles,
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

# Ningun archivo legible: no se observo nada. No es lo mismo que estar ausente.
if [ "${leidos:-0}" = "0" ]; then
  reportar "[summonaikit] REGISTRO DEL HOOK: unknown — ningun settings legible."
  reportar "              buscado en: $SETTINGS"
  reportar "                          $LOCAL_SETTINGS"
  [ -n "$ilegibles" ] && reportar "              ilegible(s): $ilegibles"
  reportar "              No se afirma que el registro falte: no se pudo mirar."
  exit 0
fi

if [ -z "$faltantes" ]; then
  # Registro completo: silencio. Un aviso en cada arranque sin nada que decir
  # es como se entrena a un operador a ignorarlos.
  [ -n "$ilegibles" ] && reportar "[summonaikit] REGISTRO DEL HOOK: completo, pero hay settings ilegible(s) (unknown): $ilegibles"
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
  exit 0
fi

reportar "[summonaikit] REGISTRO DEL HOOK INCOMPLETO — el gate NO corre en: $faltantes"
reportar "              El archivo del hook puede estar perfecto: esto es el registro, no el contenido."
reportar "              revisar: $SETTINGS"
exit 0
