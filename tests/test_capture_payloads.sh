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

  # ---- z9: DOS repos contra UN user-config (hallazgo H2 de CodeRabbit) -----
  # El user-config de zcode es COMPARTIDO. `has_tag` decidia por evento+tag y
  # `ours` matcheaba solo el capture-id: ninguno miraba el destino. Efectos, los
  # dos reales: instalar B estando A no agregaba las entradas de B (su captura
  # nunca ocurria), y --quitar B se llevaba los hooks VIVOS de A.
  # Los destinos se extraen DESDE jq y se comparan en bash, igual que z1: en el
  # archivo las comillas van escapadas (\"), asi que un grep con comilla
  # literal no matchea nunca y el caso pasaria por el motivo equivocado.
  destinos_guardados() {
    jq -r '[ .hooks.events[][] | .hooks[].command // empty ][]' "$zcode_cfg" 2>/dev/null \
      | sed -n 's/.*--only-cwd "\([^"]*\)".*/\1/p' | sort -u
  }

  caso "H2: instalar para B estando A agrega las entradas de B"
  fabricar_zcode_config
  rA="$SANDBOX/zc-repo-A"; rB="$SANDBOX/zc-repo-B"
  rm -rf "$rA" "$rB"; mkdir -p "$rA" "$rB"
  absA="$(cd "$rA" && pwd -P)"; absB="$(cd "$rB" && pwd -P)"
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$rA" --host zcode >/dev/null 2>&1
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$rB" --host zcode >/dev/null 2>&1
  destinos_guardados | grep -qx -- "$absA" \
    || malo "precondicion rota: las entradas de A no estan"
  destinos_guardados | grep -qx -- "$absB" \
    || malo "las entradas de B no se agregaron: has_tag decide por evento+tag y el tag ya estaba por A"

  caso "H2: --quitar B NO se lleva las entradas vivas de A"
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --quitar "$rB" --host zcode >/dev/null 2>&1
  destinos_guardados | grep -qx -- "$absA" \
    || malo "BORRO los hooks vivos de A: 'ours' matchea el capture-id sin mirar el destino"
  if destinos_guardados | grep -qx -- "$absB"; then
    malo "no quito las entradas de B"
  fi

  # ---- z10: el resumen de --quitar no puede contar destinos ajenos --------
  # Hallazgo 4 de la revision cruzada (kimi, 2026-08-13): tras el fix H2,
  # n_antes/n_despues seguian contando TODAS las entradas 5.1 del config
  # compartido, asi que el resumen mentia justo en el caso multi-repo que H2
  # arregla. Misma familia que el unknown-publicado-como-PASS de la Task 1.5:
  # el defecto esta en el REPORTE, no en la accion.
  caso "H2: el resumen de --quitar cuenta solo el destino, no todos"
  fabricar_zcode_config
  rm -rf "$rA" "$rB"; mkdir -p "$rA" "$rB"
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$rA" --host zcode >/dev/null 2>&1
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --instalar "$rB" --host zcode >/dev/null 2>&1
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --quitar "$rB" --host zcode 2>&1)"
  printf '%s' "$out" | grep -qE 'antes: *5 +despues: *0' \
    || malo "el resumen cuenta las entradas de TODOS los destinos (esperaba 5 -> 0): $out"

  echo "  test_capture_payloads: zcode OK"
fi

# ============================================================
# Task 6.1 -- --host codex: la captura es COLOCACION DE ARCHIVO, no mutacion
# de config. Medido: ~/.codex/hooks/summonaikit-harness.ps1 resuelve su hook
# con `git rev-parse --show-toplevel` y PREFIERE <repo>/.codex/hooks/
# summonaikit-harness.sh cuando existe. Por eso alcanza con dejar el shim ahi
# y el registro que ya existe en ~/.codex/hooks.json lo invoca: el config del
# operador NO se toca en ningun momento. Sin jq, a diferencia de zcode.
# ============================================================
cdx="$SANDBOX/repo-codex"
mkdir -p "$cdx" && ( cd "$cdx" && git init -q )
shim="$cdx/.codex/hooks/summonaikit-harness.sh"

