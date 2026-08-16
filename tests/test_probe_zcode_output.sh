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

# ====================================== §A2.6 familia session (Task 10.9)
# El canal de las reglas permanentes (10.6) sale por la fase de ARRANQUE, que
# ningun modo previo ejercita: context/extra son UPS y el resto son Stop. Los
# tres modos de acá son las tres formas que la 10.9 tiene que distinguir para no
# declarar `ignored` sin agotar el oraculo (leccion del cross-review de la 7.2).
#
# El texto lleva una INSTRUCCION observable a proposito: el oraculo del
# transcript dice si el host inyecto, y el modelo obedeciendo dice si le llego.
# Un veredicto necesita las dos.
SESSION='{"hook_event_name":"SessionStart","source":"startup"}'
SESSION_SNAKE='{"hookEventName":"session_start","source":"startup"}'

caso "session (SessionStart): forma 1 con hookEventName SessionStart + exit 0 + .ok"
printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=S001 bash "$tool" --mode session --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "session: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PROBE-SESSION-S001 reply with the literal token PROBE-SESSION-S001 in your answer"}}'
[ -f "$(ok_of S001)" ] || malo "session: no escribio .ok"

caso "session_snake (SessionStart): mismo envoltorio con hookEventName session_start"
printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=S002 bash "$tool" --mode session_snake --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "session_snake: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"session_start","additionalContext":"PROBE-SESSNAKE-S002 reply with the literal token PROBE-SESSNAKE-S002 in your answer"}}'
[ -f "$(ok_of S002)" ] || malo "session_snake: no escribio .ok"

caso "session_top (SessionStart): additionalContext top-level, sin envoltorio"
printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=S003 bash "$tool" --mode session_top --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "session_top: exit $RC (esperaba 0)"
stdout_is '{"additionalContext":"PROBE-SESSTOP-S003 reply with the literal token PROBE-SESSTOP-S003 in your answer"}'
[ -f "$(ok_of S003)" ] || malo "session_top: no escribio .ok"

caso "grok: la familia session dispara con el VALOR snake session_start"
printf '%s' "$SESSION_SNAKE" | SAIKIT_PROBE_NONCE=S004 bash "$tool" --host grok --mode session --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "grok session: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PROBE-SESSION-S004 reply with the literal token PROBE-SESSION-S004 in your answer"}}'
[ -f "$(ok_of S004)" ] || malo "grok session: no escribio .ok"

caso "grok: la familia session NO dispara con el valor CamelCase (es de zcode/codex)"
printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=S005 bash "$tool" --host grok --mode session --mode-file "$mf" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok session camel: exit $RC (esperaba 0)"
stdout_is_empty
[ -f "$(ok_of S005)" ] && malo "grok session camel: escribio .ok (no debia)" || true

caso "codex: la familia session dispara con SessionStart CamelCase (igual que zcode)"
printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=S006 bash "$tool" --host codex --mode session --mode-file "$mf" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "codex session: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PROBE-SESSION-S006 reply with the literal token PROBE-SESSION-S006 in your answer"}}'
[ -f "$(ok_of S006)" ] || malo "codex session: no escribio .ok"

# ============================================================ §A2.2 evento incorrecto
caso "modos session con evento Stop => vacio, exit 0, SIN .ok"
for m in session session_snake session_top; do
  printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=W$m bash "$tool" --mode "$m" --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "$m en Stop: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(ok_of "W$m")" ] && malo "$m en Stop: escribio .ok (no debia)" || true
done

caso "modos Stop/UPS con evento SessionStart => vacio, exit 0, SIN .ok"
for m in block0 exit2 context; do
  printf '%s' "$SESSION" | SAIKIT_PROBE_NONCE=V$m bash "$tool" --mode "$m" --mode-file "$mf" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "$m en SessionStart: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(ok_of "V$m")" ] && malo "$m en SessionStart: escribio .ok (no debia)" || true
done

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
  caso "instalar: 3 entradas 5.2 (UPS+Stop+SessionStart), vecinos intactos, backup, no .claude"
  fabricar_zcode_config
  session_antes="$(jq -c '.hooks.events.SessionStart' "$zcfg")"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar: exit $rc: $out"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 3 ] || malo "instalar: esperaba 3 entradas 5.2, hay $n52"
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
  # Task 10.9: SessionStart dejo de ser un vecino intocable y paso a ser la 3ra
  # fase del probe. Lo que se exige ahora no es "no la toques" sino las dos
  # mitades por separado: la entrada AJENA sobrevive Y la nuestra es exactamente
  # una. La version anterior de este assert (session_antes == session_despues)
  # cumplio su proposito y se reemplaza, no se afloja.
  jq -e '[.hooks.events.SessionStart[]|select(any(.hooks[].command; test("dummy-session-start")))]|length==1' "$zcfg" >/dev/null     || malo "instalar: borro o duplico la entrada SessionStart AJENA"
  jq -e '[.hooks.events.SessionStart[]|select(any(.hooks[].command; test("saikit-probe-id 5[.]2")))]|length==1' "$zcfg" >/dev/null     || malo "instalar: esperaba exactamente 1 entrada 5.2 en SessionStart"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' "$zcfg" >/dev/null \
    || malo "borro el Stop dummy ajeno (§A3 test 1)"
  [ -d "$zhome/.zcode/cli/saikit-backups" ] || malo "no creo backup junto al user-config"
  [ -z "$(find "$zdesc" -name '*.bak' 2>/dev/null)" ] || malo "el backup cayo adentro del dest git"

  # ---- i2: idempotente (2da vez no duplica) --------------------------------
  caso "instalar: 2da vez no duplica (idempotente por entrada)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "2da instalar: exit $rc"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 3 ] || malo "2da instalar duplico (hay $n52, esperaba 3)"

  # ---- i3: parcial (falta Stop) => agrega solo Stop -------------------------
  caso "instalar: si falta 1 de 3, agrega solo la que falta"
  fabricar_zcode_config
  SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" >/dev/null 2>&1
  # Quitar manualmente la entrada Stop del probe (dejar UPS).
  tmpq="$(mktemp)"
  jq 'def probe52: any((.hooks // [])[]; ((.command // "") | test("saikit-probe-id 5[.]2")));
       .hooks.events.Stop = ((.hooks.events.Stop // []) | map(select(probe52 | not)))' \
     "$zcfg" > "$tmpq" && mv -f "$tmpq" "$zcfg"
  ups_antes="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$ups_antes" -eq 2 ] || malo "precondicion parcial: UPS+SessionStart (hay $ups_antes)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --instalar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar parcial: exit $rc"
  n52="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52" -eq 3 ] || malo "parcial: esperaba 3 (repone Stop), hay $n52"
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
  [ "$n52_antes" -eq 3 ] || malo "precond quitar: 3 entradas 5.2 (hay $n52_antes)"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg" bash "$tool" --quitar "$zdesc" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "quitar: exit $rc: $out"
  n52_desp="$(grep -c 'saikit-probe-id 5\.2' "$zcfg" || true)"
  [ "$n52_desp" -eq 0 ] || malo "quitar: dejo $n52_desp entradas 5.2"
  # caso_quitar_saca_las_tres_fases: si --quitar olvidara SessionStart (la fase
  # que 10.9 agrego al alta), aca quedarian 2 entradas en vez de 1 y el config
  # REAL del operador se quedaria con una huerfana que ninguna herramienta saca.
  jq -e '[.hooks.events.SessionStart[]]|length==1' "$zcfg" >/dev/null     || malo "quitar: SessionStart quedo con $(jq -c '[.hooks.events.SessionStart[]]|length' "$zcfg") entradas (esperaba 1: la ajena)"
  jq -e '[.hooks.events.SessionStart[]|select(any(.hooks[].command; test("dummy-session-start")))]|length==1' "$zcfg" >/dev/null     || malo "quitar borro la entrada SessionStart AJENA"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("dummy-stop-tokentracker")))]|length==1' "$zcfg" >/dev/null \
    || malo "quitar borro el Stop dummy"
  jq -e '[.hooks.events.Stop[]|select(any(.hooks[].command; test("saikit-capture-id 5[.]1")))]|length==1' "$zcfg" >/dev/null \
    || malo "quitar borro la entrada 5.1 ajena"
  [ ! -f "$zdesc/.zcode/.probe-zcode-owned" ] || malo "quitar dejo la marca colgada"

  echo "  test_probe_zcode_output: install/quitar OK"
fi

