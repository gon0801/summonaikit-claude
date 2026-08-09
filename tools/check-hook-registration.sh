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

while [ $# -gt 0 ]; do
  case "$1" in
    --settings)       SETTINGS="${2:-}"; shift 2 ;;
    --local-settings) LOCAL_SETTINGS="${2:-}"; shift 2 ;;
    --hook-name)      HOOK_NAME="${2:-}"; shift 2 ;;
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

reportar() { printf '%s\n' "$*"; }

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
import json, sys

settings, local, hook = sys.argv[1], sys.argv[2], sys.argv[3]
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
                if hook in str(entrada.get("command", "")):
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

reportar "[summonaikit] REGISTRO DEL HOOK INCOMPLETO — el gate NO corre en: $faltantes"
reportar "              El archivo del hook puede estar perfecto: esto es el registro, no el contenido."
reportar "              revisar: $SETTINGS"
[ -n "$ilegibles" ] && reportar "              ademas, settings ilegible(s) (unknown): $ilegibles"
exit 0
