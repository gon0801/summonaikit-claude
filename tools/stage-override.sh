#!/usr/bin/env bash
# stage-override.sh — staging por OVERRIDE DE PROYECTO (Task 2.4).
#
# El problema que resuelve: el archivo que gatea cada turno vive en
# `~/.claude/hooks/` y lo comparten TODOS los repos. Estrenarlo ahi es estrenarlo
# en produccion, en todos lados a la vez. El staging pone la version nueva en UN
# repo descartable y deja el resto del sistema como estaba.
#
# Por que funciona, medido y no supuesto: el override NO es una preferencia del
# host. Es el propio comando REGISTRADO en `settings.json` el que lo hace —
#
#   h="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/summonaikit-harness.sh"
#   [ -f "$h" ] || h="$HOME/.claude/hooks/summonaikit-harness.sh"
#
# — asi que hay UN solo hook por turno (no dos corriendo a la vez), y quien manda
# es el del repo cuando existe. Dos consecuencias que importan:
#
#   1. Si alguien edita ese comando y le saca el fallback, el staging pasa a ser
#      una ILUSION: el archivo del repo esta puesto y nunca corre. Por eso esta
#      herramienta no lee el comando para creerle: lo EJECUTA y mira cual de los
#      dos hooks corrio.
#   2. El repo tiene que ser un repo git. `git rev-parse --show-toplevel` es lo
#      que resuelve la ruta; en un directorio suelto el override no gana nunca.
#
# El estado tambien queda aislado: el hook deriva `STATE_ROOT` de su propia
# ubicacion (`$(dirname "$0")/state`), asi que el staging escribe en
# `<repo>/.claude/hooks/state/` y no toca el estado del perfil.
#
# Uso:
#   bash tools/stage-override.sh <repo-descartable>
#   bash tools/stage-override.sh <repo> --settings <path> --source <path> --no-medir
#
# Exit codes (cualquier != 0 significa que NO quedo staging utilizable):
#   0  staging instalado, y medido que el registro lo prefiere
#   2  invocacion invalida, o el destino no es un repo git
#   3  el registro NO prefiere el override: el staging seria una ilusion
#   4  unknown — no se pudo medir (no se afirma que funcione ni que no)
#   5  la instalacion no se pudo completar (el instalador ya lo reporto)
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_propio="$(cd "$here/.." && pwd)"

REPO=''
SOURCE="$repo_propio/hooks/summonaikit-harness.sh"
MANIFEST="$repo_propio/hooks/vendor-manifest.sha256"
SETTINGS="${HOME:-}/.claude/settings.json"
INSTALADOR="$here/install-hook.sh"
MEDIR=1
HOOK_NAME='summonaikit-harness.sh'

decir() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --settings|--source|--manifest|--installer)
      # Un flag sin valor no puede hacer girar el `while`: es el cuelgue que la
      # Task 0.4 midio en `check-hook-registration.sh` (rc=124).
      if [ $# -lt 2 ]; then
        decir "[summonaikit] staging: falta el valor de $1"
        exit 2
      fi
      case "$1" in
        --settings)  SETTINGS="$2" ;;
        --source)    SOURCE="$2" ;;
        --manifest)  MANIFEST="$2" ;;
        --installer) INSTALADOR="$2" ;;
      esac
      shift 2
      ;;
    --no-medir) MEDIR=0; shift ;;
    -h|--help)  sed -n '2,38p' "$0"; exit 0 ;;
    -*)
      decir "[summonaikit] staging: opcion desconocida: $1"
      exit 2
      ;;
    *)
      if [ -n "$REPO" ]; then
        decir "[summonaikit] staging: se esperaba un solo repo, y llego tambien: $1"
        exit 2
      fi
      REPO="$1"; shift
      ;;
  esac
done

if [ -z "$REPO" ]; then
  decir "[summonaikit] staging: falta el repo descartable."
  decir "              uso: bash tools/stage-override.sh <repo-descartable>"
  exit 2
fi
if [ ! -d "$REPO" ]; then
  decir "[summonaikit] staging: no existe el directorio $REPO"
  exit 2
fi
REPO="$(cd "$REPO" && pwd)"