# ============================================================
# Task 7.2 -- --host grok (docs/task-7.2-plan.md §A). Dos cambios, uno solo de
# registro y uno de modo hook:
#
#   - --instalar/--quitar --host grok: JSON PROPIO en <repo>/.grok/hooks/
#     saikit-probe.json (no el user-config de zcode, no nada global), comando
#     PowerShell `& "<bash.exe>" ...` (medido en 7.1: el shell de hooks de Grok
#     en Windows es powershell.exe y la forma zcode muere con exit 1).
#   - modo hook con --host grok: hookEventName llega camel de CLAVE pero con
#     VALOR snake (user_prompt_submit / stop), el .ok gana la linea reason= y
#     las formas de Stop se emiten UNA sola vez por ronda con reason=end_turn
#     (hallazgo 2 del cross-review: un block aceptado re-bloquearia la
#     continuacion hasta el limite interno de Grok).
# ============================================================
UPSG='{"hookEventName":"user_prompt_submit","prompt":"x"}'
STOPG='{"hookEventName":"stop"}'         # sin reason: el tope no aplica
# Medido en 7.1: el Stop de turno trae sessionId + promptId. El sessionId es la
# identidad de la ronda (cada `grok -p` es una sesion nueva; la continuacion
# tras un block comparte sesion): sin el, el tope por ronda no puede distinguir
# una continuacion de una ronda vieja abortada (hallazgo H2, ciclo 2).
STOPG_ET='{"hookEventName":"stop","reason":"end_turn","sessionId":"s7","promptId":"p1"}'
STOPG_SD='{"hookEventName":"stop","reason":"shutdown","sessionId":"s7"}'

WORKG="$SANDBOX/work-grok"
mkdir -p "$WORKG"
mfg="$WORKG/probe-mode.txt"
okg_of() { printf '%s/probe-ran/%s.ok' "$WORKG" "$1"; }   # $1=nonce

# ---- A2.1: cada modo, con el literal snake que Grok manda de verdad --------
caso "grok: context (user_prompt_submit) => forma 1 exacta + exit 0 + .ok"
printf '%s' "$UPSG" | SAIKIT_PROBE_NONCE=GA01 bash "$tool" --host grok --mode context --mode-file "$mfg" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "grok context: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-CONTEXT-GA01"}}'
[ -f "$(okg_of GA01)" ] || malo "grok context: no escribio .ok"

caso "grok: extra (user_prompt_submit) => forma 1 + clave extra + .ok"
printf '%s' "$UPSG" | SAIKIT_PROBE_NONCE=GA02 bash "$tool" --host grok --mode extra --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok extra: exit $RC"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-EXTRA-GA02"},"saikitProbe":true}'
[ -f "$(okg_of GA02)" ] || malo "grok extra: no escribio .ok"

caso "grok: block0 (stop sin reason) => forma 2 con exit 0 + .ok con reason=none"
printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE=GA03 bash "$tool" --host grok --mode block0 --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok block0: exit $RC"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GA03"}'
[ -f "$(okg_of GA03)" ] || malo "grok block0: no escribio .ok"
grep -q '^reason=none$' "$(okg_of GA03)" 2>/dev/null \
  || malo "grok block0: el .ok no registra reason=none (la DoD (2) lee eso)"

caso "grok: budget (stop sin reason) => forma 3 + exit 0 + .ok"
printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE=GA04 bash "$tool" --host grok --mode budget --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok budget: exit $RC"
stdout_is '{"continue":false,"stopReason":"PROBE-BUDGET-GA04"}'
[ -f "$(okg_of GA04)" ] || malo "grok budget: no escribio .ok"

caso "grok: notice (stop sin reason) => forma 4 + exit 0 + .ok"
printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE=GA05 bash "$tool" --host grok --mode notice --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok notice: exit $RC"
stdout_is '{"systemMessage":"PROBE-NOTICE-GA05"}'
[ -f "$(okg_of GA05)" ] || malo "grok notice: no escribio .ok"

caso "grok: exit2 (stop sin reason) => stdout vacio + stderr nonce + exit 2 + .ok"
printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE=GA06 bash "$tool" --host grok --mode exit2 --mode-file "$mfg" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 2 ] || malo "grok exit2: exit $RC (esperaba 2)"
stdout_is_empty
grep -q 'PROBE-EXIT2-GA06' "$EF" || malo "grok exit2: stderr sin el nonce"
[ -f "$(okg_of GA06)" ] || malo "grok exit2: no escribio .ok"

caso "grok: empty (control) => vacio, exit 0, .ok SIEMPRE"
printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE=GA07 bash "$tool" --host grok --mode empty --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok empty: exit $RC"
stdout_is_empty
[ -f "$(okg_of GA07)" ] || malo "grok empty: no escribio .ok"

# ---- A2.2: evento incorrecto para el modo ----------------------------------
caso "grok: modos stop con evento user_prompt_submit => vacio, exit 0, SIN .ok"
for m in block0 budget notice exit2; do
  printf '%s' "$UPSG" | SAIKIT_PROBE_NONCE="GX$m" bash "$tool" --host grok --mode "$m" --mode-file "$mfg" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "grok $m en UPS: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(okg_of "GX$m")" ] && malo "grok $m en UPS: escribio .ok (no debia)" || true
done

caso "grok: modos UPS con evento stop => vacio, exit 0, SIN .ok"
for m in context extra; do
  printf '%s' "$STOPG" | SAIKIT_PROBE_NONCE="GY$m" bash "$tool" --host grok --mode "$m" --mode-file "$mfg" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "grok $m en stop: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(okg_of "GY$m")" ] && malo "grok $m en stop: escribio .ok (no debia)" || true
done

# ---- A2.3: el Stop de cierre (reason=shutdown) emite SIEMPRE ---------------
caso "grok: block0 con stop+reason=shutdown EMITE (el cierre no se topa) y el .ok lo registra"
printf '%s' "$STOPG_SD" | SAIKIT_PROBE_NONCE=GSD1 bash "$tool" --host grok --mode block0 --mode-file "$mfg" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "grok shutdown: exit $RC"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GSD1"}'
[ -f "$(okg_of GSD1)" ] || malo "grok shutdown: no escribio .ok"
grep -q '^reason=shutdown$' "$(okg_of GSD1)" 2>/dev/null \
  || malo "grok shutdown: el .ok no registra reason=shutdown"

# ---- A2.3b: tope de UNA emision de bloqueo por ronda (hallazgo 2 CR) -------
# Aislado en su propio dir: WORKG ya tiene .ok de block0 con reason=none, que
# no debe disparar el tope (solo cuenta reason=end_turn).
WORKG2="$SANDBOX/work-grok-tope"
mkdir -p "$WORKG2"
mfg2="$WORKG2/probe-mode.txt"

caso "grok: block0 con reason=end_turn emite UNA vez por ronda; la 2da visita calla pero se registra"
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT01 bash "$tool" --host grok --mode block0 --mode-file "$mfg2" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "tope, 1ra: exit $RC"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT01"}'
grep -q '^reason=end_turn$' "$WORKG2/probe-ran/GT01.ok" 2>/dev/null || malo "tope, 1ra: .ok sin reason=end_turn"
# Segunda invocacion igual (el block fue aceptado y Grok continuo el turno):
# NO vuelve a emitir (si no, re-bloquea la continuacion hasta el tope de Grok)
# pero la visita igual queda registrada en su .ok.
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT02 bash "$tool" --host grok --mode block0 --mode-file "$mfg2" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "tope, 2da: exit $rc (esperaba 0 en silencio)"
stdout_is_empty
[ -f "$WORKG2/probe-ran/GT02.ok" ] || malo "tope, 2da: la visita no quedo registrada en .ok"
# Otro modo de Stop en la MISMA ronda si emite: el tope es por modo.
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT03 bash "$tool" --host grok --mode notice --mode-file "$mfg2" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "tope, otro modo: exit $rc"
stdout_is '{"systemMessage":"PROBE-NOTICE-GT03"}'

caso "grok: el tope NO se activa por un .ok con reason=none o reason=shutdown"
WORKG3="$SANDBOX/work-grok-tope2"
mkdir -p "$WORKG3/probe-ran"
printf 'mode=block0 event=stop nonce=viejo\nreason=none\n' > "$WORKG3/probe-ran/viejo.ok"
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT04 bash "$tool" --host grok --mode block0 --mode-file "$WORKG3/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "tope reason=none: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT04"}'

