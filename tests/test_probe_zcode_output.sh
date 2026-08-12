#!/usr/bin/env bash
# Task 5.2 — el probe de stdout/exit tiene que emitir byte a byte lo que el plan
# pide, no interferir en el evento equivocado, y dejar el side-channel .ok como
# prueba de que corrio (el log de zcode NO sirve: un hook OK no deja stdout/stderr
# ahi, y transcript_path es un tmp que cleanup() borra).
#
# Dos caras, mismo binario. La cara HOOK se prueba en §A2 (comportamiento); la
# cara --instalar/--quitar en §A3 (registro en el user-config, respeta vecinos y
# 5.1). Core Rule 4: nada toca el ~/.zcode real — todo via SAIKIT_ZCODE_USER_CONFIG
# apuntando al sandbox, con vecinos ajenos de mentira.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
tool="$repo/tools/probe-zcode-output.sh"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# Captura reutilizable: el probe escribe a $OF (stdout) y $EF (stderr); $RC = exit.
OF="$(mktemp)"; EF="$(mktemp)"

# stdout exacto (con el \n final que emite el probe). $1 = JSON sin \n final.
stdout_is() {
  local expf; expf="$(mktemp)"
  printf '%s\n' "$1" > "$expf"
  cmp -s "$OF" "$expf" || malo "stdout no calza: esperaba [$1] tengo [$(cat "$OF")]"
  rm -f "$expf"
}
stdout_is_empty() {
  [ -s "$OF" ] && malo "esperaba stdout vacio, tengo [$(cat "$OF")]" || true
}

# mode-file en $WORK; probe-ran cae en $WORK/probe-ran.
WORK="$SANDBOX/work"
mkdir -p "$WORK"
mf="$WORK/probe-mode.txt"
ok_of() { printf '%s/probe-ran/%s.ok' "$WORK" "$1"; }   # $1=nonce

UPS='{"hook_event_name":"UserPromptSubmit","prompt":"x"}'
STOP='{"hook_event_name":"Stop"}'

# ============================================================ §A2.1 cada modo
caso "context (UPS): forma 1 exacta + exit 0 + .ok"
printf '%s' "$UPS" | SAIKIT_PROBE_NONCE=AAAA bash "$tool" --mode context --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "context: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-CONTEXT-AAAA"}}'
[ -f "$(ok_of AAAA)" ] || malo "context: no escribio .ok"

caso "extra (UPS): forma 1 + clave extra saikitProbe + exit 0 + .ok"
printf '%s' "$UPS" | SAIKIT_PROBE_NONCE=BBBB bash "$tool" --mode extra --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "extra: exit $RC"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-EXTRA-BBBB"},"saikitProbe":true}'
grep -q saikitProbe "$OF" || malo "extra: falta saikitProbe"
grep -q additionalContext "$OF" || malo "extra: falta additionalContext"
[ -f "$(ok_of BBBB)" ] || malo "extra: no escribio .ok"

caso "block0 (Stop): forma 2 con exit 0 (no 2) + .ok"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=CCCC bash "$tool" --mode block0 --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "block0: exit $RC (esperaba 0, no 2)"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-CCCC"}'
[ -f "$(ok_of CCCC)" ] || malo "block0: no escribio .ok"

caso "budget (Stop): forma 3 + exit 0 + .ok"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=DDDD bash "$tool" --mode budget --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "budget: exit $RC"
stdout_is '{"continue":false,"stopReason":"PROBE-BUDGET-DDDD"}'
[ -f "$(ok_of DDDD)" ] || malo "budget: no escribio .ok"

caso "notice (Stop): forma 4 + exit 0 + .ok"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=EEEE bash "$tool" --mode notice --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "notice: exit $RC"
stdout_is '{"systemMessage":"PROBE-NOTICE-EEEE"}'
[ -f "$(ok_of EEEE)" ] || malo "notice: no escribio .ok"

# ============================================================ §A2.5 exit2 (Stop)
caso "exit2 (Stop): stdout vacio + stderr con nonce + exit 2 + .ok"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=FFFF bash "$tool" --mode exit2 --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 2 ] || malo "exit2: exit $RC (esperaba 2)"
stdout_is_empty
grep -q 'PROBE-EXIT2-FFFF' "$EF" || malo "exit2: stderr sin el nonce"
[ -f "$(ok_of FFFF)" ] || malo "exit2: no escribio .ok"

# ============================================================ §A2.2 evento incorrecto
caso "modos Stop con evento UPS => vacio, exit 0, SIN .ok"
for m in block0 budget notice exit2; do
  rm -f "$WORK/probe-ran"/X$m.ok 2>/dev/null
  printf '%s' "$UPS" | SAIKIT_PROBE_NONCE=X$m bash "$tool" --mode "$m" --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "$m en UPS: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(ok_of "X$m")" ] && malo "$m en UPS: escribio .ok (no debia)" || true
