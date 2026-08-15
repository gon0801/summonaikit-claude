#!/usr/bin/env bash
# Task 0.3 — el verificador del REGISTRO del hook.
#
# El modo de falla que cubre: `settings.json` deja de apuntar al hook. El
# archivo del hook puede estar perfecto y el gate simplemente no existir. Hoy
# nada lo detecta, porque todo lo que hay verifica CONTENIDO.
#
# Contrato: reporta fuerte y sale 0 SIEMPRE (fail-open, Core Rule 1). Corre en
# SessionStart; un verificador que rompe el arranque es peor que no tenerlo.
# Lo que no se puede observar se reporta `unknown`, nunca como ausencia
# (Core Rule 2).
#
# Core Rule 4: todo contra un tmpdir. Jamas toca `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="$here/../tools/check-hook-registration.sh"
# Comprobado: sin `tmp` los fixtures se escribirian en `/completo.json` y los
# casos pasarian por el motivo equivocado (Task 0.4).
tmp="$(mktemp -d)" || { echo "test_hook_registration: FAIL (mktemp)" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# Registro completo: las 3 fases que el hook necesita, con un matcher de
# PostToolUse SANO (cubre Agent). Desde la Task 3.7 el verificador reporta si el
# matcher no cubre Agent (CORRECCION 2/14); el fixture "completo/sano" tiene que
# serlo de verdad, o "registro completo => silencio" dejaria de significar completo.
escribir_settings_completo() {
  cat > "$1" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=prompt bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash|Edit|Write|apply_patch|Task|Agent",
        "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=tool bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=stop bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ],
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=session bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ]
  }
}
JSON
}

# Task 10.6: SessionStart entra al fixture "completo" porque un registro completo
# hoy la incluye — sin ella el verificador avisa (con razon) que las reglas
# permanentes no llegan, y "completo => SILENCIO" dejaria de significar completo.
# NO entra en `escribir_settings_real_sin_agent`: ese fixture representa el
# registro REAL del operador, que no la tiene, y es el que ata el advisory.

# El matcher REAL que usa el operador hoy (sin Agent). Es el fixture del caso
# "registro real" y de los casos de matcher: cuenta las 3 fases (el hook corre)
# pero el verificador tiene que advertir el hueco de Agent. No se hace pasar por
# "completo/sano".
escribir_settings_real_sin_agent() {
  cat > "$1" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=prompt bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash|Edit|Write|apply_patch|Task",
        "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=tool bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude SUMMONAIKIT_HOOK_PHASE=stop bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
    ]
  }
}
JSON
}

# ---------------------------------------------------------------- 1) presente
caso "registro completo => SILENCIO y exit 0"
escribir_settings_completo "$tmp/completo.json"
out="$(bash "$tool" --settings "$tmp/completo.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "esperaba silencio, imprimio: $out"

# ------------------------------------------------------------------ 2) ausente
caso "sin ninguna referencia al hook => reporta FUERTE y exit 0 (fail-open)"
cat > "$tmp/vacio.json" <<'JSON'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo hola" } ] } ] } }
JSON
out="$(bash "$tool" --settings "$tmp/vacio.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto: esperaba exit 0, dio $rc"
[ -n "$out" ] || malo "esperaba un reporte, no imprimio nada"
printf '%s' "$out" | grep -qi 'UserPromptSubmit' || malo "no nombra la fase UserPromptSubmit faltante"
printf '%s' "$out" | grep -qi 'PostToolUse'      || malo "no nombra la fase PostToolUse faltante"
printf '%s' "$out" | grep -qi 'Stop'             || malo "no nombra la fase Stop faltante"

# --------------------------------------------------------------- 3) parcial
caso "registro PARCIAL (falta Stop) => nombra solo la que falta"
python - "$tmp/completo.json" "$tmp/parcial.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
del d['hooks']['Stop']
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --settings "$tmp/parcial.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'Stop' || malo "no nombra la fase Stop faltante"
printf '%s' "$out" | grep -qi 'UserPromptSubmit' && malo "reporta UserPromptSubmit que SI esta registrada"

# ------------------------------------------------- 4) no observable: no existe
caso "settings.json inexistente => 'unknown', no 'ausente', y exit 0"
out="$(bash "$tool" --settings "$tmp/no-existe.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "Core Rule 2: debe decir unknown, no afirmar ausencia"