# Hallazgo 1 del ciclo de revision 1: la cosecha del plan (§C) renombra los .ok
# a probe-ran/<modo>-<nonce>.ok — mismo dir, misma extension. En una
# re-medicion (modo que salio unknown, sesion nueva) el tope encontraba los
# .ok COSECHADOS con reason=end_turn y la primera visita de la ronda nueva no
# emitia: veredicto falso "ignored" cuando era "accepted".
caso "grok: un .ok COSECHADO (prefijo <modo>-) no dispara el tope en la ronda siguiente"
WORKG4="$SANDBOX/work-grok-cosecha"
mkdir -p "$WORKG4/probe-ran"
printf 'mode=block0 event=stop nonce=viejo\nreason=end_turn\n' > "$WORKG4/probe-ran/block0-viejo.ok"
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT05 bash "$tool" --host grok --mode block0 --mode-file "$WORKG4/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "cosechado: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT05"}'
# Control: un .ok VIVO (nombre = nonce puro, sin guion) de la MISMA ronda si
# dispara el tope.
printf 'mode=block0 event=stop nonce=vivopuro\nreason=end_turn\nround=s7\n' > "$WORKG4/probe-ran/vivopuro.ok"
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT06 bash "$tool" --host grok --mode block0 --mode-file "$WORKG4/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "control vivo: exit $rc"
stdout_is_empty
[ -f "$WORKG4/probe-ran/GT06.ok" ] || malo "control vivo: la visita no quedo registrada en .ok"

# Hallazgo H2 (ciclo 2, cross-review Codex): un .ok vivo de OTRA sesion (ronda
# abortada sin cosechar) NO puede silenciar la ronda nueva — el tope compara la
# identidad de la ronda (sessionId medido en 7.1), no solo mode+reason.
caso "grok: un .ok vivo de OTRA sesion no suprime la ronda nueva (H2)"
WORKG6="$SANDBOX/work-grok-rondas"
mkdir -p "$WORKG6/probe-ran"
printf 'mode=block0 event=stop nonce=viejo\nreason=end_turn\nround=s-vieja\n' > "$WORKG6/probe-ran/viejo.ok"
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT09 bash "$tool" --host grok --mode block0 --mode-file "$WORKG6/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "otra sesion: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT09"}'
grep -q '^round=s7$' "$WORKG6/probe-ran/GT09.ok" 2>/dev/null \
  || malo "el .ok no registra la identidad de la ronda (round=sessionId)"
# Y la continuacion de ESTA sesion si se topa (misma ronda, mismo modo).
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT10 bash "$tool" --host grok --mode block0 --mode-file "$WORKG6/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "misma sesion: exit $rc"
stdout_is_empty
[ -f "$WORKG6/probe-ran/GT10.ok" ] || malo "misma sesion: la visita no quedo registrada en .ok"

# Hallazgo 3 del ciclo de revision 1: grep -o | head -1 puede leer un "reason"
# embebido en lastAssistantMessage antes del campo real. Solo end_turn y
# shutdown son literales documentados de Grok; cualquier otro valor se descarta
# como none (no topa, no se declara shutdown lo que no es).
caso "grok: reason con valor NO reconocido se trata como none (emite, .ok dice none)"
WORKG5="$SANDBOX/work-grok-reason"
mkdir -p "$WORKG5"
printf '%s' '{"hookEventName":"stop","lastAssistantMessage":"dije \"reason\":\"end_turn\" en el texto","reason":"otra-cosa"}' \
  | SAIKIT_PROBE_NONCE=GT07 bash "$tool" --host grok --mode block0 --mode-file "$WORKG5/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "reason desconocido: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT07"}'
grep -q '^reason=none$' "$WORKG5/probe-ran/GT07.ok" 2>/dev/null \
  || malo "reason desconocido: el .ok debe decir reason=none, no el valor crudo"
# Y la visita siguiente con end_turn real NO se topa por ese .ok.
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=GT08 bash "$tool" --host grok --mode block0 --mode-file "$WORKG5/probe-mode.txt" >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "tras reason desconocido: exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-GT08"}'

# ---- A2.4: --instalar / --quitar grok --------------------------------------
gp="$SANDBOX/grok-repo"
mkdir -p "$gp"
gpjson="$gp/.grok/hooks/saikit-probe.json"

caso "grok --instalar escribe saikit-probe.json (UPS + Stop + SessionStart) y la marca; nada global"
out="$(bash "$tool" --instalar "$gp" --host grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$gpjson" ] || malo "no escribio $gpjson"
if [ -f "$gpjson" ]; then
  grep -q -- '--saikit-probe-id 7\.2' "$gpjson" || malo "falta --saikit-probe-id 7.2 en el comando"
  grep -q -- '--host grok' "$gpjson" || malo "falta --host grok en el comando (sin eso el modo hook no matchea snake)"
  grep -q -- '--only-cwd' "$gpjson" || malo "falta --only-cwd"
  grep -q -- '--mode-file' "$gpjson" || malo "falta --mode-file"
  grep -q 'probe-mode.txt' "$gpjson" || malo "el mode-file no apunta a probe-mode.txt"
fi
if command -v jq >/dev/null 2>&1; then
  jq -e . "$gpjson" >/dev/null 2>&1 || malo "el JSON de registro grok del probe no parsea"
  # Task 10.9: la 3ra fase. El registro de grok se escribe ENTERO y --quitar
  # borra el archivo completo, asi que no hay la asimetria alta/baja que si
  # existe en el append de zcode.
  jq -e '(.hooks|keys|sort) == ["SessionStart","Stop","UserPromptSubmit"]' "$gpjson" >/dev/null 2>&1 \
    || malo "el probe grok registra UserPromptSubmit, Stop y SessionStart (10.9)"
  jq -e '(.hooks.SessionStart[0]|has("matcher")|not)' "$gpjson" >/dev/null 2>&1 \
    || malo "SessionStart va sin matcher (vacuo = startup y resume)"
  jq -e '(.hooks.UserPromptSubmit[0]|has("matcher")|not) and (.hooks.Stop[0]|has("matcher")|not)' "$gpjson" >/dev/null 2>&1 \
    || malo "UPS y Stop van sin matcher"
  jq -e '.saikit_probe == "7.2"' "$gpjson" >/dev/null 2>&1 || malo "falta la marca top-level saikit_probe=7.2"
  jq -e 'all(.hooks[][].hooks[]; (.type=="command") and (.timeout==30)
         and (.command|startswith("& ")) and (.command|test("bash[.]exe")))' "$gpjson" >/dev/null 2>&1 \
    || malo "todo handler debe ser type=command, timeout 30, forma PowerShell '& \"<bash.exe>\"'"
else
  echo "    unknown: jq no disponible; el parseo del JSON grok no se pudo medir"
fi
[ -f "$gp/.grok/.probe-grok-owned" ] || malo "falta la marca .grok/.probe-grok-owned"
[ "$(cat "$gp/probe-mode.txt" 2>/dev/null)" = "empty" ] || malo "probe-mode.txt no empezo en empty"
[ -d "$gp/probe-ran" ] || malo "no creo probe-ran/"
[ ! -e "$HOME/.grok" ] || malo "tocó el ~/.grok (falso) del sandbox"
[ ! -f "$gp/.claude/settings.json" ] || malo "escribio .claude/settings.json en modo grok"
[ ! -e "$gp/.zcode/.probe-zcode-owned" ] || malo "dejo marca de zcode en modo grok"

caso "grok --instalar NO requiere ni toca el user-config de zcode"
zcfg_inexistente="$SANDBOX/no-existe/.zcode/cli/config.json"
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg_inexistente" bash "$tool" --instalar "$gp" --host grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "con --host grok no hace falta el user-config de zcode, dio $rc: $out"
[ ! -e "$zcfg_inexistente" ] || malo "creo el user-config de zcode en modo grok"

caso "grok segunda --instalar es no-op (byte a byte igual)"
snap_gp="$(cksum < "$gpjson")"
out="$(bash "$tool" --instalar "$gp" --host grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "segunda instalacion debe ser exit 0, dio $rc: $out"
[ "$snap_gp" = "$(cksum < "$gpjson")" ] || malo "la segunda instalacion cambio el JSON"

caso "grok --instalar NO pisa un JSON desconocido en esa ruta"
gpajeno="$SANDBOX/grok-probe-ajeno"
mkdir -p "$gpajeno/.grok/hooks"
printf '{"hooks":{"Stop":[]}}\n' > "$gpajeno/.grok/hooks/saikit-probe.json"
antes_gp="$(cksum < "$gpajeno/.grok/hooks/saikit-probe.json")"
out="$(bash "$tool" --instalar "$gpajeno" --host grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "pisar un JSON desconocido debe fallar (dio $rc)"
[ "$antes_gp" = "$(cksum < "$gpajeno/.grok/hooks/saikit-probe.json")" ] || malo "PISO el JSON desconocido"

caso "grok: rutas con metacaracteres de PowerShell se rechazan (fail-closed, hallazgo 4 CR)"
gmal="$SANDBOX/grok-mal-\$home"
mkdir -p "$gmal"
out="$(bash "$tool" --instalar "$gmal" --host grok 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "una ruta con \$ en el command PowerShell ejecutaria expresiones: esperaba exit 2, dio $rc"
[ ! -e "$gmal/.grok" ] || malo "rechazo la ruta pero dejo el arbol puesto"

