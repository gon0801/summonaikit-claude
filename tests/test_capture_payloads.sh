#!/usr/bin/env bash
# Task 1.2 — la herramienta de captura no puede convertirse en el problema.
#
# Captura payloads crudos de turnos reales y escribe un `settings.json`: las
# dos cosas que puede romper son ensuciar el perfil vivo y borrarle
# configuracion al usuario. Cada caso de aca sale de un hallazgo de la revision
# cruzada del 2026-08-09 (codex), no de imaginar riesgos:
#
#   - el filtro del perfil miraba la ruta LOGICA, asi que un enlace simbolico
#     lo esquivaba;
#   - `--quitar` borraba el settings.json entero aunque fuera del usuario —
#     justo el caso que el propio instalador le dice que arme a mano;
#   - lo capturado (que puede traer el texto de un turno real) quedaba con
#     permisos heredados y sin nada que impidiera commitearlo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="$repo/tools/capture-payloads.sh"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

descartable="$SANDBOX/repo-descartable"
mkdir -p "$descartable"

# ------------------------------------------------------------ 1) instalar
caso "--instalar deja el registro, la marca de propiedad y las capturas ignoradas"
out="$(bash "$tool" --instalar "$descartable" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$descartable/.claude/settings.json" ] || malo "no escribio el settings"
grep -q 'capture-payloads.sh' "$descartable/.claude/settings.json" \
  || malo "el settings no llama al capturador"
[ -f "$descartable/.claude/.capture-payloads-owned" ] \
  || malo "no dejo la marca de propiedad; sin ella --quitar no puede distinguir"
[ -f "$descartable/capturas/.gitignore" ] \
  || malo "la carpeta de capturas no se ignora: un payload real podria terminar commiteado"

caso "--instalar NO pisa un settings que ya existe"
otro="$SANDBOX/con-settings"
mkdir -p "$otro/.claude"
printf '{"mio":true}\n' > "$otro/.claude/settings.json"
out="$(bash "$tool" --instalar "$otro" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "pisar un settings ajeno debe fallar"
grep -q '"mio"' "$otro/.claude/settings.json" || malo "PISO el settings del usuario"

# -------------------------------------------------------------- 2) quitar
caso "--quitar SI borra lo que instalo esta herramienta"
out="$(bash "$tool" --quitar "$descartable" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ ! -f "$descartable/.claude/settings.json" ] || malo "no quito el settings propio"
[ ! -f "$descartable/.claude/.capture-payloads-owned" ] || malo "dejo la marca colgada"

caso "--quitar NO borra un settings del usuario aunque mencione el capturador"
ajeno="$SANDBOX/settings-ajeno"
mkdir -p "$ajeno/.claude"
cat > "$ajeno/.claude/settings.json" <<'JSON'
{
  "permissions": { "allow": ["Bash(ls:*)"] },
  "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "bash /ruta/capture-payloads.sh" } ] } ] }
}
JSON
antes="$(cksum < "$ajeno/.claude/settings.json")"
out="$(bash "$tool" --quitar "$ajeno" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "sin marca de propiedad, --quitar debe negarse (dio $rc)"
[ -f "$ajeno/.claude/settings.json" ] || malo "DESTRUCTIVO: borro el settings del usuario"
[ "$antes" = "$(cksum < "$ajeno/.claude/settings.json" 2>/dev/null)" ] \
  || malo "DESTRUCTIVO: modifico el settings del usuario"
printf '%s' "$out" | grep -qi 'no lo cree yo' || malo "no explica por que no lo borra: $out"

# ------------------------------------------------- 3) el perfil real, intacto
caso "se niega a instalar sobre el perfil real"
for ruta in "$HOME" "$HOME/.claude"; do
  mkdir -p "$ruta"
  out="$(bash "$tool" --instalar "$ruta" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "acepto instalar en $ruta"
  [ -f "$ruta/.claude/settings.json" ] && malo "escribio adentro de $ruta"
done

caso "un enlace simbolico al perfil TAMPOCO lo esquiva (ruta fisica, no logica)"
alias_home="$SANDBOX/alias-al-home"
if ln -s "$HOME" "$alias_home" 2>/dev/null && [ -L "$alias_home" ]; then
  out="$(bash "$tool" --instalar "$alias_home" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "el enlace simbolico esquivo el filtro del perfil"
  [ -f "$HOME/.claude/settings.json" ] && malo "escribio en el perfil a traves del enlace"
  printf '%s' "$out" | grep -qi 'resuelve a' || malo "no muestra a donde resuelve la ruta: $out"
else
  # Core Rule 2: no poder crear un enlace simbolico (Windows sin modo
  # desarrollador) no es lo mismo que haber comprobado que el filtro aguanta.
  echo "    unknown: esta maquina no deja crear enlaces simbolicos; el caso no se pudo medir"
  rm -rf "$alias_home" 2>/dev/null
fi

# ----------------------------------------------- 4) el modo hook, contenido
caso "como hook: guarda el payload donde se le dice y en ningun otro lado"
capturas="$SANDBOX/capturas-sueltas"
antes_repo="$(find "$repo" -newer "$tool" -name 'capturas' -type d 2>/dev/null | head -1)"
printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"-saikit hola"}' \
  | ( cd "$SANDBOX" && SAIKIT_CAPTURE_DIR="$capturas" bash "$tool" ); rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto: el capturador debe salir 0 siempre (dio $rc)"
archivo="$(find "$capturas" -name '*UserPromptSubmit*.json' 2>/dev/null | head -1)"
[ -n "$archivo" ] || malo "no guardo el payload con el nombre del evento"
[ -n "$archivo" ] && grep -q 'saikit hola' "$archivo" || malo "no guardo el payload crudo"
[ -f "$capturas/.gitignore" ] || malo "no dejo el .gitignore que evita commitear un turno real"
[ -z "$antes_repo" ] && [ ! -d "$repo/capturas" ] \
  || malo "escribio una carpeta de capturas adentro del repo"

caso "como hook: un payload ilegible no rompe el turno (fail-open)"
printf '%s' 'esto no es json' \
  | ( cd "$SANDBOX" && SAIKIT_CAPTURE_DIR="$capturas" bash "$tool" ); rc=$?
[ "$rc" -eq 0 ] || malo "un payload ilegible debe salir 0 igual (dio $rc)"
[ -n "$(find "$capturas" -name '*sin-evento*.json' 2>/dev/null | head -1)" ] \
  || malo "deberia guardarlo igual, marcado como sin-evento"

if [ "$fail" -ne 0 ]; then
  echo "test_capture_payloads: FAIL" >&2
  exit 1
fi
echo "test_capture_payloads: OK"
