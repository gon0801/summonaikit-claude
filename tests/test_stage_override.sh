#!/usr/bin/env bash
# Task 2.4 — el staging por OVERRIDE DE PROYECTO.
#
# Lo que este archivo afirma, y por que:
#
#   - El staging no toca el hook global. Es la mitad de la DoD de la tarea, y no
#     alcanza con "no lo escribimos a proposito": se mide antes y despues.
#   - Un directorio que no es repo git NO se acepta. El comando registrado
#     resuelve el override con `git rev-parse --show-toplevel`; ahi el archivo
#     quedaria puesto y no correria nunca — un staging que miente.
#   - La preferencia del registro se MIDE ejecutando, no leyendo. Un settings al
#     que le sacaron el fallback al proyecto se ve igual de bien en una lectura
#     superficial y convierte el staging en una ilusion: el archivo puesto, el
#     turno gateado por el global.
#   - No poder medir es `unknown` y no "no funciona" (Core Rule 2). Sin settings
#     legible no se afirma ninguna de las dos cosas.
#
# El ultimo caso mira el settings REAL del host. Sin el, esta bateria quedaria
# verde con su propio literal el dia que alguien edite el registro de verdad —
# el mismo agujero que la Task 2.3 tapo mirando los dos artefactos a la vez.
#
# Core Rule 4: todo contra un tmpdir. Ningun caso escribe en `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="${SAIKIT_STAGE_TOOL:-$repo/tools/stage-override.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
manifiesto="$repo/hooks/vendor-manifest.sha256"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
nota() { printf '    nota: %s\n' "$1"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-stage-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe la herramienta de staging en $tool" >&2
  echo "test_stage_override: FAIL" >&2
  exit 1
fi

# El comando REGISTRADO, con el fallback al perfil. Es la forma que el staging
# asume; el ultimo caso comprueba que la maquina real siga teniendo esta forma.
CMD_CON_OVERRIDE='SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=prompt bash -c '"'"'h="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/hooks/summonaikit-harness.sh"; [ -f "$h" ] || h="$HOME/.claude/hooks/summonaikit-harness.sh"; bash "$h"'"'"''
# El mismo registro sin la mitad que hace posible el staging.
CMD_SIN_OVERRIDE='SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=prompt bash "$HOME/.claude/hooks/summonaikit-harness.sh"'

settings_con() {
  python - "$1" "$2" <<'PY'
import json, sys
json.dump({"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": sys.argv[2]}]}]}},
          open(sys.argv[1], "w", encoding="utf-8"))
PY
}

n_repo=0
nuevo_repo() {
  n_repo=$((n_repo + 1))
  repo_stage="$tmp/stage-$n_repo"
  mkdir -p "$repo_stage"
  ( cd "$repo_stage" && git init -q . ) >/dev/null 2>&1
  repo_stage="$(cd "$repo_stage" && pwd)"
}

# El HOME del test ya viene aislado por `run.sh`; el hook global es el de ESE
# home, no el del perfil.
global="$HOME/.claude/hooks/summonaikit-harness.sh"
huella_global() { if [ -e "$global" ]; then sha256sum < "$global"; else printf 'ausente\n'; fi; }

# ---------------------------------------------- 1) sin repo git no hay staging
caso "un directorio que no es repo git => no instala y lo dice"
suelto="$tmp/no-es-repo"
mkdir -p "$suelto"
out="$(bash "$tool" "$suelto" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 sobre un directorio suelto, dio $rc: $out"
[ -e "$suelto/.claude/hooks/summonaikit-harness.sh" ] \
  && malo "instalo el override donde el registro nunca lo va a resolver"
printf '%s' "$out" | grep -qi 'git' || malo "no explica que hace falta un repo git: $out"

# --------------------------------- 2) el camino feliz: instala, mide, no toca el global
caso "repo git + registro con override => instala byte a byte y MIDE que se prefiere"
nuevo_repo
settings="$tmp/settings-ok.json"
settings_con "$settings" "$CMD_CON_OVERRIDE"
antes_global="$(huella_global)"
out="$(bash "$tool" "$repo_stage" --source "$fuente" --manifest "$manifiesto" --settings "$settings" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 con un registro que prefiere el override, dio $rc: $out"
cmp -s "$repo_stage/.claude/hooks/summonaikit-harness.sh" "$fuente" \
  || malo "el override no quedo byte a byte igual a la fuente del repo"
[ "$(huella_global)" = "$antes_global" ] || malo "TOCO el hook global durante el staging"
printf '%s' "$out" | grep -qi 'MEDIDO' || malo "no declara haber medido la preferencia: $out"

caso "la medicion no deja su propio estado atras"
resto="$(find "$repo_stage/.claude/hooks/state" -type f 2>/dev/null | wc -l)"
[ "$resto" -eq 0 ] \
  || malo "el staging quedo con $resto archivos de estado de la medicion: el turno real no arrancaria limpio"