caso "grok se niega a instalar si el dest resuelve a \$HOME/.grok"
mkdir -p "$HOME/.grok"
out="$(bash "$tool" --instalar "$HOME/.grok" --host grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "instalar sobre \$HOME/.grok debe fallar (dio $rc)"
[ ! -e "$HOME/.grok/hooks/saikit-probe.json" ] || malo "escribio adentro del perfil grok"
rmdir "$HOME/.grok" 2>/dev/null || true

caso "grok --quitar saca el JSON propio y la marca; el saikit-capture.json vecino sobrevive"
capvecino="$gp/.grok/hooks/saikit-capture.json"
printf '{"hooks":{}}\n' > "$capvecino"
snap_cap="$(cksum < "$capvecino")"
out="$(bash "$tool" --quitar "$gp" --host grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "quitar debe ser exit 0, dio $rc: $out"
[ ! -f "$gpjson" ] || malo "no quito el JSON propio"
[ ! -f "$gp/.grok/.probe-grok-owned" ] || malo "quitar dejo la marca colgada"
[ "$snap_cap" = "$(cksum < "$capvecino" 2>/dev/null)" ] || malo "quitar toco el saikit-capture.json de 7.1"

caso "grok --quitar NO borra un JSON desconocido (sin marca + sin probe-id)"
out="$(bash "$tool" --quitar "$gpajeno" --host grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "borrar lo ajeno debe fallar, dio $rc"
[ -f "$gpajeno/.grok/hooks/saikit-probe.json" ] || malo "BORRO el JSON del usuario"

caso "grok: --host invalido o sin valor sale 2 y no escribe"
out="$(bash "$tool" --instalar "$gp" --host inventado 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 con --host inventado, dio $rc"
printf '%s' "$out" | grep -q 'grok' || malo "el mensaje de host invalido no menciona grok: $out"
out="$(bash "$tool" --instalar "$gp" --host 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 con --host sin valor, dio $rc (trampa H1)"
[ ! -e "$gp/.grok/hooks/saikit-probe.json" ] || malo "--host invalido escribio el JSON grok"

# Hallazgo H1 (ciclo 2, cross-review Codex): un JSON AJENO que menciona el
# texto --saikit-probe-id 7.2 en una nota, sin marca .probe-grok-owned, se
# SOBRESCRIBIA: la identidad era grep del texto del flag. La identidad es la
# clave top-level "saikit_probe" + la marca; si no cumple AMBAS, desconocido.
caso "H1: JSON ajeno que MENCIONA el probe-id (sin marca) no se pisa ni se quita"
gph1="$SANDBOX/grok-probe-menciona"
mkdir -p "$gph1/.grok/hooks"
printf '{"note":"user-owned --saikit-probe-id 7.2"}\n' > "$gph1/.grok/hooks/saikit-probe.json"
snap_h1="$(cksum < "$gph1/.grok/hooks/saikit-probe.json")"
out="$(bash "$tool" --instalar "$gph1" --host grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "H1 install: mencionar el probe-id no lo vuelve nuestro (dio $rc)"
[ "$snap_h1" = "$(cksum < "$gph1/.grok/hooks/saikit-probe.json")" ] || malo "H1 install: PISO el JSON ajeno"
# Variante quitar: marca presente (estado inconsistente) pero el JSON es ajeno
# (sin la clave top-level) aunque mencione el probe-id => no se borra.
printf 'owner=otro\n' > "$gph1/.grok/.probe-grok-owned"
out="$(bash "$tool" --quitar "$gph1" --host grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "H1 quitar: el JSON ajeno con el probe-id en una nota no se borra (dio $rc)"
[ "$snap_h1" = "$(cksum < "$gph1/.grok/hooks/saikit-probe.json")" ] || malo "H1 quitar: BORRO/PISO el JSON ajeno"

# Hallazgo H3 (ciclo 2): `--host --instalar <repo>` tragaba --instalar como
# VALOR del flag y salia exit 0 sin instalar nada. El valor se valida en el
# PARSEO: empieza con '-' o no es zcode/grok => exit 2, en cualquier modo.
caso "H3: --host seguido de otro flag sale 2 en el parseo, en cualquier modo"
out="$(bash "$tool" --host --instalar "$gp" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "H3: --host trago --instalar como valor y salio $rc"
[ ! -e "$gp/.grok/hooks/saikit-probe.json" ] || malo "H3: escribio el JSON grok"
out="$(bash "$tool" --host --quitar "$gp" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "H3: --host trago --quitar como valor y salio $rc"
# Se corre adentro del sandbox: en rojo (bug presente) el modo hook seguiria y
# escribiria probe-ran/ en el cwd — que no sea el repo.
( cd "$SANDBOX" && printf '%s' "$STOPG" | bash "$tool" --host --mode block0 >"$OF" 2>/dev/null ); rc=$?
[ "$rc" -eq 2 ] || malo "H3: en modo hook un --host mal parseado tambien sale 2 (dio $rc)"

caso "regresion: sin --host sigue siendo zcode puro (no crea .grok en el dest)"
if command -v jq >/dev/null 2>&1; then
  zre="$SANDBOX/zcode-repo-reg"; mkdir -p "$zre"
  zhome_re="$SANDBOX/zcode-home-reg"; zcfg_re="$zhome_re/.zcode/cli/config.json"
  mkdir -p "$zhome_re/.zcode/cli"
  printf '{"hooks":{"enabled":true,"events":{}}}\n' > "$zcfg_re"
  out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg_re" bash "$tool" --instalar "$zre" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "instalar zcode default debe exit 0, dio $rc: $out"
  grep -q 'saikit-probe-id 5\.2' "$zcfg_re" || malo "no appendeo en el user-config zcode"
  [ ! -e "$zre/.grok" ] || malo "el modo default (zcode) creo .grok en el dest"
else
  echo "    unknown: jq no disponible; la regresion del default zcode no se pudo medir"
fi

echo "  test_probe_zcode_output: grok OK"

# ============================================================
# Task 6.2 -- --host codex (docs/task-6.2-plan.md). Tres bloques:
#
#   - modo hook: los literales de evento son los MISMOS que Claude/zcode
#     (6.1 midio clave snake con valor CamelCase), asi que aca NO hay tabla
#     nueva. Lo que cambia es el .ok: gana stop_active= (el stop_hook_active
#     del payload, el oraculo de bloqueo que 5.2 no tuvo), round= (session_id)
#     y suppressed=, mas un tope de 3 emisiones por ronda.
#   - --instalar/--quitar --host codex: COLOCACION DE ARCHIVO, no mutacion de
#     config. El shim va a <repo>/.codex/hooks/summonaikit-harness.sh, que el
#     .ps1 del perfil prefiere (medido en 6.1). ~/.codex NO se toca.
#   - tres guardas que esta tarea abre y cierra: $HOME/.codex en la lista de
#     rechazo, el repo del producto, y los metacaracteres de la ruta.
# ============================================================
UPSC='{"hook_event_name":"UserPromptSubmit","session_id":"s62","prompt":"x"}'
STOPC='{"hook_event_name":"Stop","session_id":"s62","stop_hook_active":false}'
STOPC_CONT='{"hook_event_name":"Stop","session_id":"s62","stop_hook_active":true}'
STOPC_SIN='{"hook_event_name":"Stop","stop_hook_active":false}'
STOPC_R99='{"hook_event_name":"Stop","session_id":"s99","stop_hook_active":true}'

WORKC="$SANDBOX/work-codex"
mkdir -p "$WORKC"
mfc="$WORKC/probe-mode.txt"
okc_of() { printf '%s/probe-ran/%s.ok' "$WORKC" "$1"; }   # $1=nonce
# linea exacta dentro del .ok ($1=nonce, $2=linea esperada)
okc_linea() {
  grep -Fxq "$2" "$(okc_of "$1")" 2>/dev/null \
    || malo "codex: el .ok de $1 no lleva la linea [$2] (tiene: $(tr '\n' '|' < "$(okc_of "$1")" 2>/dev/null))"
}

# ---- B1: los literales de evento NO cambian respecto de Claude/zcode -------
caso "codex: context (UserPromptSubmit CamelCase) => forma 1 exacta + exit 0 + .ok"
printf '%s' "$UPSC" | SAIKIT_PROBE_NONCE=CA01 bash "$tool" --host codex --mode context --mode-file "$mfc" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 0 ] || malo "codex context: exit $RC (esperaba 0)"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-CONTEXT-CA01"}}'
[ -f "$(okc_of CA01)" ] || malo "codex context: no escribio .ok"