# ------------------------------------------------------------- tiene que ser git
# No es burocracia: el comando registrado resuelve la ruta del override con
# `git rev-parse --show-toplevel`. En un directorio suelto cae al `|| pwd`, que
# solo coincide si el turno corre justo desde ahi; y con un subdirectorio abierto
# no coincide nunca. Instalar igual dejaria un archivo puesto que no corre.
if [ "$(cd "$REPO" && git rev-parse --show-toplevel 2>/dev/null)" = '' ]; then
  decir "[summonaikit] staging: $REPO no es un repo git."
  decir "              El comando registrado resuelve el override con 'git rev-parse --show-toplevel',"
  decir "              asi que aca el archivo quedaria puesto y no correria nunca. Corre 'git init' primero."
  exit 2
fi

DEST="$REPO/.claude/hooks/$HOOK_NAME"
GLOBAL="${HOME:-}/.claude/hooks/$HOOK_NAME"

# La primera mitad de la DoD de esta tarea es "sin tocar el archivo global", asi
# que se mide: huella antes y despues. No alcanza con no escribirlo a proposito.
huella_global() {
  if [ -e "$GLOBAL" ]; then
    sha256sum < "$GLOBAL" 2>/dev/null || printf 'ilegible\n'
  else
    printf 'ausente\n'
  fi
}
global_antes="$(huella_global)"

# ------------------------------------------------------------------- instalar
# Se delega en el instalador de la Task 2.2 y no se copia con `cp`: el staging
# tambien puede caer sobre un archivo que ya estaba y que nadie miro, y ahi valen
# los mismos tres estados. `--no-registration-check` porque el settings que manda
# es el del perfil, no el hermano del destino: la verificacion del registro la
# hace la medicion de mas abajo, que es mas fuerte (ejecuta, no lee).
decir "[summonaikit] staging por override de proyecto"
decir "              repo:    $REPO"
decir "              destino: $DEST"
if ! bash "$INSTALADOR" --dest "$DEST" --source "$SOURCE" --manifest "$MANIFEST" --no-registration-check; then
  rc=$?
  decir "[summonaikit] staging: el instalador no dejo el archivo (exit $rc). No se toco nada mas."
  exit 5
fi

if [ "$(huella_global)" != "$global_antes" ]; then
  decir "[summonaikit] staging: ALERTA — el hook GLOBAL cambio durante el staging."
  decir "              global: $GLOBAL"
  decir "              El staging existe justamente para no tocarlo."
  exit 5
fi
decir "[summonaikit] el hook global quedo intacto (medido antes y despues)."

[ "$MEDIR" -eq 1 ] || exit 0

# ------------------------------------------- medir que el registro lo prefiere
# No se lee el comando para creerle: se lo EJECUTA con el repo como cwd y se mira
# cual de los dos hooks corrio. Un settings con el fallback borrado se ve igual
# de bien en una lectura superficial y deja el staging sin efecto.
python_bin=''
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then python_bin="$c"; break; fi
done
if [ -z "$python_bin" ]; then
  decir "[summonaikit] unknown — no hay interprete python para leer el settings."
  decir "              El archivo quedo instalado; lo que no se pudo es medir si el registro lo prefiere."
  exit 4
fi

comando="$("$python_bin" - "$SETTINGS" "$HOOK_NAME" <<'PY' 2>/dev/null
import json, sys
ruta, hook = sys.argv[1], sys.argv[2]
try:
    with open(ruta, encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)
for bloque in (data.get('hooks') or {}).get('UserPromptSubmit') or []:
    for h in (bloque or {}).get('hooks') or []:
        cmd = (h or {}).get('command')
        if isinstance(cmd, str) and hook in cmd:
            print(cmd)
            sys.exit(0)
sys.exit(2)
PY
)"
rc_cmd=$?

if [ "$rc_cmd" -eq 1 ]; then
  decir "[summonaikit] unknown — no se pudo leer el settings: $SETTINGS"
  decir "              No se afirma que el registro prefiera (ni que no prefiera) el override."
  exit 4