caso "codex --instalar deja el shim en la ruta que el .ps1 prefiere"
out="$(bash "$tool" --instalar "$cdx" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$shim" ] || malo "no escribio $shim"
grep -q -- '--saikit-capture-id 6.1' "$shim" 2>/dev/null || malo "el shim no lleva el marcador de propiedad"
bash -n "$shim" 2>/dev/null || malo "el shim no parsea: romperia todos los turnos siguientes"
if grep -q '__REPO__\|__CAPTURADOR__' "$shim" 2>/dev/null; then
  malo "quedaron placeholders sin sustituir en el shim"
fi

caso "codex: un directorio sin git se rechaza (el .ps1 no lo elegiria)"
sing="$SANDBOX/codex-sin-git"
rm -rf "$sing"; mkdir -p "$sing"
out="$(bash "$tool" --instalar "$sing" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: sin repo git el shim queda puesto y no corre nunca"
[ ! -e "$sing/.codex" ] || malo "rechazo pero dejo el arbol puesto"

caso "codex --instalar NO pisa un hook ajeno"
ajeno="$SANDBOX/codex-ajeno"
rm -rf "$ajeno"; mkdir -p "$ajeno/.codex/hooks" && ( cd "$ajeno" && git init -q )
printf '#!/usr/bin/env bash\n# de otro\n' > "$ajeno/.codex/hooks/summonaikit-harness.sh"
antes_ajeno="$(cksum < "$ajeno/.codex/hooks/summonaikit-harness.sh")"
out="$(bash "$tool" --instalar "$ajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "pisar un hook ajeno debe fallar, dio $rc"
[ "$antes_ajeno" = "$(cksum < "$ajeno/.codex/hooks/summonaikit-harness.sh")" ] \
  || malo "PISO el hook del usuario"