done

caso "modos UPS con evento Stop => vacio, exit 0, SIN .ok"
for m in context extra; do
  printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=Y$m bash "$tool" --mode "$m" --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "$m en Stop: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(ok_of "Y$m")" ] && malo "$m en Stop: escribio .ok (no debia)" || true
done

# ============================================================ §A2.3 basura / ausente
caso "modo basura => vacio, exit 0, SIN .ok"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=ZZZZ bash "$tool" --mode estoNoExiste --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "basura: exit $rc"
stdout_is_empty
[ -f "$(ok_of ZZZZ)" ] && malo "basura: escribio .ok (no debia)" || true

caso "modo ausente (sin --mode ni env ni file) => empty => vacio, exit 0, .ok SIEMPRE (control)"
rm -f "$mf"; printf '   \n' > "$mf"   # file con solo espacios => normaliza a empty
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=WWWW bash "$tool" --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "ausente: exit $rc"
stdout_is_empty
[ -f "$(ok_of WWWW)" ] || malo "empty/control: NO escribio .ok (debe, es la prueba de que corrio)"

# ============================================================ §A2.4 --only-cwd ajeno
caso "--only-cwd de otro dir => vacio, exit 0, SIN .ok (aun siendo exit2 + Stop)"
otro="$SANDBOX/otro-cwd"; mkdir -p "$otro"
rm -f "$WORK/probe-ran"/CWD1.ok 2>/dev/null
( cd "$otro" && printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=CWD1 bash "$tool" --mode exit2 --only-cwd "$WORK" --mode-file "$mf" ) >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "only-cwd ajeno: exit $rc (esperaba 0)"
stdout_is_empty
[ -f "$(ok_of CWD1)" ] && malo "only-cwd ajeno: escribio .ok (no debia)" || true

caso "--only-cwd correcto => emite normal (el gate no falsea negativos)"
rm -f "$WORK/probe-ran"/CWD2.ok 2>/dev/null
( cd "$WORK" && printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=CWD2 bash "$tool" --mode block0 --only-cwd "$WORK" --mode-file "$mf" ) >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "only-cwd correcto: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-CWD2"}'
[ -f "$(ok_of CWD2)" ] || malo "only-cwd correcto: no escribio .ok"

# ============================================================ bonus: camelCase
caso "lee hookEventName (camel) si hook_event_name falta — zcode emite ambos (5.1)"
printf '%s' '{"hookEventName":"Stop"}' | SAIKIT_PROBE_NONCE=CAML bash "$tool" --mode budget --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "camel: exit $rc"
stdout_is '{"continue":false,"stopReason":"PROBE-BUDGET-CAML"}'

# ============================================================ REGRESIÓN zcode realista
# Payload REALISTA de zcode (CLI 3.7.5-11): evento en camelCase (esta medición vio
# SOLO hookEventName en Stop, 0 snake) + responseText largo con UTF-8 multibyte
# (acentos, emoji, backticks, \n escapados). Defecto propio hallado en el auto-test
# del modo empty: el sed con .* greedy + [^"]* cruzaba comillas en C.UTF-8 con
# GNU sed 4.9 sobre estos bytes (daba "Stopï\n\nEstoy..." en vez de "Stop"), asi
# que NINGÚN modo Stop emitia. grep -o (leftmost) no tiene ese problema. Este es
# el test que lo habria atrapado.
STOP_REAL='{"cwd":"C:\\dev\\demo-repo","hookEventName":"Stop","mode":"yolo","responsePreview":"¡Hola! 👋\n\nEstoy listo para ayudarte con el repositorio. ¿Qué querés hacer? Por ejemplo:\n\n- Implementar o arreglar algo\n- Explorar el código\n- Correr pre-commit\n- Otra cosa\n\nDecime y arrancamos.","responseText":"¡Hola! 👋\n\nEstoy listo para ayudarte con el repositorio. ¿Qué querés hacer? Por ejemplo:\n\n- Implementar o arreglar algo\n- Explorar el código\n- Correr pre-commit\n- Otra cosa\n\nDecime y arrancamos.","stop_hook_active":false}'

caso "REGRESIÓN: budget + payload Stop realista de zcode (UTF-8) => forma 3"
printf '%s' "$STOP_REAL" | SAIKIT_PROBE_NONCE=REAL1 bash "$tool" --mode budget --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "regresión budget: exit $rc"
stdout_is '{"continue":false,"stopReason":"PROBE-BUDGET-REAL1"}'
[ -f "$(ok_of REAL1)" ] || malo "regresión budget: no escribió .ok"