fi
if [ "$rc_cmd" -ne 0 ] || [ -z "$comando" ]; then
  decir "[summonaikit] EL HOOK NO ESTA REGISTRADO en UserPromptSubmit: $SETTINGS"
  decir "              Sin registro no hay turno que gatear, ni en el repo ni en el perfil."
  exit 3
fi

# El HOME desechable es lo que vuelve inequivoca la medicion: ahi el fallback
# global apunta a un archivo que NO existe, asi que si el comando corre algo, fue
# el override. Y de paso ningun estado puede caer en el perfil real.
medicion_home="$(mktemp -d "${TMPDIR:-/tmp}/saikit-stage-home-XXXXXX")" || {
  decir "[summonaikit] unknown — no se pudo crear el HOME de medicion."
  exit 4
}
mkdir -p "$medicion_home/.claude/hooks"

estado_dir="$REPO/.claude/hooks/state"
# Dos huellas y no una: la de CONTENIDO decide si el hook corrio, y la de NOMBRES
# dice que limpiar. Comparar solo los nombres daba un falso "no prefiere el
# override" en la segunda corrida sobre el mismo staging: ahi el hook re-arma
# sobre los archivos que ya estaban, la lista no cambia, y la herramienta habria
# concluido que no corrio nada. El log de evidencia lleva TIMESTAMP, asi que el
# contenido si cambia.
estado_contenido() { find "$estado_dir" -type f -print0 2>/dev/null | sort -z | xargs -0 -r cksum 2>/dev/null; }
estado_nombres()   { find "$estado_dir" -type f 2>/dev/null | sort; }
estado_antes="$(estado_contenido)"
nombres_antes="$(estado_nombres)"

payload="$(printf '{"session_id":"stage-override","transcript_path":"","cwd":"%s","hook_event_name":"UserPromptSubmit","permission_mode":"auto","prompt":"medicion del staging -saikit"}' \
  "$(printf '%s' "$REPO" | sed 's/\\/\\\\/g')")"

salida="$(cd "$REPO" && printf '%s' "$payload" \
  | env HOME="$medicion_home" USERPROFILE="$medicion_home" bash -c "$comando" 2>&1)"
rc_medicion=$?

estado_despues="$(estado_contenido)"
nombres_despues="$(estado_nombres)"
rm -rf "$medicion_home"

if [ "$estado_antes" != "$estado_despues" ]; then
  decir "[summonaikit] MEDIDO: el registro prefiere el override del proyecto."
  decir "              El turno de prueba armo el harness en $estado_dir"
  # Se limpia lo que la medicion creo, y SOLO eso: se compara contra los nombres
  # de antes, no contra la huella de contenido. El estado que ya estaba no es de
  # la prueba y no le corresponde a esta herramienta borrarlo.
  printf '%s\n' "$nombres_despues" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$nombres_antes" | grep -qxF "$f" || rm -f "$f"
  done
  decir "              (el estado de la medicion se borro; el staging arranca limpio)"
  decir ""
  decir "Ahora, el turno REAL — es el unico paso que no se puede hacer desde aca,"
  decir "porque Claude Code fotografia los hooks al arrancar la sesion:"
  decir "  1) abri una sesion nueva de Claude Code en $REPO"
  decir "  2) un prompt CON '-saikit' arma el harness; uno pelado no debe crear estado"
  decir "  3) mira $estado_dir para ver que se armo, y"
  decir "     $GLOBAL para confirmar que el global sigue intacto"
  decir "  4) para volver atras: bash tools/install-hook.sh --dest '$DEST' --restore-vendor"
  decir "     (o simplemente borra $REPO/.claude/hooks/)"
  exit 0
fi

decir "[summonaikit] EL REGISTRO NO PREFIERE EL OVERRIDE — el staging seria una ilusion."
decir "              settings: $SETTINGS"
decir "              El turno de prueba no armo nada en $estado_dir (exit $rc_medicion)."
decir "              El comando registrado tiene que resolver primero"
decir "              '<repo>/.claude/hooks/$HOOK_NAME' y recien despues el del perfil."
decir "              comando: $comando"
[ -n "$salida" ] && decir "              salida:  $salida"
exit 3