caso "codex: la fase entra en el nombre aunque el payload no traiga hook_event_name"
# El env va sobre el `bash "$shim"`, NO sobre el printf: en un pipeline el
# prefijo VAR=val solo alcanza al comando que precede, y ponerlo del lado del
# printf deja al shim sin la fase (medido: el archivo salia 'sin-fase').
( cd "$cdx" && printf '{"session_id":"x"}' | SUMMONAIKIT_HOOK_PHASE=stop bash "$shim" ) 2>/dev/null
ls "$cdx"/capturas/*stop*.json >/dev/null 2>&1 \
  || malo "sin hook_event_name las 3 fases colisionarian en 'sin-evento': el --tag es lo que las separa"

caso "codex: el env dump contesta la pregunta del TARGET que pide la DoD"
( cd "$cdx" && printf '{"hook_event_name":"UserPromptSubmit"}' \
    | SUMMONAIKIT_HOOK_PHASE=prompt SUMMONAIKIT_HOOK_TARGET=codex bash "$shim" ) 2>/dev/null
grep -rq 'SUMMONAIKIT_HOOK_TARGET=codex' "$cdx"/capturas/ 2>/dev/null \
  || malo "el env dump no trae el TARGET; sin eso la DoD de 6.1 no se puede contestar"

caso "codex --quitar deja la ruta limpia"
out="$(bash "$tool" --quitar "$cdx" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ ! -f "$shim" ] || malo "no quito el shim propio"

caso "codex --quitar NO borra un shim ajeno"
out="$(bash "$tool" --quitar "$ajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "borrar lo ajeno para 'limpiar' es el mismo error que pisarlo, dio $rc"
[ -f "$ajeno/.codex/hooks/summonaikit-harness.sh" ] || malo "BORRO el hook del usuario"

# ------------------------------ H1 (CodeRabbit PR#2, abierto hasta hoy) -----
# `--host)` tomaba ${2:-}, que con el flag al final queda vacio, y luego
# host="${host:-claude}" lo convertia en 'claude'. Un typo en el flag no falla:
# captura mal y se descubre con la captura vacia, o sea quemando una sesion con
# el operador adelante. Afecta a los TRES hosts.
caso "H1: --host sin valor sale 2 y NO instala el host equivocado"
h1="$SANDBOX/repo-h1"
rm -rf "$h1"; mkdir -p "$h1" && ( cd "$h1" && git init -q )
out="$(bash "$tool" --instalar "$h1" --host 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: cae al default 'claude' y captura el host equivocado"
[ ! -f "$h1/.claude/settings.json" ] || malo "instalo el host equivocado en silencio"

caso "H1: --host con valor vacio tambien sale 2"
rm -rf "$h1"; mkdir -p "$h1" && ( cd "$h1" && git init -q )
out="$(bash "$tool" --instalar "$h1" --host '' 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: '' vuelve a caer en el default por \${host:-claude}"
[ ! -f "$h1/.claude/settings.json" ] || malo "instalo con host vacio"

# --------------- Hallazgos 2 y 3 de la revision cruzada (kimi, 2026-08-13) ---
# H-2: `git rev-parse` falla IGUAL si git no esta instalado que si el directorio
# no es un repo, y el mensaje acusaba al directorio. Es la Core Rule 2 en
# chiquito: "no se pudo mirar" reportado como "se miro y falta".
caso "codex: git ausente se reporta como tal, no como 'no es repo git'"
sg="$SANDBOX/codex-git-ausente"
rm -rf "$sg"; mkdir -p "$sg" && ( cd "$sg" && git init -q )   # SI es repo git
# Portabilidad (hallazgo de CodeRabbit en el PR#10): `PATH=/usr/bin` esconde
# git SOLO donde git vive en otro lado -- en MSYS esta en /mingw64/bin. En una
# distro Linux tipica git ES /usr/bin/git, y ahi el escenario no se puede
# montar: `command -v git` acierta, el install sale 0, y el caso fallaria por
# el motivo equivocado. Eso es "no se pudo medir", no un fallo -- mismo
# criterio que el caso de los enlaces simbolicos de mas arriba (Core Rule 2).
if PATH=/usr/bin command -v git >/dev/null 2>&1; then
  echo "    unknown: git resuelve dentro de /usr/bin en esta maquina; el caso no se pudo montar"
else
  out="$(PATH=/usr/bin bash "$tool" --instalar "$sg" --host codex 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "esperaba exit 2, dio $rc: $out"
  printf '%s' "$out" | grep -qiE 'no encontr|no esta instalado|no se pudo' \
    || malo "acusa al directorio cuando el problema es que git no esta: $out"
  [ ! -e "$sg/.codex" ] || malo "rechazo pero dejo el arbol puesto"
fi

# H-3: el shim hace `exec bash <ruta absoluta al capturador>`. Si ese repo se
# mueve o se borra con el shim puesto, el shim muere con exit != 0 en CADA fase
# y rompe los turnos del host. El fail-open del modo hook no cubre al shim: el
# shim tiene que ser fail-open POR SI MISMO.
caso "codex: el shim es fail-open si el capturador ya no esta"
tmpcap="$SANDBOX/copia-tool"
rm -rf "$tmpcap"; mkdir -p "$tmpcap"
cp "$tool" "$tmpcap/capture-payloads.sh"
sf="$SANDBOX/codex-shim-huerfano"
rm -rf "$sf"; mkdir -p "$sf" && ( cd "$sf" && git init -q )
bash "$tmpcap/capture-payloads.sh" --instalar "$sf" --host codex >/dev/null 2>&1
[ -f "$sf/.codex/hooks/summonaikit-harness.sh" ] || malo "precondicion: no se instalo el shim"
rm -f "$tmpcap/capture-payloads.sh"    # el capturador desaparece
printf '{"hook_event_name":"Stop"}' \
  | ( cd "$sf" && SUMMONAIKIT_HOOK_PHASE=stop bash "$sf/.codex/hooks/summonaikit-harness.sh" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || malo "el shim con capturador ausente salio $rc: romperia cada turno del host"

echo "  test_capture_payloads: codex OK"

# ============================================================
# Task 7.1 -- --host grok: colocacion de archivo, como codex, pero aca el
# registro es un JSON PROPIO en <repo>/.grok/hooks/ (Grok corre hooks de
# proyecto tras trust del folder) y cada handler lleva el env map
# SUMMONAIKIT_HOOK_TARGET=grok -- medir si ese env llega de verdad es una de
# las preguntas de la 7.1. PostToolUse se registra TRES veces a proposito:
# matcher estilo Claude (Bash|Edit|Write|Task), matcher con los nombres
# nativos y sin matcher. Es la leccion de la 6.1: hay que distinguir "el host
# no emite el evento" de "el matcher lo filtro", y eso solo se ve si las tres
# variantes llevan --tag distinto desde el primer turno.
# ============================================================
if ! command -v jq >/dev/null 2>&1; then
  # El install de grok no necesita jq, pero validar que el JSON generado
  # PARSEA si. Sin jq no se puede medir; se declara unknown (unknown != verde).
  echo "  caso: --host grok requiere jq para validar el JSON -> UNKNOWN (jq no disponible)"
  echo "  test_capture_payloads: grok skip (unknown)"
else
  grk="$SANDBOX/repo-grok"
  mkdir -p "$grk"
  gjson="$grk/.grok/hooks/saikit-capture.json"

  # ---- g1: instalar crea el JSON de registro con los 5 eventos --------------
  caso "grok --instalar crea .grok/hooks/saikit-capture.json parseable con los 5 eventos"
  out="$(bash "$tool" --instalar "$grk" --host grok 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
  [ -f "$gjson" ] || malo "no escribio $gjson"
  jq -e . "$gjson" >/dev/null 2>&1 || malo "el JSON generado no parsea"
  jq -e '.hooks | has("UserPromptSubmit") and has("PostToolUse") and has("PostToolUseFailure") and has("SubagentStart") and has("Stop")' \
        "$gjson" >/dev/null || malo "faltan eventos: se piden UserPromptSubmit, PostToolUse, PostToolUseFailure, SubagentStart, Stop"

  caso "grok: PostToolUse lleva las 3 variantes (alias Claude, nativos, sin matcher)"
  jq -e '[.hooks.PostToolUse[] | select(.matcher=="Bash|Edit|Write|Task")] | length==1' "$gjson" >/dev/null \
    || malo "falta la entrada PostToolUse con matcher estilo Claude"
  jq -e '[.hooks.PostToolUse[] | select(.matcher=="run_terminal_command|search_replace|spawn_subagent")] | length==1' "$gjson" >/dev/null \
    || malo "falta la entrada PostToolUse con los nombres nativos"
  jq -e '[.hooks.PostToolUse[] | select(has("matcher")|not)] | length==1' "$gjson" >/dev/null \
    || malo "falta la entrada PostToolUse sin matcher (distingue no-emite de matcher-filtra)"

  caso "grok: UserPromptSubmit, SubagentStart, Stop y PostToolUseFailure van sin matcher"
  for ev in UserPromptSubmit SubagentStart Stop PostToolUseFailure; do
    jq -e --arg ev "$ev" '[.hooks[$ev][] | select(has("matcher"))] | length==0' "$gjson" >/dev/null \
      || malo "$ev no deberia llevar matcher (captura: ver todo lo que el host emite)"
  done

  caso "grok: TODO handler lleva el env map SUMMONAIKIT_HOOK_TARGET=grok y el capture-id"
  jq -e '[.hooks | to_entries[] | .value[] | .hooks[]] | all(.env.SUMMONAIKIT_HOOK_TARGET=="grok")' \
        "$gjson" >/dev/null || malo "hay handlers sin el env map TARGET=grok"
  jq -e '[.hooks | to_entries[] | .value[] | .hooks[]] | all(.command | contains("--saikit-capture-id 7.1"))' \
        "$gjson" >/dev/null || malo "hay handlers sin el marker de propiedad --saikit-capture-id 7.1"
  for t in ups ptu-alias ptu-native ptu-all ptuf sub stop; do
    grep -q -- "--tag $t" "$gjson" || malo "falta --tag $t (sin tags no se distingue que entrada disparo)"
  done

  caso "grok --instalar deja marca de propiedad, capturas ignoradas y NO toca otros hosts"
  [ -f "$grk/.grok/.capture-payloads-owned" ] || malo "no dejo marca .grok/.capture-payloads-owned"
  [ -f "$grk/capturas/.gitignore" ] || malo "no ignoro capturas/"
  [ ! -e "$grk/.claude" ] || malo "creo .claude en modo grok"
  [ ! -e "$grk/.codex" ]  || malo "creo .codex en modo grok"
  [ ! -e "$grk/.zcode" ]  || malo "creo .zcode en modo grok"

  # ---- g2: no pisa un JSON ajeno ---------------------------------------------
  caso "grok --instalar NO pisa un saikit-capture.json ajeno"
  gajeno="$SANDBOX/grok-ajeno"
  rm -rf "$gajeno"; mkdir -p "$gajeno/.grok/hooks"
  printf '{"mio":true}\n' > "$gajeno/.grok/hooks/saikit-capture.json"
  antes_gajeno="$(cksum < "$gajeno/.grok/hooks/saikit-capture.json")"
  out="$(bash "$tool" --instalar "$gajeno" --host grok 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "pisar un JSON ajeno debe fallar, dio $rc"
  [ "$antes_gajeno" = "$(cksum < "$gajeno/.grok/hooks/saikit-capture.json")" ] \
    || malo "PISO el JSON del usuario"

  # ---- g3: reinstalar es idempotente ------------------------------------------
  caso "grok segunda --instalar no duplica ni rompe (idempotente)"
  out="$(bash "$tool" --instalar "$grk" --host grok 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "segunda instalacion debe ser exit 0, dio $rc: $out"
  jq -e . "$gjson" >/dev/null 2>&1 || malo "la segunda instalacion dejo el JSON roto"
  n_json="$(find "$grk/.grok/hooks" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
  [ "$n_json" -eq 1 ] || malo "hay $n_json JSON en .grok/hooks, esperaba 1"

  # ---- g4: quitar saca solo lo propio ------------------------------------------
  caso "grok --quitar saca JSON y marca propios, respeta vecinos ajenos"
  printf '{"ajeno":true}\n' > "$grk/.grok/hooks/other.json"
  antes_other="$(cksum < "$grk/.grok/hooks/other.json")"
  out="$(bash "$tool" --quitar "$grk" --host grok 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
  [ ! -f "$gjson" ] || malo "no quito el JSON propio"
  [ ! -f "$grk/.grok/.capture-payloads-owned" ] || malo "dejo la marca colgada"
  [ -f "$grk/.grok/hooks/other.json" ] || malo "BORRO el JSON vecino ajeno"
  [ "$antes_other" = "$(cksum < "$grk/.grok/hooks/other.json" 2>/dev/null)" ] \
    || malo "MODIFICO el JSON vecino ajeno"

  # ---- g5: quitar sin --host infiere grok por la marca --------------------------
  caso "grok --quitar sin --host infiere el host por la marca .grok"
  bash "$tool" --instalar "$grk" --host grok >/dev/null 2>&1
  out="$(bash "$tool" --quitar "$grk" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
  [ ! -f "$gjson" ] || malo "sin --host no quito el JSON (no infirio grok por la marca)"

  # ---- g6: quitar NO borra un JSON que ya no es nuestro -------------------------
  caso "grok --quitar NO borra un saikit-capture.json que ya no lleva el capture-id"
  bash "$tool" --instalar "$grk" --host grok >/dev/null 2>&1
  printf '{"cambiado":"por el usuario"}\n' > "$gjson"
  out="$(bash "$tool" --quitar "$grk" --host grok 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "borrar un JSON que ya no es nuestro debe fallar, dio $rc"
  grep -q 'cambiado' "$gjson" || malo "BORRO/MODIFICO el JSON que el usuario cambio"
  rm -rf "$grk/.grok"   # limpieza del caso

  # ---- g7: el perfil real de grok queda rechazado -------------------------------
  caso "grok se niega a instalar si el dest resuelve a \$HOME/.grok"
  mkdir -p "$HOME/.grok"   # $HOME es el del sandbox
  out="$(bash "$tool" --instalar "$HOME/.grok" --host grok 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "instalar sobre \$HOME/.grok debe fallar (dio $rc)"
  [ ! -e "$HOME/.grok/.grok" ] && [ ! -f "$HOME/.grok/hooks/saikit-capture.json" ] \
    || malo "escribio adentro del perfil grok"

  echo "  test_capture_payloads: grok OK"
fi

# ---- g8/g9: el modo hook entiende el envelope camel de Grok ------------------
# Estos casos no necesitan jq: miden al capturador actuando de hook, no el JSON.
caso "grok modo hook: hookEventName (camel) entra en el nombre del archivo"
grkcap="$SANDBOX/cap-grok"
printf '%s' '{"hookEventName":"UserPromptSubmit","prompt":"x"}' \
  | ( cd "$SANDBOX" && SAIKIT_CAPTURE_DIR="$grkcap" bash "$tool" ); rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto con envelope camel (dio $rc)"
[ -n "$(find "$grkcap" -name '*UserPromptSubmit*.json' 2>/dev/null | head -1)" ] \
  || malo "no nombro el archivo por hookEventName: los eventos de Grok colisionarian en 'sin-evento'"

caso "grok modo hook: el env dump trae GROK_HOOK_EVENT/GROK_SESSION_ID y NUNCA GROK_API_KEY"
# Dir PROPIO para este caso (18.16): el `find | head -1` de antes elegia entre
# el .env del caso anterior y el de este segun el orden de directorio de
# find — en macOS (APFS) devolvia el del caso anterior (sin GROK_*) y el caso
# fallaba por orden de listado, no por comportamiento del capturador.
grkcap9="$SANDBOX/cap-grok-env"
rm -rf "$grkcap9"; mkdir -p "$grkcap9"
printf '%s' '{"hookEventName":"Stop","reason":"end_turn"}' \
  | ( cd "$SANDBOX" && SAIKIT_CAPTURE_DIR="$grkcap9" \
      GROK_HOOK_EVENT=stop GROK_SESSION_ID=g123 GROK_WORKSPACE_ROOT=/x \
      GROK_API_KEY=no-volcar-esto bash "$tool" ); rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto con env grok (dio $rc)"
envfile="$(find "$grkcap9" -name '*.env' 2>/dev/null | head -1)"
[ -n "$envfile" ] || malo "no escribio el .env"
grep -q 'GROK_HOOK_EVENT=stop' "$envfile" 2>/dev/null || malo "el env dump no trae GROK_HOOK_EVENT (D2 no se puede medir)"
grep -q 'GROK_SESSION_ID=g123' "$envfile" 2>/dev/null || malo "el env dump no trae GROK_SESSION_ID"
grep -q 'GROK_API_KEY' "$envfile" 2>/dev/null \
  && malo "el env dump volco GROK_API_KEY: la allowlist es por NOMBRE, nunca por prefijo GROK_"

if [ "$fail" -ne 0 ]; then
  echo "test_capture_payloads: FAIL" >&2
  exit 1
fi
echo "test_capture_payloads: OK"