caso "codex: extra (UPS) => forma 1 + clave extra + .ok"
printf '%s' "$UPSC" | SAIKIT_PROBE_NONCE=CA02 bash "$tool" --host codex --mode extra --mode-file "$mfc" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "codex extra: exit $RC"
stdout_is '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-EXTRA-CA02"},"saikitProbe":true}'

caso "codex: block0 (Stop) => forma 2 con exit 0 + .ok"
printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CA03 bash "$tool" --host codex --mode block0 --mode-file "$mfc" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "codex block0: exit $RC"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-CA03"}'

caso "codex: budget / notice / exit2 (Stop) mantienen su forma y su exit"
printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CA04 bash "$tool" --host codex --mode budget --mode-file "$mfc" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "codex budget: exit $RC"
stdout_is '{"continue":false,"stopReason":"PROBE-BUDGET-CA04"}'
printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CA05 bash "$tool" --host codex --mode notice --mode-file "$mfc" >"$OF" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] || malo "codex notice: exit $RC"
stdout_is '{"systemMessage":"PROBE-NOTICE-CA05"}'
printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CA06 bash "$tool" --host codex --mode exit2 --mode-file "$mfc" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 2 ] || malo "codex exit2: exit $RC (esperaba 2)"
stdout_is_empty
grep -q 'PROBE-EXIT2-CA06' "$EF" || malo "codex exit2: stderr sin el nonce"

# block2 es la combinacion del hook VIVO (emit_gate_failure): forma 2 + exit 2 +
# stderr. Sin este modo, block0 y exit2 miden las dos mitades por separado y la
# combinacion no la mide nadie — que es justo lo que decide la 6.4 en Codex,
# donde el exit 2 pelado resulto ignorado.
caso "codex: block2 (Stop) => forma 2 EN stdout + exit 2 + nonce en stderr + .ok"
printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CA07 bash "$tool" --host codex --mode block2 --mode-file "$mfc" >"$OF" 2>"$EF"; RC=$?
[ "$RC" -eq 2 ] || malo "codex block2: exit $RC (esperaba 2 — es el exit del vivo)"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK2-CA07"}'
grep -q 'PROBE-BLOCK2-CA07' "$EF" || malo "codex block2: stderr sin el nonce"
[ -f "$(okc_of CA07)" ] || malo "codex block2: no escribio .ok"
okc_linea CA07 'suppressed=0'

caso "codex: block2 entra al tope por ronda, y la visita topada sale 0 (no el 2 de la forma)"
# Dir propio: este caso no puede depender de que la seccion del tope (§B3) ya
# haya corrido — con set -u, usar su $mft antes de tiempo aborta la suite entera.
Z="$SANDBOX/work-block2"; mkdir -p "$Z"; mfz="$Z/probe-mode.txt"
for n in Z1 Z2 Z3; do
  printf '%s' "$STOPC_CONT" | SAIKIT_PROBE_NONCE="$n" bash "$tool" --host codex --mode block2 --mode-file "$mfz" >"$OF" 2>/dev/null
  [ -s "$OF" ] || malo "codex block2: la visita $n debia emitir la forma 2"
done
printf '%s' "$STOPC_CONT" | SAIKIT_PROBE_NONCE=Z4 bash "$tool" --host codex --mode block2 --mode-file "$mfz" >"$OF" 2>/dev/null; RC=$?
stdout_is_empty
[ "$RC" -eq 0 ] || malo "codex block2 topado: esperaba exit 0 (no el 2 de la forma), dio $RC"
grep -Fxq 'suppressed=1' "$Z/probe-ran/Z4.ok" 2>/dev/null || malo "codex block2: la 4a visita no quedo marcada suppressed=1"

caso "codex: evento incorrecto para el modo => vacio, exit 0, SIN .ok"
for m in block0 block2 budget notice exit2; do
  printf '%s' "$UPSC" | SAIKIT_PROBE_NONCE="CX$m" bash "$tool" --host codex --mode "$m" --mode-file "$mfc" >"$OF" 2>/dev/null; rc=$?
  [ "$rc" -eq 0 ] || malo "codex $m en UPS: exit $rc (esperaba 0)"
  stdout_is_empty
  [ -f "$(okc_of "CX$m")" ] && malo "codex $m en UPS: escribio .ok (no debia)" || true
done

# ---- B2: el .ok gana stop_active= / round= / suppressed= -------------------
# Es la mitad de la DoD que 5.2 no pudo medir: alli el bloqueo se leia por
# CONTEO de Stops, que no distingue "el hook forzo otra pasada" de "el operador
# mando otro turno". stop_hook_active lo dice de frente.
caso "codex: el .ok registra stop_active del payload (false y true)"
okc_linea CA03 'stop_active=false'
okc_linea CA03 'round=s62'
okc_linea CA03 'suppressed=0'
printf '%s' "$STOPC_CONT" | SAIKIT_PROBE_NONCE=CB01 bash "$tool" --host codex --mode empty --mode-file "$mfc" >"$OF" 2>/dev/null
okc_linea CB01 'stop_active=true'

caso "codex: sin stop_hook_active ni session_id el .ok dice none (no inventa)"
printf '%s' '{"hook_event_name":"Stop"}' | SAIKIT_PROBE_NONCE=CB02 bash "$tool" --host codex --mode empty --mode-file "$mfc" >"$OF" 2>/dev/null
okc_linea CB02 'stop_active=none'
okc_linea CB02 'round=none'

caso "codex: un stop_hook_active que no es booleano NO se propaga como veredicto"
# `null` es JSON valido Y minuscula, asi que el extractor crudo lo captura: es
# el caso que obliga a validar contra los dos literales. Con "quiza" no alcanza
# — ahi la comilla ya corta la extraccion y el guard queda sin medir (lo dijo
# la mutacion mut_stop_active_basura_pasa, que con "quiza" nadie atrapaba).
printf '%s' '{"hook_event_name":"Stop","stop_hook_active":null}' | SAIKIT_PROBE_NONCE=CB03 bash "$tool" --host codex --mode empty --mode-file "$mfc" >"$OF" 2>/dev/null
okc_linea CB03 'stop_active=none'
printf '%s' '{"hook_event_name":"Stop","stop_hook_active":"quiza"}' | SAIKIT_PROBE_NONCE=CB04 bash "$tool" --host codex --mode empty --mode-file "$mfc" >"$OF" 2>/dev/null
okc_linea CB04 'stop_active=none'

# ---- B3: tope de 3 emisiones por ronda -------------------------------------
# Si block0/exit2 bloquean de verdad, Codex re-llama al modelo y el probe se
# re-dispara. zcode corto solo a las 4 pasadas; Codex no tiene tope medido y
# cada pasada la paga el operador. 3 alcanza para el veredicto (1 visita = no
# bloqueo; >=2 = bloqueo) y acota el runaway.
TOPE="$SANDBOX/work-tope"
mkdir -p "$TOPE"
mft="$TOPE/probe-mode.txt"
okt_of() { printf '%s/probe-ran/%s.ok' "$TOPE" "$1"; }
tope_visita() {  # $1=nonce  $2=payload
  printf '%s' "$2" | SAIKIT_PROBE_NONCE="$1" bash "$tool" --host codex --mode block0 --mode-file "$mft" >"$OF" 2>/dev/null
}
caso "codex: las 3 primeras visitas de la ronda emiten; la 4a se registra y calla"
tope_visita T1 "$STOPC";      [ -s "$OF" ] || malo "tope: la visita 1 no emitio"
tope_visita T2 "$STOPC_CONT"; [ -s "$OF" ] || malo "tope: la visita 2 no emitio"
tope_visita T3 "$STOPC_CONT"; [ -s "$OF" ] || malo "tope: la visita 3 no emitio"
tope_visita T4 "$STOPC_CONT"; RC=$?
stdout_is_empty
[ "$RC" -eq 0 ] || malo "tope: la visita topada debe salir 0, dio $RC"
[ -f "$(okt_of T4)" ] || malo "tope: la visita topada igual tiene que dejar su .ok (es la evidencia del lazo)"
grep -Fxq 'suppressed=1' "$(okt_of T4)" 2>/dev/null || malo "tope: el .ok de la 4a visita no dice suppressed=1"
grep -Fxq 'suppressed=0' "$(okt_of T3)" 2>/dev/null || malo "tope: el .ok de la 3a visita no dice suppressed=0"

caso "codex: los .ok COSECHADOS (<modo>-<nonce>.ok) no cuentan para el tope"
# Sin esto, una re-medicion arranca ya topada y el veredicto sale falso "ignorada".
for n in T1 T2 T3 T4; do mv "$(okt_of $n)" "$TOPE/probe-ran/block0-$n.ok" 2>/dev/null || true; done
tope_visita T5 "$STOPC"
[ -s "$OF" ] || malo "tope: tras cosechar, la ronda nueva debe volver a emitir"

