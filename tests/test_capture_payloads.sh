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

# ============================================================
# Task 5.1 -- --host zcode: captura via el USER-CONFIG (no settings.json).
#
# Por que estos casos existen: el override de proyecto de zcode NO corre en
# este CLI (hallazgo 1 del plan); el canal que corre es el user-config
# `~/.zcode/cli/config.json`, que ya tiene `hooks.enabled: true`. `--instalar
# --host zcode` appendea ahi NUESTRAS entradas y deja los hooks ajenos intactos.
#
# Core Rule 4: ningun caso toca el `~/.zcode` real. Todo apunta a
# `SAIKIT_ZCODE_USER_CONFIG` dentro del sandbox, con vecinos ajenos de mentira
# (SessionStart + Stop dummy, como el tokentracker real) que el append respeta.
#
# 5 entradas (no 4): UserPromptSubmit (sin matcher) + PostToolUse x3
# (Task / Agent / Bash|Edit|Write|Read, cada una con --tag) + Stop (sin
# matcher). La cuenta "las 4" del plan omitia Stop; la DoD exige 3 fases.
# ============================================================
if ! command -v jq >/dev/null 2>&1; then
  # jq es requisito de --host zcode. Sin el no se puede medir; se declara
  # unknown, no se finge verde (unknown != ausente).
  echo "  caso: --host zcode requiere jq -> UNKNOWN (jq no disponible)"
  echo "  test_capture_payloads: zcode skip (unknown)"