# ------------------------------------------------- 5) no observable: corrupto
caso "settings.json ilegible (JSON roto) => 'unknown' y exit 0"
printf '{ "hooks": { esto no es json\n' > "$tmp/roto.json"
out="$(bash "$tool" --settings "$tmp/roto.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "fail-open roto: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "Core Rule 2: JSON roto es unknown, no ausencia"

# ------------------------------------- 6) el registro puede vivir en el local
caso "registro presente SOLO en settings.local.json => silencio"
printf '{ "hooks": {} }\n' > "$tmp/base-vacia.json"
escribir_settings_completo "$tmp/local-completo.json"
out="$(bash "$tool" --settings "$tmp/base-vacia.json" --local-settings "$tmp/local-completo.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "el registro en el local cuenta; esperaba silencio, imprimio: $out"

# ============================================================================
# Task 0.4 — los tres defectos de la revision cruzada de la Phase 0 (2026-08-10)
# ============================================================================

# ------------------------------------------- 7) invocacion mal formada: no gira
caso "un flag SIN valor no cuelga (medido: giraba para siempre)"
# `timeout` es el unico que puede afirmar esto: el defecto original no era un
# exit code equivocado, era que el `while` no terminaba nunca. Sin el tope, este
# caso colgaria la bateria entera en vez de reportar.
out="$(timeout 5 bash "$tool" --settings 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "sigue colgado: el bucle de argumentos no termina"
[ "$rc" -eq 0 ] || malo "fail-open roto: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "una invocacion que no se pudo atender es unknown, no silencio: $out"

caso "un flag desconocido tampoco gira"
out="$(timeout 5 bash "$tool" --no-existe-este-flag 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "un flag desconocido cuelga el bucle"

# ------------------------------- 8) mencionar el hook no es tenerlo registrado
caso "un comando que solo NOMBRA el hook sin ejecutarlo NO cuenta como registro"
cat > "$tmp/mencion.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo summonaikit-harness.sh" } ] } ],
    "PostToolUse":      [ { "hooks": [ { "type": "command", "command": "printf '%s' summonaikit-harness.sh" } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "echo summonaikit-harness.sh" } ] } ]
  }
}
JSON
out="$(bash "$tool" --settings "$tmp/mencion.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -n "$out" ] || malo "un settings que solo menciona el hook quedo en SILENCIO: el gate no corre en ninguna fase"
printf '%s' "$out" | grep -qi 'UserPromptSubmit' || malo "no nombra UserPromptSubmit, que solo se menciona"

caso "un comando COMPUESTO que ejecuta el hook despues de un echo SI cuenta"
# La direccion peligrosa del filtro anterior: miraba solo el primer token, asi
# que esto quedaba como NO registrado y gritaba en cada arranque sobre un
# registro que si existe.
cat > "$tmp/compuesto.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo armando && bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ],
    "PostToolUse":      [ { "hooks": [ { "type": "command", "command": "echo x; bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "true || bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ],
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ]
  }
}
JSON
out="$(bash "$tool" --settings "$tmp/compuesto.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "un comando compuesto que SI ejecuta el hook debe contar como registro: $out"

caso "el registro REAL (matcher sin Agent) advierte el hueco, sin reportar fases"
# El settings real del operador lleva env vars por delante + bash -c y un matcher
# de PostToolUse que NO cubre Agent (Bash|Edit|Write|apply_patch|Task). Desde la
# Task 3.7 el verificador reporta ese hueco (CORRECCION 2). Lo que NO debe hacer
# es gritar "INCOMPLETO" o "el gate NO corre": las 3 fases SI corren, el hook SI
# esta registrado; el matcher es un hueco independiente.
escribir_settings_real_sin_agent "$tmp/real.json"
out="$(bash "$tool" --settings "$tmp/real.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi "no cubre 'Agent'" || malo "el matcher real sin Agent debe disparar el aviso: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "las 3 fases corren: no debe reportar INCOMPLETO"
printf '%s' "$out" | grep -qi 'el gate NO corre' && malo "el gate SI corre en las 3 fases"