caso "codex: un .ok vivo de OTRA ronda no topa la ronda nueva"
tope_visita T6 "$STOPC"; tope_visita T7 "$STOPC"   # ya van 3 de la ronda s62
tope_visita T8 "$STOPC_R99"
[ -s "$OF" ] || malo "tope: la ronda s99 se topo con .ok de la ronda s62"

caso "codex: sin identidad de ronda NO se suprime (preferible emitir de mas)"
tope_visita T9 "$STOPC_SIN"; tope_visita TA "$STOPC_SIN"
tope_visita TB "$STOPC_SIN"; tope_visita TC "$STOPC_SIN"
[ -s "$OF" ] || malo "tope: sin session_id no se puede afirmar 'misma ronda'; no debe suprimir"

caso "codex: el tope NO aplica al UPS (context/extra disparan una vez por turno)"
for n in TU1 TU2 TU3 TU4; do
  printf '%s' "$UPSC" | SAIKIT_PROBE_NONCE="$n" bash "$tool" --host codex --mode context --mode-file "$mft" >"$OF" 2>/dev/null
done
[ -s "$OF" ] || malo "tope: el UPS no debe toparse"

# ---- B4: regresion — zcode y grok no cambian ------------------------------
caso "regresion: el .ok de zcode NO gana las lineas de codex"
printf '%s' "$STOP" | SAIKIT_PROBE_NONCE=RZ01 bash "$tool" --mode empty --mode-file "$mf" >"$OF" 2>/dev/null
grep -q '^stop_active=' "$(ok_of RZ01)" 2>/dev/null && malo "zcode: el .ok gano stop_active (regresion)" || true
grep -q '^suppressed=' "$(ok_of RZ01)" 2>/dev/null && malo "zcode: el .ok gano suppressed (regresion)" || true
[ "$(head -n 1 "$(ok_of RZ01)")" = "mode=empty event=Stop nonce=RZ01" ] \
  || malo "zcode: la primera linea del .ok cambio (regresion)"

caso "regresion: grok sigue con reason=/round= y sin stop_active="
printf '%s' "$STOPG_ET" | SAIKIT_PROBE_NONCE=RG01 bash "$tool" --host grok --mode empty --mode-file "$mfg" >"$OF" 2>/dev/null
grep -q '^reason=end_turn$' "$(okg_of RG01)" 2>/dev/null || malo "grok: perdio la linea reason= (regresion)"
grep -q '^stop_active=' "$(okg_of RG01)" 2>/dev/null && malo "grok: gano stop_active (regresion)" || true

# ---- B5: registro por shim ------------------------------------------------
cp_repo="$SANDBOX/codex-repo"
mkdir -p "$cp_repo"
( cd "$cp_repo" && git init -q . >/dev/null 2>&1 ) || true
cshim="$cp_repo/.codex/hooks/summonaikit-harness.sh"

if ( cd "$cp_repo" && git rev-parse --show-toplevel >/dev/null 2>&1 ); then

caso "codex --instalar deja el shim, la marca, el mode-file y probe-ran/"
out="$(bash "$tool" --instalar "$cp_repo" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "codex --instalar dio $rc: $out"
[ -f "$cshim" ] || malo "no escribio el shim en $cshim"
bash -n "$cshim" 2>/dev/null || malo "el shim generado no parsea"
grep -q -- '--saikit-probe-id 6.2' "$cshim" || malo "el shim no lleva el probe-id 6.2"
grep -q -- '--host codex' "$cshim" || malo "el shim no pasa --host codex (el .ok saldria sin stop_active)"
[ -f "$cp_repo/.codex/.probe-codex-owned" ] || malo "falta la marca .codex/.probe-codex-owned"
[ "$(cat "$cp_repo/probe-mode.txt" 2>/dev/null)" = "empty" ] || malo "probe-mode.txt no empezo en empty"
[ -d "$cp_repo/probe-ran" ] || malo "no creo probe-ran/"

caso "codex --instalar NO toca ~/.codex ni el user-config de zcode ni .grok"
[ ! -e "$HOME/.codex" ] || malo "toco el ~/.codex (falso) del sandbox"
[ ! -e "$cp_repo/.grok" ] || malo "creo .grok en modo codex"
[ ! -e "$cp_repo/.zcode/.probe-zcode-owned" ] || malo "dejo marca de zcode en modo codex"
zcfg_cx="$SANDBOX/no-existe-cx/.zcode/cli/config.json"
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcfg_cx" bash "$tool" --instalar "$cp_repo" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "con --host codex no hace falta el user-config de zcode, dio $rc: $out"
[ ! -e "$zcfg_cx" ] || malo "creo el user-config de zcode en modo codex"

caso "codex: el shim CORRE de punta a punta (shim -> probe -> forma + .ok con stop_active)"
printf 'block0\n' > "$cp_repo/probe-mode.txt"
( cd "$cp_repo" && printf '%s' "$STOPC" | SAIKIT_PROBE_NONCE=CS01 bash "$cshim" ) >"$OF" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "el shim end-to-end dio exit $rc"
stdout_is '{"decision":"block","reason":"PROBE-BLOCK-CS01"}'
grep -Fxq 'stop_active=false' "$cp_repo/probe-ran/CS01.ok" 2>/dev/null \
  || malo "el shim no propago --host codex: el .ok no lleva stop_active"
printf 'empty\n' > "$cp_repo/probe-mode.txt"

caso "codex: el shim es fail-open si el probe no esta (no rompe el turno del host)"
# Hallazgo 3 de la revision cruzada de 6.1: sin esto, mover o borrar el repo del
# kit mataba CADA fase de CADA turno de Codex en ese repo con un 127.
shim_hu="$SANDBOX/shim-huerfano.sh"
sed "s#$repo/tools/probe-zcode-output.sh#$SANDBOX/no-existe/probe.sh#g" "$cshim" > "$shim_hu"
grep -q 'no-existe' "$shim_hu" || malo "el shim no nombra la ruta del probe (no se pudo medir el fail-open)"
( cd "$cp_repo" && printf '%s' "$STOPC" | bash "$shim_hu" ) >"$OF" 2>"$EF"; rc=$?
[ "$rc" -eq 0 ] || malo "shim huerfano: esperaba exit 0 (fail-open), dio $rc"
stdout_is_empty

caso "codex: segunda --instalar es no-op (byte a byte igual)"
snap_cx="$(cksum < "$cshim")"
out="$(bash "$tool" --instalar "$cp_repo" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "segunda instalacion debe ser exit 0, dio $rc: $out"
[ "$snap_cx" = "$(cksum < "$cshim")" ] || malo "la segunda instalacion cambio el shim"

