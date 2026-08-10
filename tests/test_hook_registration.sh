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

# Registro completo: las 3 fases que el hook necesita.
escribir_settings_completo() {
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

caso "el registro REAL, con env vars por delante y bash -c, sigue contando"
# Guardia contra el arreglo de arriba: la forma que usa el settings de verdad
# lleva asignaciones de entorno antes del programa y el hook adentro de un
# `bash -c '...'`. Si el arreglo la rompiera, el verificador gritaria en cada
# arranque sobre un registro que SI existe -- una alarma falsa perpetua.
escribir_settings_completo "$tmp/real.json"
out="$(bash "$tool" --settings "$tmp/real.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
[ -z "$out" ] || malo "el registro real dejo de contar como registro: $out"

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

if [ "$fail" -ne 0 ]; then
  echo "test_hook_registration: FAIL" >&2
  exit 1
fi
echo "test_hook_registration: OK"