caso "REGRESIÓN: exit2 + payload Stop realista de zcode => exit 2 + .ok + stderr nonce"
printf '%s' "$STOP_REAL" | SAIKIT_PROBE_NONCE=REAL2 bash "$tool" --mode exit2 --mode-file "$mf" >"$OF" 2>"$EF"; rc=$?
[ "$rc" -eq 2 ] || malo "regresión exit2: exit $rc (esperaba 2)"
stdout_is_empty
grep -q 'PROBE-EXIT2-REAL2' "$EF" || malo "regresión exit2: stderr sin nonce"
[ -f "$(ok_of REAL2)" ] || malo "regresión exit2: no escribió .ok"

# ============================================================ §A2.7 bash -n
caso "el probe es bash -n valido"
bash -n "$tool" 2>/dev/null || malo "bash -n fallo en el probe"

# ============================================================
# §A3 — --instalar / --quitar en el user-config (respeta vecinos y 5.1)
# ============================================================
if ! command -v jq >/dev/null 2>&1; then
  echo "  caso: --instalar/--quitar requieren jq -> UNKNOWN (jq no disponible)"
  echo "  test_probe_zcode_output: install/quitar skip (unknown)"
else
  zhome="$SANDBOX/zcode-home"
  zcfg="$zhome/.zcode/cli/config.json"
  zdesc="$SANDBOX/zcode-repo"
  mkdir -p "$zdesc"

  fabricar_zcode_config() {
    rm -rf "$zhome"; mkdir -p "$zhome/.zcode/cli"
    cat > "$zcfg" <<'JSON'
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

  # ---- i1: instalar appendea 2 entradas, respeta vecinos, no toca .claude ----
  caso "instalar: 2 entradas 5.2 (UPS+Stop), vecinos intactos, backup, no .claude"
  fabricar_zcode_config
  session_antes="$(jq -c '.hooks.events.SessionStart' "$zcfg")"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar: exit $rc: $out"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 2 ] || malo "instalar: esperaba 2 entradas 5.2, hay $n52"
  # 5.1 ausente (no lo inventamos).
  n51="$(grep -c 'saikit-capture-id 5\.1' "$zcfg" || true)"
  [ "$n51" -eq 0 ] || malo "instalar: aparecieron entradas 5.1 (no debieran)"
  # UPS y Stop sin matcher.
  jq -e '(.hooks.events.UserPromptSubmit|length)==1 and (.hooks.events.UserPromptSubmit[0]|has("matcher")|not)' "$zcfg" >/dev/null \
    || malo "UPS: debe ser 1 entrada sin matcher"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("saikit-probe-id 5[.]2")))] | length==1 and (.[0]|has("matcher")|not)' "$zcfg" >/dev/null \
    || malo "Stop: debe tener 1 entrada 5.2 sin matcher"
  # type command, --only-cwd al dest, --mode-file al dest/probe-mode.txt.
  jq -e 'all(.hooks.events.UserPromptSubmit[].hooks[]; .type=="command")' "$zcfg" >/dev/null \
    || malo "UPS: type debe ser command"
  stored_cwd="$(jq -r '[.hooks.events[][] | .hooks[].command // empty | select(contains("--only-cwd"))][0]' "$zcfg" \
                | sed -n 's/.*--only-cwd "\([^"]*\)".*/\1/p')"
  [ "$stored_cwd" = "$(cd "$zdesc" && pwd -P)" ] || malo "--only-cwd no apunta al dest: [$stored_cwd]"
  grep -q -- "--mode-file" "$zcfg" && grep -q 'probe-mode.txt' "$zcfg" || malo "falta --mode-file <dest>/probe-mode.txt"
  # No toca .claude.
  [ ! -f "$zdesc/.claude/settings.json" ] || malo "instalar escribio .claude/settings.json"
  # Marca + mode-file inicial empty + dir probe-ran.
  [ -f "$zdesc/.zcode/.probe-zcode-owned" ] || malo "falta marca .probe-zcode-owned"
  [ "$(cat "$zdesc/probe-mode.txt" 2>/dev/null)" = "empty" ] || malo "probe-mode.txt no empezo en empty"
  [ -d "$zdesc/probe-ran" ] || malo "no creo probe-ran/"
  # Vecinos ajenos intactos; backup existe y NO dentro del dest git.
  [ "$session_antes" = "$(jq -c '.hooks.events.SessionStart' "$zcfg")" ] || malo "modifico SessionStart ajeno"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' "$zcfg" >/dev/null \
    || malo "borro el Stop dummy ajeno (§A3 test 1)"
  [ -d "$zhome/.zcode/cli/saikit-backups" ] || malo "no creo backup junto al user-config"
  [ -z "$(find "$zdesc" -name '*.bak' 2>/dev/null)" ] || malo "el backup cayo adentro del dest git"

  # ---- i2: idempotente (2da vez no duplica) --------------------------------
  caso "instalar: 2da vez no duplica (idempotente por entrada)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "2da instalar: exit $rc"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 2 ] || malo "2da instalar duplico (hay $n52, esperaba 2)"

  # ---- i3: parcial (falta Stop) => agrega solo Stop -------------------------
  caso "instalar: si falta 1 de 2, agrega solo la que falta"
  fabricar_zcode_config
  SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" >/dev/null 2>&1
  # Quitar manualmente la entrada Stop del probe (dejar UPS).
  tmpq="$(mktemp)"
  jq 'def probe52: any((.hooks // [])[]; ((.command // "") | test("saikit-probe-id 5[.]2")));
       .hooks.events.Stop = ((.hooks.events.Stop // []) | map(select(probe52 | not)))' \
     "$zcfg" > "$tmpq" && mv -f "$tmpq" "$zcfg"
  ups_antes="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$ups_antes" -eq 1 ] || malo "precondicion parcial: UPS sola (hay $ups_antes)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar parcial: exit $rc"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 2 ] || malo "parcial: esperaba 2 (repone Stop), hay $n52"
  jq -e '.hooks.events.UserPromptSubmit|length==1' "$zcfg" >/dev/null || malo "parcial: duplico UPS"

  # ---- i4: temp invalido no rompe el vivo ----------------------------------
  # Simula un jq que escribe basura: pasamos un config roto y exigimos exit != 0
  # sin que el config original se pierda. (jq falla antes del mv.)
  caso "instalar: si jq falla, el config original queda intacto"
  fabricar_zcode_config
  snap="$(cksum < "$zcfg")"
  # config invalido: jq no podra leerlo.
  printf 'no-es-json' > "$zcfg.bak.bad"
  cp -f "$zcfg" "$zcfg.keep"
  printf 'no-es-json' > "$zcfg"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "config roto: esperaba exit != 0, dio $rc"
  [ "$(cat "$zcfg")" = "no-es-json" ] || malo "config roto: se modifico igual"
  cp -f "$zcfg.keep" "$zcfg"; rm -f "$zcfg.keep" "$zcfg.bak.bad"
  [ "$snap" = "$(cksum < "$zcfg")" ] || malo "snap tras restaurar no calza"

  # ---- i5: dest = $HOME/.zcode => exit 2 -----------------------------------
  caso "instalar: dest = \$HOME/.zcode => exit 2 (no toca el perfil)"
  fabricar_zcode_config
  mkdir -p "$HOME/.zcode"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$HOME/.zcode" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "instalar sobre \$HOME/.zcode debia fallar (dio $rc)"
  grep -q 'saikit-probe-id' "$zcfg" && malo "escribio el config con dest=perfil" || true

  # ---- q1: --quitar saca solo 5.2; deja dummy, 5.1 y SessionStart -----------
  caso "quitar: saca solo 5.2; deja Stop dummy, entrada 5.1 y SessionStart (§A3 test 2)"
  fabricar_zcode_config
  SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" >/dev/null 2>&1
  # Inyectar una entrada 5.1 ajena (capture-payloads) en Stop: NO debe borrarse.
  tmpq="$(mktemp)"
  jq '.hooks.events.Stop += [{"hooks":[{"type":"command","command":"bash /algo/capture-payloads.sh --saikit-capture-id 5.1","timeout":5}]}]' \
     "$zcfg" > "$tmpq" && mv -f "$tmpq" "$zcfg"
  n52_antes="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52_antes" -eq 2 ] || malo "precond quitar: 2 entradas 5.2 (hay $n52_antes)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --quitar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "quitar: exit $rc: $out"
  n52_desp="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52_desp" -eq 0 ] || malo "quitar: dejo $n52_desp entradas 5.2"
  jq -e '[.hooks.events.SessionStart[]]|length==1' "$zcfg" >/dev/null || malo "quitar borro SessionStart"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' "$zcfg" >/dev/null \
    || malo "quitar borro el Stop dummy"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("saikit-capture-id 5[.]1")))]|length==1' "$zcfg" >/dev/null \
    || malo "quitar borro la entrada 5.1 ajena"
  [ ! -f "$zdesc/.zcode/.probe-zcode-owned" ] || malo "quitar dejo la marca colgada"

  echo "  test_probe_zcode_output: install/quitar OK"
fi

if [ "$fail" -ne 0 ]; then
  echo "test_probe_zcode_output: FAIL" >&2
  exit 1
fi
echo "test_probe_zcode_output: OK"