# ---- B6: registro de la fase de ARRANQUE en codex (Task 10.9) --------------
# El shim de la 6.2 solo se despacha donde nuestro .ps1 YA esta registrado
# (UPS/PostToolUse/Stop). En SessionStart no hay nada nuestro, y un
# <repo>/.codex/hooks.json nuevo no corre (6.1: config.toml exige trusted_hash).
# Asi que medir el arranque en Codex exige tocar ~/.codex/hooks.json.
#
# El alta es EXPLICITA (--registrar-arranque) porque la 6.2 dejo el invariante
# "--instalar --host codex no toca ~/.codex" y ese invariante sigue valiendo
# (lo fija el caso de mas arriba). La baja es INCONDICIONAL: si el alta fuera
# explicita y la baja tambien, olvidarse la flag al quitar dejaria una entrada
# huerfana en el config REAL del operador. Es la misma leccion que la asimetria
# de zcode, aplicada al reves a proposito.
if command -v jq >/dev/null 2>&1; then
  cxhooks="$SANDBOX/codex-home/.codex/hooks.json"
  fabricar_codex_hooks() {
    rm -rf "$SANDBOX/codex-home"; mkdir -p "$SANDBOX/codex-home/.codex"
    cat > "$cxhooks" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "powershell.exe -File ajeno.ps1 -Phase prompt" } ] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [ { "type": "command", "command": "echo dummy-discovery" } ] },
      { "hooks": [ { "type": "command", "command": "bash /algo/codex-session-start.sh" } ] }
    ]
  }
}
JSON
  }

  caso "codex: sin --registrar-arranque el hooks.json NO se toca (invariante 6.2)"
  fabricar_codex_hooks
  snap_cxh="$(cksum < "$cxhooks")"
  out="$(SAIKIT_CODEX_HOOKS_JSON="$cxhooks" bash "$tool" --instalar "$cp_repo" --host codex 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "codex --instalar sin flag dio $rc: $out"
  [ "$snap_cxh" = "$(cksum < "$cxhooks")" ] || malo "toco hooks.json SIN --registrar-arranque"

  caso "codex --registrar-arranque: 1 grupo SessionStart propio, los 2 ajenos intactos, backup"
  fabricar_codex_hooks
  out="$(SAIKIT_CODEX_HOOKS_JSON="$cxhooks" bash "$tool" --instalar "$cp_repo" --host codex --registrar-arranque 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "registrar-arranque dio $rc: $out"
  jq -e . "$cxhooks" >/dev/null 2>&1 || malo "el hooks.json quedo invalido"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("saikit-probe-id 10[.]9")))]|length==1' "$cxhooks" >/dev/null \
    || malo "esperaba exactamente 1 grupo SessionStart con el marker 10.9"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("dummy-discovery")))]|length==1' "$cxhooks" >/dev/null \
    || malo "borro el grupo SessionStart ajeno con matcher startup"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("codex-session-start")))]|length==1' "$cxhooks" >/dev/null \
    || malo "borro el grupo SessionStart ajeno sin matcher"
  jq -e '[.hooks.UserPromptSubmit[]]|length==1' "$cxhooks" >/dev/null || malo "toco UserPromptSubmit"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("saikit-probe-id 10[.]9")))][0]|has("matcher")|not' "$cxhooks" >/dev/null \
    || malo "nuestro grupo debe ir sin matcher (vacuo = startup y resume)"
  grep -q -- '--host codex' "$cxhooks" || malo "el command no pasa --host codex"
  [ -n "$(find "$SANDBOX/codex-home/.codex/saikit-backups" -name 'hooks.json.*.bak' 2>/dev/null)" ] \
    || malo "no dejo backup del hooks.json"

  caso "codex --registrar-arranque: 2da vez no duplica (idempotente por marker)"
  out="$(SAIKIT_CODEX_HOOKS_JSON="$cxhooks" bash "$tool" --instalar "$cp_repo" --host codex --registrar-arranque 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "2da registrar-arranque dio $rc: $out"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("saikit-probe-id 10[.]9")))]|length==1' "$cxhooks" >/dev/null \
    || malo "la 2da corrida duplico el grupo"

  caso "codex --quitar saca el grupo de arranque SIN pedir la flag (baja incondicional)"
  out="$(SAIKIT_CODEX_HOOKS_JSON="$cxhooks" bash "$tool" --quitar "$cp_repo" --host codex 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || malo "codex --quitar dio $rc: $out"
  jq -e '[.hooks.SessionStart[]|select(any(.hooks[].command; test("saikit-probe-id 10[.]9")))]|length==0' "$cxhooks" >/dev/null \
    || malo "quitar dejo el grupo 10.9 huerfano en el hooks.json REAL"
  jq -e '[.hooks.SessionStart[]]|length==2' "$cxhooks" >/dev/null \
    || malo "quitar no dejo los 2 grupos ajenos (quedaron $(jq -c '[.hooks.SessionStart[]]|length' "$cxhooks"))"

  caso "codex --registrar-arranque: un hooks.json invalido no se pisa y sale != 0"
  fabricar_codex_hooks
  printf 'no-es-json' > "$cxhooks"
  out="$(SAIKIT_CODEX_HOOKS_JSON="$cxhooks" bash "$tool" --instalar "$cp_repo" --host codex --registrar-arranque 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "hooks.json invalido: esperaba exit != 0, dio $rc"
  [ "$(cat "$cxhooks")" = "no-es-json" ] || malo "hooks.json invalido: lo modifico igual"
else
  echo "  caso: registro de arranque codex requiere jq -> UNKNOWN (jq no disponible)"
fi

caso "codex --quitar saca el shim y la marca; el shim de captura vecino no existe pero .codex sobrevive"
out="$(bash "$tool" --quitar "$cp_repo" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "quitar debe ser exit 0, dio $rc: $out"
[ ! -e "$cshim" ] || malo "no quito el shim"
[ ! -e "$cp_repo/.codex/.probe-codex-owned" ] || malo "quitar dejo la marca colgada"
[ -d "$cp_repo/probe-ran" ] || malo "quitar borro la evidencia (probe-ran/)"

caso "codex --instalar NO pisa un shim desconocido en esa ruta"
cxajeno="$SANDBOX/codex-ajeno"
mkdir -p "$cxajeno/.codex/hooks"
( cd "$cxajeno" && git init -q . >/dev/null 2>&1 ) || true
printf '#!/usr/bin/env bash\n# hook propio del usuario\nexit 0\n' > "$cxajeno/.codex/hooks/summonaikit-harness.sh"
antes_cx="$(cksum < "$cxajeno/.codex/hooks/summonaikit-harness.sh")"
out="$(bash "$tool" --instalar "$cxajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "pisar un shim desconocido debe fallar (dio $rc)"
printf '%s' "$out" | grep -q 'no es mio' || malo "el rechazo del shim ajeno no dice por que: $out"
[ "$antes_cx" = "$(cksum < "$cxajeno/.codex/hooks/summonaikit-harness.sh")" ] || malo "PISO el shim desconocido"
out="$(bash "$tool" --quitar "$cxajeno" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "borrar un shim desconocido debe fallar (dio $rc)"
[ -f "$cxajeno/.codex/hooks/summonaikit-harness.sh" ] || malo "BORRO el shim del usuario"

# Misma leccion H1 que 7.2: la identidad no puede ser "el archivo menciona el
# probe-id". Un hook ajeno que lo cite en un comentario no es nuestro.
caso "H1: shim ajeno que MENCIONA el probe-id (sin marca) no se pisa ni se quita"
cxh1="$SANDBOX/codex-menciona"
mkdir -p "$cxh1/.codex/hooks"
( cd "$cxh1" && git init -q . >/dev/null 2>&1 ) || true
printf '#!/usr/bin/env bash\n# nota: ver --saikit-probe-id 6.2 del kit\nexit 0\n' > "$cxh1/.codex/hooks/summonaikit-harness.sh"
snap_cxh1="$(cksum < "$cxh1/.codex/hooks/summonaikit-harness.sh")"
out="$(bash "$tool" --instalar "$cxh1" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "H1 install codex: mencionar el probe-id no lo vuelve nuestro (dio $rc)"
[ "$snap_cxh1" = "$(cksum < "$cxh1/.codex/hooks/summonaikit-harness.sh")" ] || malo "H1 install codex: PISO el shim ajeno"
printf 'owner=otro\n' > "$cxh1/.codex/.probe-codex-owned"
# Con la marca YA puesta, la unica cosa que separa "nuestro" de "ajeno" es el
# sello del shim. Sin este caso, aflojar la identidad a un grep del probe-id
# quedaba sin atrapar: en la variante sin marca el install ya fallaba por la
# marca (lo dijo la mutacion mut_identidad_shim_laxa).
out="$(bash "$tool" --instalar "$cxh1" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "H1 install codex: con marca presente, mencionar el probe-id no lo vuelve nuestro (dio $rc)"
printf '%s' "$out" | grep -q 'no es mio' || malo "H1 install codex: el rechazo no dice que el shim no es nuestro: $out"
[ "$snap_cxh1" = "$(cksum < "$cxh1/.codex/hooks/summonaikit-harness.sh")" ] || malo "H1 install codex: PISO el shim ajeno teniendo la marca"
out="$(bash "$tool" --quitar "$cxh1" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "H1 quitar codex: con marca ajena pero shim ajeno no se borra (dio $rc)"
printf '%s' "$out" | grep -qi 'no lo escribi\|no es mio' \
  || malo "H1 quitar codex: el rechazo no dice que el shim no es nuestro: $out"
[ "$snap_cxh1" = "$(cksum < "$cxh1/.codex/hooks/summonaikit-harness.sh")" ] || malo "H1 quitar codex: BORRO el shim ajeno"

# ---- CodeRabbit PR #15 ------------------------------------------------------
# CR1: la MARCA sola tambien es estado reclamado. Si existe sin shim, el install
# la pisaba sin mirarla; un archivo ajeno con ese nombre se perdia.
caso "CR1: una marca AJENA (sin la linea owner=) no se pisa, ni sin shim"
cxm="$SANDBOX/codex-marca-ajena"
mkdir -p "$cxm/.codex"
( cd "$cxm" && git init -q . >/dev/null 2>&1 ) || true
printf 'datos del usuario, no del probe\n' > "$cxm/.codex/.probe-codex-owned"
snap_cxm="$(cksum < "$cxm/.codex/.probe-codex-owned")"
out="$(bash "$tool" --instalar "$cxm" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "CR1: pisar una marca ajena debe salir 2, dio $rc"
printf '%s' "$out" | grep -q 'no es mio' || malo "CR1: el rechazo no dice que la marca no es nuestra: $out"
[ "$snap_cxm" = "$(cksum < "$cxm/.codex/.probe-codex-owned")" ] || malo "CR1: PISO la marca ajena"
[ ! -e "$cxm/.codex/hooks/summonaikit-harness.sh" ] || malo "CR1: escribio el shim igual"