# ------------------- 8-bis) Task 10.6: SessionStart se afirma SEPARADA y advisory
# El registro real tiene las 3 fases del gate y NO tiene SessionStart. El
# verificador tiene que decirlo, y tiene que decirlo SIN disfrazarlo de gate
# roto: las reglas permanentes son una mejora, el gate corre igual. Si esto se
# reportara como fase faltante, todo install existente pasaria a "INCOMPLETO"
# — la alarma falsa que la Task 0.4 prohibe.
caso "3 fases sin SessionStart => avisa de reglas permanentes, NO de gate roto"
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'REGLAS PERMANENTES' || malo "sin SessionStart debe avisar de las reglas permanentes: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "SessionStart ausente NO vuelve incompleto al registro del gate"
printf '%s' "$out" | grep -qi 'el gate NO corre' && malo "el gate corre igual sin SessionStart"

caso "con SessionStart registrada, el aviso de reglas permanentes NO aparece"
# Exigir exit 0 y silencio TOTAL, no solo la ausencia del aviso: con "no
# contiene REGLAS PERMANENTES" alcanzaba con que el tool reventara con otra
# salida para que el caso pasara en verde (CodeRabbit PR #19).
if out_s="$(bash "$tool" --settings "$tmp/completo.json" 2>&1)"; then rc_s=0; else rc_s=$?; fi
[ "$rc_s" -eq 0 ] || malo "registro completo debe terminar con exit 0, dio $rc_s: $out_s"
[ -z "$out_s" ] || malo "registro completo (con SessionStart) debe quedar en SILENCIO: $out_s"

# ------------------- 9) lo no observado no vuelve ausente a lo que si se observo
caso "settings legible INCOMPLETO + local ILEGIBLE => unknown, no ausencia"
python - "$tmp/completo.json" "$tmp/parcial2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
del d['hooks']['Stop']
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
printf '{ "hooks": { roto\n' > "$tmp/local-roto.json"
out="$(bash "$tool" --settings "$tmp/parcial2.json" --local-settings "$tmp/local-roto.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "Core Rule 2: con un settings ilegible, la fase faltante podria estar ahi => unknown"
printf '%s' "$out" | grep -qi 'el gate NO corre' \
  && malo "afirma ausencia sobre una fase que podria vivir en el archivo que no se pudo leer"

# --------------- 10) el reporte distingue ausencia OBSERVADA de no observada
# Sin esto, un mutante que llame `unknown` a todo --o que reporte todo como
# INCOMPLETO-- pasaria los casos de arriba: los dos dicen algo, y hasta ahora
# los asserts solo miraban que dijeran ALGO.
caso "ausencia OBSERVADA (todo legible) se afirma, y no se disfraza de unknown"
out="$(bash "$tool" --settings "$tmp/vacio.json" 2>&1)"
printf '%s' "$out" | grep -qi 'el gate NO corre' \
  || malo "con todo legible SI se puede afirmar la ausencia, y hay que afirmarla"
printf '%s' "$out" | grep -qi 'unknown' \
  && malo "una ausencia observada no es unknown"

caso "no observado (settings inexistente) NO se reporta como incompleto"
out="$(bash "$tool" --settings "$tmp/no-existe.json" 2>&1)"
printf '%s' "$out" | grep -qi 'el gate NO corre' \
  && malo "no se afirma que el gate no corre a partir de un archivo que no se pudo mirar"

# ============================================================================
# Task 3.7 — el matcher de PostToolUse y la herramienta de subagentes (Agent)
# ============================================================================
# Un subagente read-only (Read/Grep/Glob) no genera eventos que lleguen al gate
# si el matcher no cubre Agent; su rol no se registra. El verificador lo REPORTA
# (fail-open, exit 0); no edita el registro.

caso "matcher de PostToolUse sin Agent => reporta FUERTE y exit 0"
cat > "$tmp/no-agent.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash|Edit|Write","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/no-agent.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "fail-open: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi "no cubre 'Agent'" || malo "debe reportar que el matcher no cubre Agent: $out"

caso "matcher '*' cubre Agent y calla"
cat > "$tmp/star.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"*","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/star.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "matcher '*' cubre todo => silencio: $out"

caso "un matcher cubierto entre varios grupos => calla"
cat > "$tmp/mix.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]},{"matcher":"Agent","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/mix.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "basta UN grupo que cubra Agent => silencio: $out"