else
  zcode_home="$SANDBOX/zcode-home"
  zcode_cfg="$zcode_home/.zcode/cli/config.json"
  zdesc="$SANDBOX/zcode-repo"
  mkdir -p "$zdesc"

  # Fabrica un config de zcode minimo con vecinos ajenos que el append debe
  # respetar: SessionStart dummy y un Stop dummy (estilo tokentracker).
  fabricar_zcode_config() {
    rm -rf "$zcode_home"; mkdir -p "$zcode_home/.zcode/cli"
    cat > "$zcode_cfg" <<'JSON'
{
  "hooks": {
    "enabled": true,
    "events": {
      "SessionStart": [
        { "matcher": "startup", "hooks": [ { "type": "command", "command": "echo dummy-session-start", "timeout": 5 } ] }
      ],
      "UserPromptSubmit": [],
      "PostToolUse": [],
      "Stop": [
        { "hooks": [ { "type": "command", "command": "echo dummy-stop-tokentracker", "timeout": 5 } ] }
      ]
    }
  }
}
JSON
  }

  # ---- z1: instalar appendea 5 entradas, respetando vecinos -----------------
  caso "zcode --instalar appendea 5 entradas en el user-config y NO toca .claude"
  fabricar_zcode_config
  session_antes="$(jq -c '.hooks.events.SessionStart' "$zcode_cfg")"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$zdesc" --host zcode 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
  # 5 entradas nuestras, identificadas por el marker de propiedad.
  n_id="$(grep -c 'saikit-capture-id 5\.1' "$zcode_cfg" || true)"
  [ "$n_id" -eq 5 ] || malo "esperaba 5 entradas con saikit-capture-id 5.1, hay $n_id"
  # UserPromptSubmit y Stop sin matcher; PostToolUse con Task/Agent/Bash|Edit|Write|Read.
  jq -e '(.hooks.events.UserPromptSubmit|length)==1 and (.hooks.events.UserPromptSubmit[0]|has("matcher")|not)' \
        "$zcode_cfg" >/dev/null \
    || malo "UserPromptSubmit debe ser 1 entrada sin matcher"
  jq -e 'all(.hooks.events.PostToolUse[]; .matcher=="Task" or .matcher=="Agent" or .matcher=="Bash|Edit|Write|Read")' \
        "$zcode_cfg" >/dev/null \
    || malo "PostToolUse tiene entradas con matcher inesperado"
  jq -e '[.hooks.events.PostToolUse[]|select(.matcher=="Task")]                | length==1' "$zcode_cfg" >/dev/null || malo "falta PostToolUse Task"
  jq -e '[.hooks.events.PostToolUse[]|select(.matcher=="Agent")]               | length==1' "$zcode_cfg" >/dev/null || malo "falta PostToolUse Agent"
  jq -e '[.hooks.events.PostToolUse[]|select(.matcher=="Bash|Edit|Write|Read")]| length==1' "$zcode_cfg" >/dev/null || malo "falta PostToolUse Bash|Edit|Write|Read"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("saikit-capture-id")))] | length==1 and (.[0]|has("matcher")|not)' \
        "$zcode_cfg" >/dev/null \
    || malo "Stop: debe tener 1 entrada nuestra sin matcher"
  # Cada comando lleva --only-cwd al dest y su --tag. El dest va resuelto
  # fisicamente (pwd -P), igual que lo guarda el script. Se extrae el path
  # guardado DESDE jq (no se le pasa por --arg: jq.exe es nativo y MSYS le
  # converteria el path POSIX del sandbox a Windows), y se compara en bash.
  stored_cwd="$(jq -r '[ .hooks.events[][] | .hooks[].command // empty | select(contains("--only-cwd")) ][0]' \
                  "$zcode_cfg" | sed -n 's/.*--only-cwd "\([^"]*\)".*/\1/p')"
  zdesc_real="$(cd "$zdesc" && pwd -P)"
  [ "$stored_cwd" = "$zdesc_real" ] \
    || malo "--only-cwd no apunta al dest: guardo [$stored_cwd], esperaba [$zdesc_real]"
  for t in ups task agent tools stop; do
    grep -q -- "--tag $t" "$zcode_cfg" || malo "falta --tag $t"
  done
  # NO toca el canal de Claude ni crea el override de proyecto de zcode.
  [ ! -f "$zdesc/.claude/settings.json" ] || malo "escribio .claude/settings.json en modo zcode"
  [ ! -f "$zdesc/.zcode/config.json" ]     || malo "creo .zcode/config.json (override de proyecto, que no corre)"
  # Marca y capturas ignoradas.
  [ -f "$zdesc/.zcode/.capture-payloads-owned" ] || malo "no dejo marca .zcode/.capture-payloads-owned"
  [ -f "$zdesc/capturas/.gitignore" ]            || malo "no ignoro capturas/"
  # Los vecinos ajenos sobreviven intactos (estructura, no bytes).
  session_despues="$(jq -c '.hooks.events.SessionStart' "$zcode_cfg")"
  [ "$session_antes" = "$session_despues" ] || malo "modifico el SessionStart ajeno"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' \
        "$zcode_cfg" >/dev/null || malo "borro el Stop dummy ajeno"
  # El backup va bajo el dir del user-config, NUNCA bajo el dest git.
  [ -d "$zcode_home/.zcode/cli/saikit-backups" ] || malo "no creo backup junto al user-config"
  [ -z "$(find "$zdesc" -name '*.bak' 2>/dev/null)" ] || malo "el backup cayo adentro del dest git"

  # ---- z2: segunda instalacion es idempotente (no duplica) ------------------
  caso "zcode segunda --instalar no duplica (idempotente por tag)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$zdesc" --host zcode 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "segunda instalacion debe ser exit 0, dio $rc: $out"
  n_id="$(grep -c 'saikit-capture-id 5\.1' "$zcode_cfg" || true)"
  [ "$n_id" -eq 5 ] || malo "la segunda instalacion duplico entradas (hay $n_id, esperaba 5)"
  jq -e '.hooks.events.UserPromptSubmit|length==1' "$zcode_cfg" >/dev/null || malo "duplico UserPromptSubmit"
  jq -e '.hooks.events.PostToolUse|length==3'        "$zcode_cfg" >/dev/null || malo "duplico PostToolUse"

  # ---- z3: --host inventado => exit 2 ---------------------------------------
  caso "zcode --host inventado => exit 2 y no escribe"
  fabricar_zcode_config
  rm -rf "$zdesc/.claude" "$zdesc/.zcode" "$zdesc/capturas"   # estado pristine
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$zdesc" --host inventado 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "esperaba exit 2 con --host inventado, dio $rc"
  grep -q 'saikit-capture-id' "$zcode_cfg" && malo "--host inventado escribio en el config" || true
  [ ! -f "$zdesc/.claude/settings.json" ] || malo "--host inventado creo .claude/settings"
  [ ! -f "$zdesc/.zcode/.capture-payloads-owned" ] || malo "--host inventado dejo marca"

  # ---- z4: el dest no puede resolver al ~/.zcode del perfil -----------------
  caso "zcode se niega a instalar si el dest resuelve a \$HOME/.zcode"
  fabricar_zcode_config
  mkdir -p "$HOME/.zcode"   # $HOME es el del sandbox
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$HOME/.zcode" --host zcode 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "instalar sobre \$HOME/.zcode debe fallar (dio $rc)"
  grep -q 'saikit-capture-id' "$zcode_cfg" && malo "escribio el config con dest = perfil" || true

  # ---- z5: --quitar saca SOLO nuestras entradas; vecinos siguen -------------
  caso "zcode --quitar (sin --host, infiere por marca) saca solo saikit-capture-id 5.1"
  # Reconstruimos un config con nuestras 5 + vecinos + un Stop ajeno que
  # menciona capture-payloads.sh SIN el id (no debe borrarse).
  fabricar_zcode_config
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$zdesc" --host zcode >/dev/null
  # Inyectar un Stop ajeno con capture-payloads.sh pero sin el id.
  tmpq="$(mktemp)"
  jq '.hooks.events.Stop += [{"hooks":[{"type":"command","command":"bash /otro/capture-payloads.sh","timeout":5}]}]' \
     "$zcode_cfg" > "$tmpq" && mv -f "$tmpq" "$zcode_cfg"
  n_antes="$(grep -c 'saikit-capture-id 5\.1' "$zcode_cfg" || true)"
  [ "$n_antes" -eq 5 ] || malo "precondicion: 5 entradas antes de quitar (hay $n_antes)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --quitar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "quitar debe ser exit 0, dio $rc: $out"
  n_despues="$(grep -c 'saikit-capture-id 5\.1' "$zcode_cfg" || true)"
  [ "$n_despues" -eq 0 ] || malo "quitar dejo $n_despues entradas con el id"
  jq -e '[.hooks.events.SessionStart[]]|length==1' "$zcode_cfg" >/dev/null || malo "quitar borro SessionStart ajeno"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' "$zcode_cfg" >/dev/null \
    || malo "quitar borro el Stop dummy ajeno"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("capture-payloads.sh") and (test("saikit-capture-id")|not)))]|length==1' "$zcode_cfg" >/dev/null \
    || malo "quitar borro un Stop ajeno que menciona capture-payloads.sh sin el id"
  [ ! -f "$zdesc/.zcode/.capture-payloads-owned" ] || malo "quitar dejo la marca colgada"

  # ---- z6: regresion -- sin --host sigue siendo Claude puro ----------------
  caso "regresion: --instalar sin --host escribe .claude/settings y ignora el user-config zcode"
  fabricar_zcode_config
  snap_zcode="$(cksum < "$zcode_cfg")"
  crepo="$SANDBOX/claude-repo"; mkdir -p "$crepo"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$crepo" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar Claude debe exit 0, dio $rc: $out"
  [ -f "$crepo/.claude/settings.json" ] || malo "no escribio .claude/settings.json"
  grep -q 'capture-payloads.sh' "$crepo/.claude/settings.json" || malo "el settings no llama al capturador"
  [ "$snap_zcode" = "$(cksum < "$zcode_cfg")" ] || malo "el modo Claude toco el user-config de zcode"

  # ---- z7: modo hook --only-cwd de otro dir => no escribe ------------------
  caso "zcode modo hook: --only-cwd de otro directorio no crea archivo"
  capdir7="$SANDBOX/cap-onlycwd"
  printf '%s' '{"hook_event_name":"UserPromptSubmit","prompt":"x"}' \
    | ( cd "$SANDBOX" && SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
        bash "$tool" --only-cwd "$zdesc" --capture-dir "$capdir7" --tag ups ); rc=$?
  [ "$rc" -eq 0 ] || malo "fail-open roto en --only-cwd (dio $rc)"
  [ -z "$(find "$capdir7" -name '*.json' 2>/dev/null)" ] || malo "--only-cwd ajeno igual escribio"

  # ---- z8: dos writes al mismo dir no se pisan (mktemp) --------------------
  caso "zcode modo hook: dos writes seguidos no se pisan (atomicidad por mktemp)"
  capdir8="$SANDBOX/cap-atomic"
  printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Bash"}' \
    | ( cd "$zdesc" && SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
        bash "$tool" --only-cwd "$zdesc" --capture-dir "$capdir8" --tag tools )
  printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Read"}' \
    | ( cd "$zdesc" && SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
        bash "$tool" --only-cwd "$zdesc" --capture-dir "$capdir8" --tag tools )
  archivos8="$(find "$capdir8" -name '*PostToolUse*tools*.json' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$archivos8" -ge 2 ] || malo "dos writes se pisaron (hay $archivos8 archivo(s), esperaba >=2)"
  # Los payloads no llevan newline; hay que separarlos antes de sort -u, si no
  # cat los pega en una sola linea y la cuenta de distinct colapsa a 1.
  distintos="$(find "$capdir8" -name '*PostToolUse*tools*.json' \
                -exec sh -c 'cat "$1"; echo' _ {} \; 2>/dev/null | sort -u | grep -c . || true)"
  [ "$distintos" -ge 2 ] || malo "los dos archivos no tienen contenido distinto"

  echo "  test_capture_payloads: zcode OK"
fi

if [ "$fail" -ne 0 ]; then
  echo "test_capture_payloads: FAIL" >&2
  exit 1
fi
echo "test_capture_payloads: OK"
