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

# Task 16.5: reportar_recetario deriva el hookdir del settings (<dir>/hooks) en
# modo claude. Los fixtures "completo => silencio" usan --settings "$tmp/*.json",
# cuyo hookdir es $tmp/hooks: se les planta un recetario VALIDO (manifiesto +
# recetas del repo) para que el advisory no dispare y el "silencio" del registro
# completo siga siendo silencio.
repo="$(cd "$here/.." && pwd)"
mkdir -p "$tmp/hooks/recetas"
cp "$repo/recetas/MANIFEST.sha256" "$tmp/hooks/recetas/"
cp "$repo"/recetas/*.md "$tmp/hooks/recetas/"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# 18.22: `python` a secas no existe en un macOS pelado (solo python3) — los
# heredocs fallaban, los fixtures derivados quedaban vacios y el checker leia
# «unknown — ningun settings legible» (rc 4). Mismo orden que el tool bajo
# prueba: python3 primero, python despues.
py_bin=''
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1; then py_bin="$c"; break; fi
done

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
    ],
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "SUMMONAIKIT_HOOK_TARGET=claude bash -c 'bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"'" } ] }
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
"$py_bin" - "$tmp/completo.json" "$tmp/parcial.json" <<'PY'
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
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ],
    "PreToolUse":       [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"$HOME/.claude/hooks/summonaikit-harness.sh\"" } ] } ]
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

# ------------------- 8-ter) Task 18.11: PreToolUse se afirma SEPARADA y advisory
# Misma forma que SessionStart (10.6): la 4a fase se REPORTA, no entra en
# ESPERADAS. Meterla ahi marcaria INCOMPLETO cada host sin PreToolUse.
# El command del snippet NO fija SUMMONAIKIT_HOOK_PHASE=tool (pisa el payload).
caso "3 fases sin PreToolUse => avisa de merge a pelo, NO de gate roto"
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'PreToolUse' || malo "sin PreToolUse debe nombrar la 4a fase: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "PreToolUse ausente NO vuelve incompleto al registro del gate"
printf '%s' "$out" | grep -qi 'el gate NO corre' && malo "el gate corre igual sin PreToolUse"
printf '%s' "$out" | grep -qi 'HOOK_PHASE=tool' \
  || malo "el advisory debe advertir que el command no fije PHASE=tool: $out"

caso "con PreToolUse registrada, el aviso de merge a pelo NO aparece"
if out_p="$(bash "$tool" --settings "$tmp/completo.json" 2>&1)"; then rc_p=0; else rc_p=$?; fi
[ "$rc_p" -eq 0 ] || malo "registro completo debe terminar con exit 0, dio $rc_p: $out_p"
[ -z "$out_p" ] || malo "registro completo (con PreToolUse) debe quedar en SILENCIO: $out_p"

# ------------------- 9) lo no observado no vuelve ausente a lo que si se observo
caso "settings legible INCOMPLETO + local ILEGIBLE => unknown, no ausencia"
"$py_bin" - "$tmp/completo.json" "$tmp/parcial2.json" <<'PY'
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
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"*","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/star.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "matcher '*' cubre todo => silencio: $out"

caso "un matcher cubierto entre varios grupos => calla"
cat > "$tmp/mix.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]},{"matcher":"Agent","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
JSON
out="$(bash "$tool" --settings "$tmp/mix.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "basta UN grupo que cubra Agent => silencio: $out"

caso "base sin Agent + local con Agent => calla"
cat > "$tmp/base-noagent.json" <<'JSON'
{ "hooks": { "UserPromptSubmit": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PostToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "Stop": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "SessionStart": [{"hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}], "PreToolUse": [{"matcher":"Bash","hooks":[{"type":"command","command":"bash summonaikit-harness.sh"}]}] } }
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
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-sin-stop.json" <<'PY'
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
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-ups-match.json" <<'PY'
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
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-stop-empty.json" <<'PY'
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
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-task-only.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['events']['PostToolUse'][0]['matcher'] = 'Task'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-task-only.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "Task cubre Agent via alias en zcode => silencio: $out"

caso "zcode: PTU matcher 'Bash' solo => reporta (no cubre Task ni Agent)"
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-bash-only.json" <<'PY'
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
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-yes.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
d['hooks']['enabled'] = 'yes'
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
PY
out="$(bash "$tool" --zcode-config "$tmp/zc-yes.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'enabled' || malo "debe avisar que enabled no es true: $out"

caso "zcode: enabled=1 (numero) => reporta fuerte"
"$py_bin" - "$tmp/zc-completo.json" "$tmp/zc-one.json" <<'PY'
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
# CodeRabbit (PR #25, minor): el assert va al DIAGNOSTICO especifico — con
# `wrapper` a secas, cualquier otra linea del wrapper (p.ej. "no existe") lo
# satisfaria y el caso pasaria sin fijar el filtrado de comentarios.
printf '%s' "$out" | grep -q 'existe pero NO nombra summonaikit-harness.sh en ninguna linea de codigo' \
  || malo "una mencion en comentario no es codigo que lance el hook; debe reportar (b) con su diagnostico exacto: $out"

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

# ============================================ Task 7.5 — la CUARTA forma (grok)
# En Grok el registro es un JSON PROPIO (<dir>/summonaikit.json) cuyo command
# nombra al hook DIRECTAMENTE, en forma PowerShell: '& "bash.exe" "hook"' — 7.1
# midio que el shell de hooks en Windows es powershell.exe y que el call
# operator '&' es la invocacion (la forma zcode muere con exit 1). TRES
# afirmaciones SEPARADAS, no colapsadas (leccion 0.4 + Greptile P1 del PR #25):
#   (1) el JSON nombra al hook en una linea que no solo IMPRIME;
#   (2) el hook que el JSON nombra EXISTE y lleva el marcador de la linea 2;
#   (3) el matcher de PostToolUse cubre spawn_subagent o su alias Task (7.1).
# Contrato intacto: exit 0 SIEMPRE, unknown != ausente.
n_grok_reg=0
grok_dir=''
nuevo_grok_reg() {
  n_grok_reg=$((n_grok_reg + 1))
  grok_dir="$tmp/grok-reg-$n_grok_reg"
  mkdir -p "$grok_dir/hooks"
}

escribir_hook_grok() {
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# SAIKIT-CLAUDE-OWNED summonaikit-claude 7.5'
    printf '%s\n' 'exit 0'
  } > "$grok_dir/hooks/summonaikit-harness.sh"
}

# $1=command (YA escapado para JSON), $2=matcher de PostToolUse ('' => sin matcher).
escribir_grok_json() {
  local m=''
  [ -n "$2" ] && m="\"matcher\": \"$2\","
  cat > "$grok_dir/hooks/summonaikit.json" <<JSON
{
  "saikit_owned": "summonaikit-claude",
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "$1", "timeout": 30 } ] } ],
    "PostToolUse": [ { $m "hooks": [ { "type": "command", "command": "$1", "timeout": 30 } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "$1", "timeout": 600 } ] } ]
  }
}
JSON
}

# El command en forma PowerShell, YA escapado para vivir dentro del string JSON.
grok_cmd_json() {
  printf '& \\"C:/Program Files/Git/bin/bash.exe\\" \\"%s\\"' "$grok_dir/hooks/summonaikit-harness.sh"
}

caso "grok: registro completo (JSON + hook con marca + matcher) => SILENCIO y exit 0"
nuevo_grok_reg; escribir_hook_grok
escribir_grok_json "$(grok_cmd_json)" 'Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace|write'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "esperaba silencio con las tres afirmaciones en verde: $out"

caso "grok: un JSON que solo IMPRIME el nombre del hook NO cuenta (afirmacion 1)"
nuevo_grok_reg; escribir_hook_grok
escribir_grok_json 'echo summonaikit-harness.sh' ''
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "fail-open: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'INCOMPLETO' || malo "debe reportar el registro incompleto: $out"
printf '%s' "$out" | grep -q 'PostToolUse' || malo "debe nombrar la fase PostToolUse faltante: $out"

caso "grok: el JSON nombra un hook que NO existe => afirmacion (2), no un registro roto"
nuevo_grok_reg
escribir_grok_json "$(grok_cmd_json)" 'spawn_subagent|Task|Bash'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'NO existe' || malo "debe reportar que el hook nombrado no existe: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "las 3 fases estan registradas; no debe acusar el registro"

caso "grok: hook presente pero SIN el marcador de la linea 2 => afirmacion (2)"
nuevo_grok_reg
printf '#!/usr/bin/env bash\n# un hook de otro, sin marcador\nexit 0\n' > "$grok_dir/hooks/summonaikit-harness.sh"
escribir_grok_json "$(grok_cmd_json)" 'spawn_subagent|Task|Bash'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'marcador' || malo "debe reportar el hook sin marcador: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "el registro esta completo; el hueco es del hook, no del JSON"

caso "grok: matcher sin spawn_subagent ni Task => afirmacion (3)"
nuevo_grok_reg; escribir_hook_grok
escribir_grok_json "$(grok_cmd_json)" 'Bash|Edit|Write'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -q "no cubre 'spawn_subagent'" \
  || malo "debe reportar que el matcher no cubre la delegacion: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "las 3 fases corren; el matcher es un hueco independiente"

caso "grok: matcher con SOLO 'Task' cubre spawn_subagent por alias => silencio"
nuevo_grok_reg; escribir_hook_grok
escribir_grok_json "$(grok_cmd_json)" 'Task'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "el alias Task cubre spawn_subagent (medido 7.1) => silencio: $out"

caso "grok: summonaikit.json ilegible => unknown, no ausencia"
nuevo_grok_reg; escribir_hook_grok
printf '{ roto\n' > "$grok_dir/hooks/summonaikit.json"
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "Core Rule 2: ilegible es unknown: $out"
printf '%s' "$out" | grep -qi 'INCOMPLETO' && malo "ilegible NO es ausencia observada: $out"

caso "grok: --grok-hooks-dir + --settings juntos => unknown (no se mezclan)"
nuevo_grok_reg; escribir_hook_grok
escribir_grok_json "$(grok_cmd_json)" 'Task'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" --settings "$grok_dir/hooks/summonaikit.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "formas mezcladas es unknown: $out"

caso "grok: --grok-hooks-dir sin valor => unknown (fail-open, leccion 0.4)"
out="$(timeout 5 bash "$tool" --grok-hooks-dir 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "el bucle de argumentos se colgo"
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "flag sin valor => unknown: $out"

# r2/CodeRabbit: la ruta citada en el command puede tener espacios (un
# 'C:/Users/John Doe/...' es un HOME real de Windows). Si la extraccion la
# parte en el espacio, la afirmacion (2) reporta un falso 'NO existe' sobre
# un hook que SI esta. El fixture cita la ruta ENTRE COMILLAS, como el JSON
# canonico del instalador.
caso "grok: hook nombrado bajo una ruta CON ESPACIOS cuenta entera (r2)"
n_grok_reg=$((n_grok_reg + 1))
grok_dir="$tmp/grok reg espacios $n_grok_reg"
mkdir -p "$grok_dir/hooks"
escribir_hook_grok
escribir_grok_json "$(grok_cmd_json)" 'Task'
out="$(bash "$tool" --grok-hooks-dir "$grok_dir/hooks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "el hook bajo ruta con espacios existe y lleva marca: silencio, no $out"

# ===================================================== Phase 15 -- --dsh-home
# dsh no se registra por archivo de hooks: el plugin se compone en
# <dsh-home>/cordis.patch.yml entre marcas. El verificador de dsh afirma: hook
# (existe + marcador), dir del plugin (4 archivos), patch (bloque entre marcas
# con hook: y las 4 personas subagent_<rol>).
escribir_hook_marca() {  # $1=dest
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# SAIKIT-CLAUDE-OWNED summonaikit-claude 0.0.1'
    printf '%s\n' 'exit 0'
  } > "$1"
}
escribir_patch_dsh() {  # $1=patch  $2=hook  $3=ddir(sin uso para name:)
  # El instalador escribe name: = paquete (@summonaikit/dsh-gate) y hook: en
  # forma WINDOWS (C:/...). El checker compara contra eso. El fixture usa rutas
  # POSIX ($tmp); el hook: se convierte con cygpath -m (PR #91).
  local hook_win
  hook_win="$2"
  if command -v cygpath >/dev/null 2>&1; then
    case "$2" in [A-Za-z]:/*|[A-Za-z]:\\*) : ;; *) hook_win="$(cygpath -m "$2" 2>/dev/null || printf '%s' "$2")" ;; esac
  fi
  cat > "$1" <<EOF
# >>> summonaikit-gate START -- managed by summonaikit-claude tools/install-hook.sh
- insert:
    - id: summonaikit-gate
      name: '@summonaikit/dsh-gate'
      config:
        hook: '$hook_win'
        bash: 'C:/Program Files/Git/bin/bash.exe'
    - id: subagent_implementer
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: spawn
        toolName: subagent_implementer
        backgroundMode: continuable
        persona: |-
          # implementer
    - id: subagent_verifier
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: spawn
        toolName: subagent_verifier
        backgroundMode: continuable
        persona: |-
          # verifier
    - id: subagent_reviewer
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: spawn
        toolName: subagent_reviewer
        backgroundMode: continuable
        persona: |-
          # reviewer
    - id: subagent_adversary
      name: '@deepseek-ai/dsh-tool-subagent'
      config:
        provider: spawn
        toolName: subagent_adversary
        backgroundMode: continuable
        persona: |-
          # adversary
# <<< summonaikit-gate END
EOF
}
nuevo_dsh_reg() {
  n_dsh_reg=$((n_dsh_reg + 1))
  dsh_home="$tmp/dsh-reg-$n_dsh_reg"
  dsh_ddir="$dsh_home/profiles/node_modules/@summonaikit/dsh-gate"
  mkdir -p "$dsh_home/hooks" "$dsh_ddir"
  escribir_hook_marca "$dsh_home/hooks/summonaikit-harness.sh"
  : > "$dsh_ddir/index.js"
  : > "$dsh_ddir/translate.js"
  : > "$dsh_ddir/spawn-hook.js"
  : > "$dsh_ddir/package.json"
  escribir_patch_dsh "$dsh_home/cordis.patch.yml" "$dsh_home/hooks/summonaikit-harness.sh" "$dsh_ddir"
}
n_dsh_reg=0

caso "dsh: --dsh-home completo => SILENCIO y exit 0"
nuevo_dsh_reg
out="$(bash "$tool" --dsh-home "$dsh_home" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh completo: esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "dsh completo: esperaba silencio, imprimio: $out"

caso "dsh: sin la entrada entre marcas => habla (y exit 0, fail-open)"
nuevo_dsh_reg
printf -- '- insert:\n    - id: otromodulo\n      name: x\n' > "$dsh_home/cordis.patch.yml"
out="$(bash "$tool" --dsh-home "$dsh_home" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh sin entrada: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'PATCH DE DSH' || malo "dsh sin entrada deberia hablar del patch: $out"

caso "dsh: [hook:] apuntando a otra ruta => habla (la entrada no apunta al hook)"
nuevo_dsh_reg
escribir_patch_dsh "$dsh_home/cordis.patch.yml" "/otra/ruta/hooks/summonaikit-harness.sh" "$dsh_ddir"
out="$(bash "$tool" --dsh-home "$dsh_home" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh hook: apuntando a otra ruta: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'PATCH DE DSH' || malo "dsh con hook: a otra ruta deberia hablar: $out"

caso "dsh: --dsh-home sin valor => unknown (fail-open, leccion 0.4)"
out="$(timeout 5 bash "$tool" --dsh-home 2>&1)"; rc=$?
[ "$rc" -ne 124 ] || malo "el bucle de argumentos se colgo"
[ "$rc" -eq 0 ] || malo "dsh --dsh-home sin valor: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "flag sin valor => unknown: $out"

caso "dsh: --dsh-home + --settings juntos => unknown (no se mezclan)"
nuevo_dsh_reg
out="$(bash "$tool" --dsh-home "$dsh_home" --settings "$tmp/completo.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh formas mezcladas: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'unknown' || malo "formas mezcladas es unknown: $out"

caso "dsh: bloque con UNA sola persona (falta el resto) => SI habla (M2/qwen r1)"
nuevo_dsh_reg
# Quitar las personas de verifier/reviewer/adversary (dejar solo implementer) —
# el checker debe hablar porque cada rol exige su persona:
#   `persona: |-` sobre el bloque entero dejaba pasar esto con 4 roles.
# 18.19: el sed original usaba direcciones relativas GNU (`,+2d`), que el sed
# de BSD rechaza — en macOS el sed fallaba, el yml quedaba con los 4 roles y
# el caso pasaba EN FALSO. awk borra cada linea `- id:` de esos roles mas las
# 2 siguientes, identico en GNU/BSD.
awk '/- id: subagent_(verifier|reviewer|adversary)/ {saltar=2; next}
     saltar > 0 {saltar--; next} {print}' \
  "$dsh_home/cordis.patch.yml" > "$dsh_home/cordis.patch.yml.saikit-new" \
  && mv "$dsh_home/cordis.patch.yml.saikit-new" "$dsh_home/cordis.patch.yml"
out="$(bash "$tool" --dsh-home "$dsh_home" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh con persona faltante: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'PATCH DE DSH' || malo "dsh con persona faltante deberia hablar: $out"

caso "dsh: rol duplicado => SI habla (M2/qwen r1)"
nuevo_dsh_reg
# Duplicar el bloque de implementer: el checker debe detectar >1 aparicion.
sed -n '/- id: subagent_implementer/,/- id: subagent_verifier/p' "$dsh_home/cordis.patch.yml" > "$tmp/dsh-dup-$n_dsh_reg.txt"
# 18.19: el sed original usaba `r` con `-i` sin sufijo (GNU-only); en BSD
# fallaba y el caso daba rojo por el instrumento, no por el checker. awk
# inserta el bloque copiado ANTES de la linea de verifier, identico en
# GNU/BSD.
awk -v dup="$tmp/dsh-dup-$n_dsh_reg.txt" \
  '/- id: subagent_verifier/ {while ((getline l < dup) > 0) print l; close(dup)}
   {print}' \
  "$dsh_home/cordis.patch.yml" > "$dsh_home/cordis.patch.yml.saikit-new" \
  && mv "$dsh_home/cordis.patch.yml.saikit-new" "$dsh_home/cordis.patch.yml"
out="$(bash "$tool" --dsh-home "$dsh_home" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh con rol duplicado: esperaba exit 0, dio $rc"
printf '%s' "$out" | grep -qi 'PATCH DE DSH' || malo "dsh con rol duplicado deberia hablar: $out"
rm -f "$tmp/dsh-dup-$n_dsh_reg.txt"

# ============================================== Task 16.5 — advisory del recetario
# El contrato del hook solo ofrece las recetas cuyo sha256 coincide con el
# manifiesto instalado; sin manifiesto (o con hash distinto) esa receta no
# aparece en el menu. El verificador lo REPORTa (fail-open: exit 0 SIEMPRE).
caso "recetario: sin manifiesto o con hash distinto => avisa y exit 0"
# Un settings en un dir propio (no $tmp, que ya tiene un recetario valido) para
# que el hookdir derivado (<dir>/hooks) no tenga recetas/.
inca_dir="$tmp/recetario-rutas"
mkdir -p "$inca_dir/hooks"
escribir_settings_completo "$inca_dir/settings.json"
if out_b="$(bash "$tool" --settings "$inca_dir/settings.json" 2>&1)"; then rc_b=0; else rc_b=$?; fi
[ "$rc_b" -eq 0 ] || malo "sin manifiesto: esperaba exit 0, dio $rc_b"
printf '%s' "$out_b" | grep -q 'recetario: ausente en' \
  || malo "sin manifiesto debe decir 'ausente en': $out_b"
printf '%s' "$out_b" | grep -qi 'hash distinto' \
  && malo "sin manifiesto NO debe decir 'hash distinto' (no se midio nada): $out_b"
# Ahora con manifiesto pero con hash FALSO para bug.md (el contrato no ofrecera
# esa receta).
mkdir -p "$inca_dir/hooks/recetas"
failsha="$(printf 'a%.0s' $(seq 1 64))"
printf '%s\treceta\tbug\tfull\tArreglar algo que no funciona\n' "$failsha" > "$inca_dir/hooks/recetas/MANIFEST.sha256"
: > "$inca_dir/hooks/recetas/bug.md"
if out_b="$(bash "$tool" --settings "$inca_dir/settings.json" 2>&1)"; then rc_b=0; else rc_b=$?; fi
[ "$rc_b" -eq 0 ] || malo "con hash distinto: esperaba exit 0, dio $rc_b"
printf '%s' "$out_b" | grep -q 'no ofrecera esa receta' \
  || malo "con hash distinto debe decir 'no ofrecera esa receta': $out_b"
# cross-review grok r4 #3: exigir SOLO 'no ofrecera esa receta' no discrimina —
# esa frase la lleva tambien el mensaje de ausente, y el archivo bug.md de este
# caso SI existe. Sin esta linea, una regresion que reportara "ausente" un
# archivo presente con hash distinto dejaba el caso verde.
printf '%s' "$out_b" | grep -q 'hash distinto' \
  || malo "con un archivo PRESENTE y hash distinto debe decir 'hash distinto', no 'ausente': $out_b"
printf '%s' "$out_b" | grep -q 'ausente en' \
  && malo "un archivo presente NO debe reportarse como ausente: $out_b"

# 16.5 (cross-review codex, P2): el hook valida `nombre` contra ^[a-z][a-z0-9-]*$,
# pero el checker NO lo hacia — un manifiesto manipulado podia hacerle hashear un
# .md FUERA de recetas/ (traversal). Se agrega el guard en reportar_recetario y
# este caso lo ata (advisory: exit 0 siempre; reporta la entrada insegura).
caso "recetario: un nombre inseguro del manifiesto NO se usa como ruta"
inseg_dir="$tmp/recetario-inseguro"
mkdir -p "$inseg_dir/hooks/recetas"
escribir_settings_completo "$inseg_dir/settings.json"
printf '%s\treceta\t../blanco\tfull\tTitulo ajeno\n' "aaaa" > "$inseg_dir/hooks/recetas/MANIFEST.sha256"
printf 'x\n' > "$inseg_dir/hooks/blanco.md"   # el archivo fuera de recetas/ que el checker NO debe leer
if out_i="$(bash "$tool" --settings "$inseg_dir/settings.json" 2>&1)"; then rc_i=0; else rc_i=$?; fi
[ "$rc_i" -eq 0 ] || malo "un nombre inseguro debe seguir exit 0 (advisory), dio $rc_i: $out_i"
printf '%s' "$out_i" | grep -q 'entrada insegura' \
  || malo "debe reportar 'entrada insegura' para el nombre ../blanco: $out_i"
printf '%s' "$out_i" | grep -q 'blanco.md' \
  && malo "no debe hashear un .md fuera de recetas/ (uso ../blanco como ruta): $out_i"

# 16.5 (cross-review, hilo sha256sum): si el binario de hash NO esta disponible
# (host con solo `shasum`, o ninguno), el checker debe salir `unknown` y NUNCA
# acusar "hash distinto" — eso seria la alarma falsa que el contrato prohibe.
# SAIKIT_SHA_BIN fuerza la falta de binario (costura de test documentada en el
# tool). El OLD code usaba `sha256sum` a pelo y acusaba integridad rota.
caso "recetario: sin binario de hash disponible => unknown, NO integridad rota"
shbo_dir="$tmp/recetario-sin-binario"
mkdir -p "$shbo_dir/hooks/recetas"
escribir_settings_completo "$shbo_dir/settings.json"
# El fixture necesita un hash VALIDO; la costura del test fuerza la falta de
# binario SOLO en la invocacion del checker, no en la preparacion. Se usa el
# mismo fallback sha256sum->shasum que el propio tool, para no depender de que
# sha256sum exista en el host (cross-review codex-16.5-r2, hallazgo 5).
if command -v sha256sum >/dev/null 2>&1; then realsha="$(sha256sum "$repo/recetas/bug.md" | cut -d' ' -f1)"
else realsha="$(shasum -a 256 "$repo/recetas/bug.md" | cut -d' ' -f1)"; fi
printf '%s\treceta\tbug\tfull\tArreglar algo que no funciona\n' "$realsha" > "$shbo_dir/hooks/recetas/MANIFEST.sha256"
cp "$repo/recetas/bug.md" "$shbo_dir/hooks/recetas/bug.md"
if out_sh="$(SAIKIT_SHA_BIN='__no_such_hash_bin__' bash "$tool" --settings "$shbo_dir/settings.json" 2>&1)"; then rc_sh=0; else rc_sh=$?; fi
[ "$rc_sh" -eq 0 ] || malo "sin binario de hash: esperaba exit 0 (advisory), dio $rc_sh: $out_sh"
printf '%s' "$out_sh" | grep -q 'unknown' \
  || malo "sin binario de hash debe decir 'unknown': $out_sh"
printf '%s' "$out_sh" | grep -qi 'hash distinto\|ausente o con hash' \
  && malo "sin binario de hash NO debe acusar integridad rota: $out_sh"

if [ "$fail" -ne 0 ]; then
  echo "test_hook_registration: FAIL" >&2
  exit 1
fi
echo "test_hook_registration: OK"