caso "base sin Agent + local con Agent => calla"
cat > "$tmp/base-noagent.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
cat > "$tmp/local-agent.json" <<'JSON'
{ "hooks": { "PostToolUse": [{"matcher":"Agent","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/base-noagent.json" --local-settings "$tmp/local-agent.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "el local trae Agent => cubre => silencio: $out"

caso "base sin Agent + local ilegible => unknown (no ausencia)"
printf '{ roto\n' > "$tmp/local-roto2.json"
out="$(bash "$tool" --settings "$tmp/base-noagent.json" --local-settings "$tmp/local-roto2.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "Core Rule 2: el local ilegible podria tener Agent => unknown"
printf '%s' "$out" | grep -qi "no cubre 'Agent'" && malo "no afirma ausencia de Agent con un local ilegible"

caso "matcher que no compila como regex => unknown, no ausencia"
cat > "$tmp/badregex.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash[","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/badregex.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "un matcher que no compila es unknown, no ausencia"
  printf '%s' "$out" | grep -qi "no cubre 'Agent'" && malo "no afirma ausencia con un matcher que no se pudo compilar"

# ============================================================================
# Task 5.4 — la SEGUNDA forma de registro: hooks.events.* (user-config de zcode)
# ============================================================================
# zcode registra en ~/.zcode/cli/config.json con `hooks.events.<Evento>[]`, con
# `{matcher?, hooks:[{type,command,timeout}]}` por grupo. Tres diferencias con
# Claude: (1) `hooks.enabled` debe ser true o los hooks de archivo NO corren;
# (2) el matcher de UserPromptSubmit/Stop se prueba contra el texto/preview, no
# contra el nombre de la herramienta -- tener matcher ahi es el error que la DoD
# nombra; (3) el alias Task<->Agent hace que un matcher 'Task' SÍ cubra Agent.

# Fixture zcode completo y sano: enabled true, 3 fases, UPS/Stop sin matcher,
# PTU cubriendo Task|Agent. Este fixture es la baseline de "completo => silencio".
escribir_zcode_completo() {
  cat > "$1" <<'JSON'
{
  "hooks": {
    "enabled": true,
    "events": {
      "UserPromptSubmit": [
        { "hooks": [ { "type": "command", "command": "bash \"/c/claude/hooks/summonaikit-harness.sh\"", "timeout": 15 } ] }
      ],
      "PostToolUse": [
        { "matcher": "Bash|Edit|Write|Read|apply_patch|Task|Agent",
          "hooks": [ { "type": "command", "command": "bash \"/c/claude/hooks/summonaikit-harness.sh\"", "timeout": 15 } ] }
      ],
      "Stop": [
        { "hooks": [ { "type": "command", "command": "bash \"/c/claude/hooks/summonaikit-harness.sh\"", "timeout": 15 } ] }
      ]
    }
  }
}
JSON
}

# -------------------------------- A3.1) completo => silencio
caso "zcode: registro completo (--zcode-config) => SILENCIO y exit 0"
escribir_zcode_completo "$tmp/zc-completo.json"
out="$(bash "$tool" --zcode-config "$tmp/zc-completo.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "esperaba silencio, imprimio: $out"

# -------------------------------- A3.2) parcial (falta Stop)
caso "zcode: sin Stop => INCOMPLETO y nombra solo Stop"
python - "$tmp/zc-completo.json" "$tmp/zc-sin-stop.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
del d['hooks']['events']['Stop']
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-sin-stop.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'Stop' || malo "no nombra la fase Stop faltante"
printf '%s' "$out" | grep -qi 'UserPromptSubmit' && malo "reporta UPS que SI esta registrada"

# -------------------------------- A3.3) matcher en UPS/Stop => reporta fuerte
caso "zcode: UPS con matcher => reporta fuerte (matcher ahi es el error de la DoD)"
python - "$tmp/zc-completo.json" "$tmp/zc-ups-match.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['events']['UserPromptSubmit'][0]['matcher'] = 'Task'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-ups-match.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'UserPromptSubmit' || malo "debe nombrar UserPromptSubmit"
printf '%s' "$out" | grep -qi 'matcher' || malo "debe mencionar el matcher indebido: $out"

caso "zcode: Stop con matcher vacio (\"\") => reporta fuerte igual (r2.4)"
python - "$tmp/zc-completo.json" "$tmp/zc-stop-empty.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['events']['Stop'][0]['matcher'] = ''
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-stop-empty.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'Stop' || malo "debe nombrar Stop"
printf '%s' "$out" | grep -qi 'matcher' || malo "la clave matcher presente (aun vacia) es error"

# -------------------------------- A3.4) alias Task<->Agent
caso "zcode: PTU matcher 'Task' solo => SILENCIO (el alias cubre Agent)"
python - "$tmp/zc-completo.json" "$tmp/zc-task-only.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['events']['PostToolUse'][0]['matcher'] = 'Task'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-task-only.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "Task cubre Agent via alias en zcode => silencio: $out"

caso "zcode: PTU matcher 'Bash' solo => reporta (no cubre Task ni Agent)"
python - "$tmp/zc-completo.json" "$tmp/zc-bash-only.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['events']['PostToolUse'][0]['matcher'] = 'Bash'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-bash-only.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi "no cubre" || malo "Bash no cubre Agent ni Task => debe reportar: $out"

# -------------------------------- A3.5) enabled estricto + ilegible
caso "zcode: user-config ilegible => unknown (no INCOMPLETO)"
printf '{ "hooks": { roto\n' > "$tmp/zc-roto.json"
out="$(bash "$tool" --zcode-config "$tmp/zc-roto.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "ilegible => unknown"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "ilegible no debe afirmarse como INCOMPLETO"

caso "zcode: enabled=\"yes\" (string) => reporta fuerte (no es JSON true)"
python - "$tmp/zc-completo.json" "$tmp/zc-yes.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['enabled'] = 'yes'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-yes.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'enabled' || malo "debe avisar que enabled no es true: $out"

caso "zcode: enabled=1 (numero) => reporta fuerte"
python - "$tmp/zc-completo.json" "$tmp/zc-one.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['enabled'] = 1
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-one.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'enabled' || malo "1 no es JSON true => debe avisar"

# -------------------------------- A3.6) no se mezclan los modos
caso "zcode: --zcode-config + --settings juntos => unknown (no se mezclan)"
escribir_zcode_completo "$tmp/zc-mix.json"
escribir_settings_completo "$tmp/cl-mix.json"
out="$(bash "$tool" --zcode-config "$tmp/zc-mix.json" --settings "$tmp/cl-mix.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "mezclar flags => unknown: $out"

caso "zcode: --zcode-config sin valor => unknown (fail-open, leccion 0.4)"
out="$(timeout 5 bash "$tool" --zcode-config 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "el bucle de argumentos se colgo"
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "flag sin valor => unknown"

# -------------------------------- A3.7) regresion: --settings NO interpreta hooks.events
caso "zcode: regresion -- un config con FORMA zcode pasado como --settings => INCOMPLETO (no silencio)"
escribir_zcode_completo "$tmp/zc-como-claude.json"
out="$(bash "$tool" --settings "$tmp/zc-como-claude.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
# Modo Claude busca hooks.<fase> (no hooks.events): las 3 fases viven bajo events,
# asi que Claude NO las ve => debe reportar faltantes, no callar. Sin esto, un
# mutante que leyera hooks.events en modo Claude daria silencio falso.
printf '%s' "$out" | grep -qi 'UserPromptSubmit' \
  || malo "modo Claude no debe interpretar hooks.events como registro Claude: $out"

# ================================================ Task 6.5 — la TERCERA forma
# En Codex el registro no nombra al hook: nombra al WRAPPER (.ps1), y el
# wrapper nombra al hook. La afirmacion se vuelve indirecta y se parte en DOS
# separadas — (a) el registro nombra al wrapper; (b) el wrapper existe y nombra
# al hook — porque colapsarlas esconderia cual de las dos se rompio. Mismo
# contrato de siempre: exit 0 SIEMPRE, unknown != ausente, silencio si todo ok.
codex_dir=''
nuevo_codex_reg() {
  codex_dir="$tmp/codex-reg-$RANDOM"
  mkdir -p "$codex_dir/hooks"
}

escribir_codex_json_completo() {
  cat > "$codex_dir/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/x/.codex/hooks/summonaikit-harness.ps1\" -Phase prompt" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Bash|Edit|Write|apply_patch|Task|exec|local_shell_call|shell_command|commandExecution",
        "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/x/.codex/hooks/summonaikit-harness.ps1\" -Phase tool" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/x/.codex/hooks/summonaikit-harness.ps1\" -Phase stop" } ] }
    ]
  }
}
JSON
}

