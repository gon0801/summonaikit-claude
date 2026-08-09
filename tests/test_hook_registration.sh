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
tmp="$(mktemp -d)"
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

if [ "$fail" -ne 0 ]; then
  echo "test_hook_registration: FAIL" >&2
  exit 1
fi
echo "test_hook_registration: OK"