# CR3 (Major): el shim se publicaba ANTES que la marca. Si la escritura de la
# marca fallaba, el shim quedaba VIVO tapando al harness real y --quitar se
# negaba a sacarlo por falta de marca: el gate apagado sin vuelta atras por
# herramienta. El orden correcto es marca primero.
caso "CR3: si la marca no se puede escribir, NO queda un shim vivo"
cxo="$SANDBOX/codex-orden"
mkdir -p "$cxo"
( cd "$cxo" && git init -q . >/dev/null 2>&1 ) || true
bash "$tool" --instalar "$cxo" --host codex >/dev/null 2>&1
rm -f "$cxo/.codex/hooks/summonaikit-harness.sh"          # deja la marca NUESTRA sin shim
chmod 444 "$cxo/.codex/.probe-codex-owned" 2>/dev/null || true
if printf 'x\n' > "$cxo/.codex/.probe-codex-owned" 2>/dev/null; then
  echo "    unknown: no se pudo hacer la marca de solo-lectura; el orden no se pudo medir"
  chmod 644 "$cxo/.codex/.probe-codex-owned" 2>/dev/null || true
else
  out="$(bash "$tool" --instalar "$cxo" --host codex 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] || malo "CR3: la marca no se pudo escribir y aun asi salio 0"
  [ ! -e "$cxo/.codex/hooks/summonaikit-harness.sh" ] \
    || malo "CR3: dejo el shim VIVO sin marca — es el estado que --quitar no puede limpiar"
  chmod 644 "$cxo/.codex/.probe-codex-owned" 2>/dev/null || true
fi

# CR4: un symlink en .codex/ saca la escritura fuera del repo y con eso esquiva
# la negativa a tocar el perfil real (<repo>/.codex -> ~/.codex mete el shim
# adentro del perfil). La guarda de destino mira el destino, no los componentes.
caso "CR4: un <repo>/.codex que es symlink se rechaza, en instalar y en quitar"
cxs="$SANDBOX/codex-symlink"
mkdir -p "$cxs" "$SANDBOX/codex-symlink-afuera/hooks"
( cd "$cxs" && git init -q . >/dev/null 2>&1 ) || true
ln -s "$SANDBOX/codex-symlink-afuera" "$cxs/.codex" 2>/dev/null || true
if [ ! -L "$cxs/.codex" ]; then
  echo "    unknown: este sistema no creo un symlink real; la guarda no se pudo medir"
else
  out="$(bash "$tool" --instalar "$cxs" --host codex 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "CR4 instalar: un .codex symlink debe salir 2, dio $rc"
  printf '%s' "$out" | grep -qi 'symlink' || malo "CR4: el rechazo no nombra el symlink: $out"
  [ ! -e "$SANDBOX/codex-symlink-afuera/hooks/summonaikit-harness.sh" ] \
    || malo "CR4: ESCRIBIO del otro lado del symlink (fuera del repo descartable)"
  # Del otro lado se deja un shim que SI lleva el sello: asi el caso mide la
  # guarda del symlink y no la de identidad — ni siquiera algo que parece
  # nuestro se borra a traves de un link.
  printf '#!/usr/bin/env bash\n# saikit-probe-shim-id: 6.2\nexit 0\n' \
    > "$SANDBOX/codex-symlink-afuera/hooks/summonaikit-harness.sh"
  printf 'owner=tools/probe-zcode-output.sh\n' > "$SANDBOX/codex-symlink-afuera/.probe-codex-owned"
  out="$(bash "$tool" --quitar "$cxs" --host codex 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "CR4 quitar: un .codex symlink debe salir 2, dio $rc"
  [ -f "$SANDBOX/codex-symlink-afuera/hooks/summonaikit-harness.sh" ] \
    || malo "CR4: BORRO del otro lado del symlink"
fi

else
  echo "    unknown: git no disponible o no pudo inicializar; el registro codex no se pudo medir"
fi

# ---- B6: las tres guardas que 6.2 abre y cierra ---------------------------
caso "codex se niega a instalar si el dest resuelve a \$HOME/.codex"
# El agujero: la lista de rechazo tenia .claude*/.zcode*/.grok* y NO .codex*.
# Mientras no existia --host codex era una inconsistencia; ahora es un agujero.
mkdir -p "$HOME/.codex"
out="$(bash "$tool" --instalar "$HOME/.codex" --host codex 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "instalar sobre \$HOME/.codex debe fallar (dio $rc)"
printf '%s' "$out" | grep -q 'perfil real' \
  || malo "tiene que rechazarlo POR SER el perfil, no por otra cosa: $out"
[ ! -e "$HOME/.codex/.codex" ] || malo "escribio adentro del perfil codex"
[ ! -e "$HOME/.codex/hooks" ] || malo "escribio hooks/ adentro del perfil codex"
rmdir "$HOME/.codex" 2>/dev/null || true

caso "codex se niega a instalar sobre el repo del PRODUCTO (el shim mataria el gate)"
# El shim REEMPLAZA al harness (medido en 6.1). Apuntar el probe al repo del kit
# apagaria el gate ahi sin avisar, y la medicion siguiente seria de otra cosa.
cxprod="$SANDBOX/codex-producto"
mkdir -p "$cxprod/hooks"
( cd "$cxprod" && git init -q . >/dev/null 2>&1 ) || true
printf '#!/usr/bin/env bash\n# harness del producto\n' > "$cxprod/hooks/summonaikit-harness.sh"
out="$(bash "$tool" --instalar "$cxprod" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "instalar sobre el repo del producto debe salir 2, dio $rc"
printf '%s' "$out" | grep -qi 'producto' \
  || malo "tiene que rechazarlo POR SER el repo del producto: $out"
[ ! -e "$cxprod/.codex/hooks/summonaikit-harness.sh" ] || malo "escribio el shim sobre el repo del producto"

caso "codex: rutas con metacaracteres de shell se rechazan (fail-closed)"
# El shim interpola las rutas en un script bash entre comillas dobles: un \$ o un
# backtick ahi ejecutaria expresiones en CADA fase de CADA turno del host.
cxmal="$SANDBOX/codex-mal-\$home"
mkdir -p "$cxmal"
out="$(bash "$tool" --instalar "$cxmal" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "una ruta con \$ interpolada en el shim: esperaba exit 2, dio $rc"
printf '%s' "$out" | grep -qi 'metacaracteres' \
  || malo "tiene que rechazarla POR los metacaracteres: $out"
[ ! -e "$cxmal/.codex" ] || malo "rechazo la ruta pero dejo el arbol puesto"

caso "codex: un dest que NO es la raiz de un repo git se rechaza"
# El .ps1 resuelve <toplevel>/.codex/hooks/... con git rev-parse --show-toplevel.
# Si el dest es un subdir, el shim queda en una ruta que NADIE lee: la medicion
# entera daria 'no corrio' y lo leeriamos como veredicto.
cxsub="$SANDBOX/codex-repo/subdir"
mkdir -p "$cxsub"
out="$(bash "$tool" --instalar "$cxsub" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "un subdir de repo debe salir 2 (el shim quedaria sin lector), dio $rc"
printf '%s' "$out" | grep -qi 'raiz\|toplevel' \
  || malo "tiene que rechazarlo POR no ser la raiz del repo: $out"
[ ! -e "$cxsub/.codex/hooks/summonaikit-harness.sh" ] || malo "escribio el shim en un subdir"
cxnorepo="$SANDBOX/codex-sin-repo"
mkdir -p "$cxnorepo"
out="$(bash "$tool" --instalar "$cxnorepo" --host codex 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "un dest que no es repo git debe salir 2, dio $rc"
printf '%s' "$out" | grep -qi 'repo git\|raiz' \
  || malo "tiene que rechazarlo POR no ser repo git: $out"

caso "codex: --host invalido sigue saliendo 2 y el mensaje ya nombra codex"
out="$(bash "$tool" --instalar "$cp_repo" --host inventado 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "esperaba exit 2 con --host inventado, dio $rc"
printf '%s' "$out" | grep -q 'codex' || malo "el mensaje de host invalido no menciona codex: $out"

echo "  test_probe_zcode_output: codex OK"

if [ "$fail" -ne 0 ]; then
  echo "test_probe_zcode_output: FAIL" >&2
  exit 1
fi
echo "test_probe_zcode_output: OK"