escribir_codex_json_sin_stop() {
  cat > "$codex_dir/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -File \"C:/Users/x/.codex/hooks/summonaikit-harness.ps1\" -Phase prompt" } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "powershell.exe -NoProfile -File \"C:/Users/x/.codex/hooks/summonaikit-harness.ps1\" -Phase tool" } ] }
    ]
  }
}
JSON
}

escribir_codex_wrapper_ok() {
  cat > "$codex_dir/hooks/summonaikit-harness.ps1" <<'PS1'
param([string]$Phase)
$env:SUMMONAIKIT_HOOK_TARGET = "codex"
$hookPath = Join-Path $env:USERPROFILE ".codex\hooks\summonaikit-harness.sh"
$payload | & bash $hookPath
PS1
}

escribir_codex_wrapper_sin_hook() {
  cat > "$codex_dir/hooks/summonaikit-harness.ps1" <<'PS1'
param([string]$Phase)
Write-Output "wrapper que ya no lanza nada"
PS1
}

# Greptile P1 (PR #23): un wrapper viejo cuya UNICA mencion del hook vive en un
# comentario PowerShell. Con el grep de subcadena sin filtrar, la afirmacion
# (b) quedaba verde y el checker callaba con la cadena rota — "nombrar el hook
# no es ejecutarlo", el mismo modo de falla que la 0.4 cerro en los settings.
escribir_codex_wrapper_hook_solo_en_comentario() {
  cat > "$codex_dir/hooks/summonaikit-harness.ps1" <<'PS1'
param([string]$Phase)
# antes esto lanzaba summonaikit-harness.sh; se desactivo el 2026-08-01
   # ruta vieja: $env:USERPROFILE\.codex\hooks\summonaikit-harness.sh
Write-Output "wrapper desactivado"
PS1
}