# Defecto propio, encontrado escribiendo la herramienta y cerrado con este caso:
# la medicion comparaba los NOMBRES de los archivos de estado. En un staging que
# ya tenia estado, el hook re-arma sobre los mismos archivos, la lista no cambia,
# y la herramienta habria concluido que el override no corrio — un falso negativo
# que aparece justo en la segunda corrida, la mas probable.
caso "una segunda corrida sobre estado preexistente sigue midiendo bien"
# La clave se calcula como la calcula el hook (cksum de la raiz git), porque el
# defecto solo aparece si el estado previo esta en los MISMOS archivos que el
# turno de prueba va a tocar. Con una clave inventada los nombres cambian igual
# y el caso pasaria sin discriminar nada — asi quedo escrito la primera vez.
proj_real="$(cd "$repo_stage" && git rev-parse --show-toplevel)"
key_real="$(printf '%s' "$proj_real" | cksum | cut -d ' ' -f 1)"
mkdir -p "$repo_stage/.claude/hooks/state/$key_real"
printf 'HARNESS_ARMED=1\n' > "$repo_stage/.claude/hooks/state/$key_real/harness-state.env"
printf 'evidencia de un turno anterior\n' > "$repo_stage/.claude/hooks/state/$key_real/harness-evidence.log"
out="$(bash "$tool" "$repo_stage" --source "$fuente" --manifest "$manifiesto" --settings "$settings" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "la segunda corrida deberia seguir midiendo el override, dio $rc: $out"
printf '%s' "$out" | grep -qi 'MEDIDO' || malo "no midio la preferencia con estado preexistente: $out"
[ -f "$repo_stage/.claude/hooks/state/$key_real/harness-state.env" ] \
  || malo "borro estado que no era de la medicion"
rm -rf "$repo_stage/.claude/hooks/state/$key_real"

caso "el turno de prueba no dejo nada en el perfil"
[ -e "$HOME/.claude/hooks/state" ] && [ -n "$(find "$HOME/.claude/hooks/state" -type f 2>/dev/null)" ] \
  && malo "la medicion escribio estado en el HOME"

# ------------------------------------- 3) un registro sin fallback es una ilusion
caso "registro SIN override => lo reporta fuerte en vez de dar el staging por bueno"
nuevo_repo
settings_malo="$tmp/settings-sin-override.json"
settings_con "$settings_malo" "$CMD_SIN_OVERRIDE"
out="$(bash "$tool" "$repo_stage" --source "$fuente" --manifest "$manifiesto" --settings "$settings_malo" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || malo "esperaba exit 3 con un registro que no prefiere el override, dio $rc: $out"
printf '%s' "$out" | grep -qi 'ilusion\|NO PREFIERE' \
  || malo "no avisa que el staging no tendria efecto: $out"

# ------------------------------------------- 4) el hook ni siquiera registrado
caso "el hook no figura en UserPromptSubmit => se dice, no se asume que anda"
nuevo_repo
settings_vacio="$tmp/settings-vacio.json"
settings_con "$settings_vacio" 'echo hola'
out="$(bash "$tool" "$repo_stage" --source "$fuente" --manifest "$manifiesto" --settings "$settings_vacio" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || malo "esperaba exit 3 sin el hook registrado, dio $rc: $out"

# ----------------------------------------------------- 5) unknown != no funciona
caso "settings ilegible => 'unknown', y el archivo igual quedo instalado"
nuevo_repo
out="$(bash "$tool" "$repo_stage" --source "$fuente" --manifest "$manifiesto" --settings "$tmp/no-existe.json" 2>&1)"; rc=$?
[ "$rc" -eq 4 ] || malo "esperaba exit 4 (unknown) sin settings legible, dio $rc: $out"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "Core Rule 2: no poder mirar el settings no es 'el registro no lo prefiere': $out"
cmp -s "$repo_stage/.claude/hooks/summonaikit-harness.sh" "$fuente" \
  || malo "no dejo el archivo instalado pese a que lo unico que fallo fue la medicion"

# --------------------------------- 6) el registro REAL sigue teniendo esta forma
# Sin este caso la bateria quedaria verde contra su propio literal el dia que
# alguien edite el registro de verdad, y el staging dejaria de existir en
# silencio. Se LEE, no se escribe (Core Rule 4).
caso "el registro real de esta maquina resuelve el override antes que el perfil"
settings_real=''
if [ -n "${SAIKIT_HOOK_VIVO:-}" ]; then
  settings_real="$(dirname "$(dirname "$SAIKIT_HOOK_VIVO")")/settings.json"
fi
if [ -z "$settings_real" ] || [ ! -r "$settings_real" ]; then
  nota "unknown — no hay settings real legible ($settings_real): no se afirma nada sobre esta maquina"
else
  real_cmd="$(python - "$settings_real" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception:
    sys.exit(1)
for bloque in (data.get('hooks') or {}).get('UserPromptSubmit') or []:
    for h in (bloque or {}).get('hooks') or []:
        cmd = (h or {}).get('command')
        if isinstance(cmd, str) and 'summonaikit-harness.sh' in cmd:
            print(cmd)
            sys.exit(0)
sys.exit(2)
PY
)"
  case $? in
    0)
      proyecto_pos="$(printf '%s' "$real_cmd" | grep -bo 'show-toplevel' | head -1 | cut -d: -f1)"
      perfil_pos="$(printf '%s' "$real_cmd" | grep -bo 'HOME/.claude/hooks' | head -1 | cut -d: -f1)"
      if [ -z "$proyecto_pos" ]; then
        malo "el registro real ya no resuelve el override del proyecto: el staging no tendria efecto"
        nota "comando real: $real_cmd"
      elif [ -n "$perfil_pos" ] && [ "$proyecto_pos" -gt "$perfil_pos" ]; then
        malo "el registro real resuelve el perfil ANTES que el proyecto: el override no ganaria"
      fi
      ;;
    2) nota "unknown — el settings real no registra el hook en UserPromptSubmit" ;;
    *) nota "unknown — no se pudo leer el settings real" ;;
  esac
fi

if [ "$fail" -ne 0 ]; then
  echo "test_stage_override: FAIL" >&2
  exit 1
fi
echo "test_stage_override: OK"