caso "codex: registro completo + wrapper que nombra al hook => SILENCIO y exit 0"
nuevo_codex_reg; escribir_codex_json_completo; escribir_codex_wrapper_ok
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "esperaba silencio con las dos afirmaciones en verde: $out"

caso "codex: sin Stop => INCOMPLETO y nombra solo Stop (afirmacion a)"
nuevo_codex_reg; escribir_codex_json_sin_stop; escribir_codex_wrapper_ok
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 (fail-open), dio $rc"
printf '%s' "$out" | grep -q 'Stop' || malo "debe nombrar la fase Stop faltante: $out"
printf '%s' "$out" | grep -q 'UserPromptSubmit' && malo "no debe acusar fases registradas: $out"

caso "codex: wrapper AUSENTE con registro completo => reporta la afirmacion (b), no un registro roto"
nuevo_codex_reg; escribir_codex_json_completo
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'wrapper' || malo "debe reportar el wrapper (afirmacion b): $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "el registro (a) esta completo; no debe acusarlo: $out"

caso "codex: wrapper presente que NO nombra al hook => reporta la afirmacion (b)"
nuevo_codex_reg; escribir_codex_json_completo; escribir_codex_wrapper_sin_hook
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'wrapper' || malo "debe reportar que el wrapper no nombra al hook: $out"

caso "codex: wrapper que solo nombra al hook en un COMENTARIO => reporta la afirmacion (b) (Greptile P1)"
nuevo_codex_reg; escribir_codex_json_completo; escribir_codex_wrapper_hook_solo_en_comentario
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'wrapper' \
  || malo "una mencion en comentario no es codigo que lance el hook; debe reportar (b): $out"

caso "codex: hooks.json ilegible => unknown, no ausencia"
nuevo_codex_reg; printf '{ roto' > "$codex_dir/hooks.json"; escribir_codex_wrapper_ok
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "ilegible es unknown: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "ilegible NO es ausencia observada: $out"

caso "codex: --codex-hooks-json + --settings juntos => unknown (no se mezclan)"
nuevo_codex_reg; escribir_codex_json_completo; escribir_codex_wrapper_ok
out="$(bash "$tool" --codex-hooks-json "$codex_dir/hooks.json" --settings "$codex_dir/hooks.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "formas mezcladas es unknown: $out"

if [ "$fail" -ne 0 ]; then
  echo "test_hook_registration: FAIL" >&2
  exit 1
fi
echo "test_hook_registration: OK"
