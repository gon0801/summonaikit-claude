#!/usr/bin/env bash
# tests/test_saikit_postmerge.sh - Task 18.5: tools/saikit-postmerge.sh
# (D19 REDUCIDA por la decision del 2026-08-30).
#
# QUE AFIRMA (DoD reescrita de la fila 18.5, columna 3 de Plans.md):
#   - Verde (CI success + salud ok o ausente) => mensaje VERDE, exit 0.
#   - Rojo (CI en failure o salud caida) => AVISA con el bloque PARA REVERTIR
#     listo para copiar, y el caso verifica que NO lo ejecuto MIRANDO EL
#     ARBOL (HEAD identico, worktree limpio igual, sin commit de revert) -
#     no una variable que dice que no (la trampa de la fila).
#   - Sin run aun => UNKNOWN (exit 3). CI pendiente => UNKNOWN (exit 3).
#   - merge_commit sin trailer Saikit-Merge: o que no es la punta de
#     origin/<rama> => el aviso lo dice y NO se ofrece revert (exit 2).
#   - telegram-send se invoca SOLO con telegram: true en la config.
#
# INFRAESTRUCTURA: git REAL en sandbox (origin bare local alcanzado via
# url.insteadOf), gh FALSO (solo `run list`), curl FALSO (codigo via env) y
# telegram-send FALSO (log a archivo). Sin acentos en este archivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
POST_REAL="$repo/tools/saikit-postmerge.sh"
POST="${SAIKIT_POSTMERGE_TOOL:-$POST_REAL}"

fail=0
CASO_ROJO=0
_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_contiene() { if ! printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: no contiene [$3]"; fi; }
_no_contiene() { if printf '%s' "$2" | grep -Fq -- "$3"; then _mal "$1: contiene [$3] y no deberia"; fi; }

SB=""
OUT=""
RC=0
MC=""

# ------------------------------------------------------------------ sandbox
# sb_reset [salud_url] [telegram]: monta work + origin bare + merge_commit con
# trailer como punta de origin/master + gh/curl/telegram falsos.
sb_reset() {
  local salud="${1:-}" tg="${2:-false}"
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-post-XXXXXX")" || exit 1
  git init --bare -q "$SB/origin.git"
  git clone -q "$SB/origin.git" "$SB/work" 2>/dev/null
  cd "$SB/work" || exit 1
  git symbolic-ref HEAD refs/heads/master
  git config user.email op@example.com
  git config user.name op
  git config "url.$SB/origin.git.insteadOf" "https://github.com/op/sandbox.git"
  git remote set-url origin "https://github.com/op/sandbox.git"

  if [ -n "$salud" ]; then
    salud_json="\"$salud\""
  else
    salud_json="null"
  fi
  mkdir -p .saikit
  printf '{"merge":true,"merge_despliega":"no","salud_url":%s,"revert_si_rojo":true,"rama":"master","sin_verify_app":false,"telegram":%s}\n' \
    "$salud_json" "$tg" > .saikit/autopilot.json
  printf 'base\n' > app.sh
  git add .saikit/autopilot.json app.sh
  git commit -qm "chore: base"
  git push -q origin master

  git checkout -qb feat/task
  printf 'task\n' >> app.sh
  git commit -qam "feat: task"
  SHA_FEAT="$(git rev-parse HEAD)"
  git checkout -q master
  git merge -q --squash feat/task
  git commit -qm "feat: task (#7)" -m "Saikit-Merge: $SHA_FEAT"
  git push -q origin master
  MC="$(git rev-parse HEAD)"

  mkdir -p "$SB/bin" "$SB/ghfix"
  cat > "$SB/bin/gh" <<'GHEOF'
#!/usr/bin/env bash
# gh falso del banco de la 18.5: solo `run list --commit`, argv al log.
set -u
[ -n "${SAIKIT_GH_LOG:-}" ] && printf 'gh %s\n' "$*" >> "$SAIKIT_GH_LOG"
fix="${SAIKIT_GH_FIX:?}"
case "$1 $2" in
  "run list") cat "$fix/runs.json"; exit 0 ;;
esac
printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
exit 1
GHEOF
  chmod +x "$SB/bin/gh"
  cat > "$SB/bin/curl" <<'CURLEOF'
#!/usr/bin/env bash
# curl falso: responde el codigo de SAIKIT_CURL_CODIGO, rc de SAIKIT_CURL_RC.
printf '%s' "${SAIKIT_CURL_CODIGO:-200}"
[ -n "${SAIKIT_CURL_LOG:-}" ] && printf 'curl %s\n' "$*" >> "$SAIKIT_CURL_LOG"
exit "${SAIKIT_CURL_RC:-0}"
CURLEOF
  chmod +x "$SB/bin/curl"
  cat > "$SB/bin/telegram-send" <<'TGEOF'
#!/usr/bin/env bash
# telegram-send falso: graba el mensaje al log; rc de SAIKIT_TG_RC.
printf '%s\n' "$*" >> "${SAIKIT_TG_LOG:?}"
exit "${SAIKIT_TG_RC:-0}"
TGEOF
  chmod +x "$SB/bin/telegram-send"
  export SAIKIT_GH_FIX="$SB/ghfix"
  export SAIKIT_GH_LOG="$SB/gh.log"
  : > "$SAIKIT_GH_LOG"
  export SAIKIT_CURL_LOG="$SB/curl.log"
  : > "$SAIKIT_CURL_LOG"
  export SAIKIT_TG_LOG="$SB/tg.log"
  : > "$SAIKIT_TG_LOG"
  export SAIKIT_CURL_CODIGO=200 SAIKIT_CURL_RC=0 SAIKIT_TG_RC=0
  export SAIKIT_POSTMERGE_TIMEOUT_SEG=0 SAIKIT_POSTMERGE_SALUD_SEG=2
  unset SAIKIT_CURL_BIN SAIKIT_TELEGRAM_BIN
  export PATH="$SB/bin:$PATH"
  printf '[{"event":"push","status":"completed","conclusion":"success","workflow":"ci"}]' > "$SB/ghfix/runs.json"
}

caso() { printf '  caso: %s\n' "$1"; CASO_ROJO=0; sb_reset; }
fin_caso() {
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    ROJO: %s\n' "$1" >&2
    fail=1
  else
    printf '    ok: %s\n' "$1"
  fi
}

correr() {  # corre el script bajo prueba desde el work del sandbox
  OUT="$(bash "$POST" --merge-commit "$MC" --rama master "$@" 2>&1)"
  RC=$?
}

# Huella del arbol: HEAD + estado del worktree. La DoD exige probar el
# no-revert MIRANDO ESTO, no una variable del script.
arbol_huella() {
  git rev-parse HEAD
  git status --porcelain
  git log --oneline -3
}

caso "verde_sin_salud_mensaje_y_cero"
{
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "dice VERDE" "$OUT" "VERDE:"
  _no_contiene "no ofrece revert en verde" "$OUT" "PARA REVERTIR"
  [ ! -s "$SAIKIT_TG_LOG" ] || _mal "con telegram:false invoco telegram-send"
}
fin_caso "verde_sin_salud_mensaje_y_cero"

caso "ci_rojo_avisa_con_comando_y_el_arbol_queda_intacto"
{
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  antes="$(arbol_huella)"
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "dice ROJO" "$OUT" "ROJO:"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
  _contiene "el comando nombra el merge_commit" "$OUT" "$MC"
  _contiene "el comando usa la via del merge" "$OUT" "--revert-de $MC"
  # La trampa de la fila: el no-revert se prueba en el arbol.
  despues="$(arbol_huella)"
  [ "$antes" = "$despues" ] || _mal "el arbol cambio pese a que solo debia avisar"
  if git log --oneline -3 | grep -q -i 'revert'; then
    _mal "aparecio un commit de revert: el script lo ejecuto"
  fi
}
fin_caso "ci_rojo_avisa_con_comando_y_el_arbol_queda_intacto"

caso "salud_caida_avisa_y_el_arbol_queda_intacto"
{
  CASO_ROJO=0; sb_reset "https://api.example.com/salud" false
  export SAIKIT_CURL_CODIGO=500
  antes="$(arbol_huella)"
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "dice ROJO" "$OUT" "ROJO:"
  _contiene "nombra la salud" "$OUT" "salud"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
  despues="$(arbol_huella)"
  [ "$antes" = "$despues" ] || _mal "el arbol cambio pese a que solo debia avisar"
  [ -s "$SAIKIT_CURL_LOG" ] || _mal "no consulto la salud_url de la config"
}
fin_caso "salud_caida_avisa_y_el_arbol_queda_intacto"

caso "sin_run_aun_unknown"
{
  printf '[]' > "$SB/ghfix/runs.json"
  correr
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
  _contiene "dice UNKNOWN" "$OUT" "UNKNOWN:"
  _contiene "dice sin run" "$OUT" "sin run"
  _no_contiene "no ofrece revert sin run" "$OUT" "PARA REVERTIR"
}
fin_caso "sin_run_aun_unknown"

caso "ci_pendiente_unknown"
{
  printf '[{"event":"push","status":"in_progress","conclusion":null,"workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr
  [ "$RC" -eq 3 ] || _mal "rc esperaba 3, dio $RC: $OUT"
  _contiene "dice UNKNOWN" "$OUT" "UNKNOWN:"
  _contiene "dice pendiente" "$OUT" "pendiente"
}
fin_caso "ci_pendiente_unknown"

caso "sin_trailer_no_ofrece_revert"
{
  # Un commit normal como punta: sin el trailer que solo pone
  # saikit-merge.sh, no es un merge del autopilot.
  printf 'extra\n' >> app.sh
  git commit -qam "chore: directo a master"
  git push -q origin master
  MC="$(git rev-parse HEAD)"
  correr
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "nombra el trailer" "$OUT" "Saikit-Merge:"
  _no_contiene "no ofrece revert" "$OUT" "PARA REVERTIR"
}
fin_caso "sin_trailer_no_ofrece_revert"

caso "no_es_la_punta_no_ofrece_revert"
{
  # Algo aterrizo despues del merge: revertir a ciegas desharia lo ajeno.
  git checkout -q -b feat/otra master
  printf 'otra\n' >> app.sh
  git commit -qam "feat: otra"
  git checkout -q master
  git merge -q --no-ff feat/otra -m "merge otra"
  git push -q origin master
  [ "$(git rev-parse HEAD)" != "$MC" ] || _mal "precondicion: el MC deberia haber dejado de ser la punta"
  correr
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "nombra la punta" "$OUT" "punta"
  _no_contiene "no ofrece revert" "$OUT" "PARA REVERTIR"
}
fin_caso "no_es_la_punta_no_ofrece_revert"

caso "telegram_true_invoca_con_el_mensaje"
{
  CASO_ROJO=0; sb_reset "" true
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ -s "$SAIKIT_TG_LOG" ] || _mal "con telegram:true no invoco telegram-send"
  _contiene "telegram lleva el veredicto" "$(cat "$SAIKIT_TG_LOG")" "VERDE"
}
fin_caso "telegram_true_invoca_con_el_mensaje"

caso "flag_sin_valor_sale_2_no_gira (cross-review kimi)"
{
  OUT="$(timeout 5 bash "$POST" --merge-commit 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _contiene "exige el valor" "$OUT" "exige un valor"
}
fin_caso "flag_sin_valor_sale_2_no_gira (cross-review kimi)"

caso "sha_corto_se_normaliza_a_completo (cross-review grok)"
{
  corto="$(git rev-parse --short HEAD)"
  [ "$corto" != "$MC" ] || _mal "precondicion: el corto deberia diferir del completo"
  OUT="$(bash "$POST" --merge-commit "$corto" --rama master 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "dice VERDE" "$OUT" "VERDE:"
  _no_contiene "sin falso no-es-punta" "$OUT" "ya no es la punta"
}
fin_caso "sha_corto_se_normaliza_a_completo (cross-review grok)"

caso "sin_rama_se_deriva_de_origin_contains (cross-review grok)"
{
  # El uso desarmado tipico corre desde la rama del PR: sin --rama el script
  # deriva la base de las ramas remotas que contienen al commit.
  git checkout -q -b feat/otra 2>/dev/null
  OUT="$(bash "$POST" --merge-commit "$MC" 2>&1)"
  RC=$?
  git checkout -q master
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "derivo la base" "$OUT" "origin/master"
}
fin_caso "sin_rama_se_deriva_de_origin_contains (cross-review grok)"

caso "rojo_con_pendiente_avisa_rojo_igual (cross-review grok, alta)"
{
  # Un failure concluido con otro run aun corriendo: el veredicto es ROJO,
  # no UNKNOWN. Antes el pendiente tapaba el rojo y no salia PARA REVERTIR.
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"quality"},{"event":"push","status":"in_progress","conclusion":null,"workflow":"suite"}]' > "$SB/ghfix/runs.json"
  antes="$(arbol_huella)"
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "dice ROJO" "$OUT" "ROJO:"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
  _contiene "menciona lo pendiente" "$OUT" "pendiente"
  despues="$(arbol_huella)"
  [ "$antes" = "$despues" ] || _mal "el arbol cambio pese a que solo debia avisar"
}
fin_caso "rojo_con_pendiente_avisa_rojo_igual (cross-review grok, alta)"

caso "rojo_sin_curl_avisa_igual_con_salud_no_observable (cross-review kimi)"
{
  CASO_ROJO=0; sb_reset "https://api.example.com/salud" false
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  export SAIKIT_CURL_BIN=curl-que-no-existe
  correr
  unset SAIKIT_CURL_BIN
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "dice ROJO" "$OUT" "ROJO:"
  _contiene "declara la salud no observable" "$OUT" "no observable"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
}
fin_caso "rojo_sin_curl_avisa_igual_con_salud_no_observable (cross-review kimi)"

caso "gh_se_llama_con_limite_alto (cross-review kimi)"
{
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "pide mas que el default 20" "$(cat "$SAIKIT_GH_LOG")" "--limit 100"
}
fin_caso "gh_se_llama_con_limite_alto (cross-review kimi)"

caso "secreto_en_salud_sale_redactado_en_stdout_y_telegram (cross-review kimi+grok)"
{
  CASO_ROJO=0; sb_reset "https://usr:clave-ejemplo@example.com/salud" true
  export SAIKIT_CURL_CODIGO=500
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "stdout redacta" "$OUT" "[REDACTED]"
  _no_contiene "stdout sin el secreto" "$OUT" "clave-ejemplo"
  [ -s "$SAIKIT_TG_LOG" ] || _mal "con telegram:true no invoco telegram-send"
  _contiene "telegram redacta" "$(cat "$SAIKIT_TG_LOG")" "[REDACTED]"
  _no_contiene "telegram sin el secreto" "$(cat "$SAIKIT_TG_LOG")" "clave-ejemplo"
}
fin_caso "secreto_en_salud_sale_redactado_en_stdout_y_telegram (cross-review kimi+grok)"

caso "telegram_sin_cli_declara_pendiente_a_mano (cross-review grok)"
{
  CASO_ROJO=0; sb_reset "" true
  export SAIKIT_TELEGRAM_BIN=tg-que-no-existe
  correr
  unset SAIKIT_TELEGRAM_BIN
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _contiene "declara pendiente a mano" "$OUT" "pendiente a mano"
}
fin_caso "telegram_sin_cli_declara_pendiente_a_mano (cross-review grok)"

caso "mensaje_rojo_cabe_en_4096_y_va_redactado"
{
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  nchars="$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
  [ "$nchars" -le 4096 ] || _mal "el aviso pasa de 4096 chars ($nchars)"
}
fin_caso "mensaje_rojo_cabe_en_4096_y_va_redactado"

# ------------------------------------------------------- mutation-test propio
mut_sed() {  # $1=sed-expr, deja el mutado en $MUTADO con HERE al tools/ real
  MUTADO="$SB-mutado-$$.sh"
  { sed "$1" "$POST_REAL"; } | sed "s|^HERE=.*$|HERE=$repo/tools|" > "$MUTADO"
}

correr_mutacion() {  # $1=nombre, $2=sed-expr, $3=funcion de caso
  local nombre="$1" expr="$2" fun="$3"
  mut_sed "$expr"
  if cmp -s "$POST_REAL" "$MUTADO"; then
    printf '    FAIL: mutacion %s no cambio nada - el sed quedo obsoleto\n' "$nombre" >&2
    fail=1
    return
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    printf '    FAIL: mutacion %s no parsea; asi no prueba nada\n' "$nombre" >&2
    fail=1
    return
  fi
  POST="$MUTADO"
  CASO_ROJO=0
  "$fun"
  if [ "$CASO_ROJO" -ne 0 ]; then
    printf '    mutacion %s atrapada por %s\n' "$nombre" "$fun"
  else
    printf '    FAIL: ningun caso detecto la mutacion [%s]\n' "$nombre" >&2
    fail=1
  fi
  POST="${SAIKIT_POSTMERGE_TOOL:-$POST_REAL}"
  rm -f "$MUTADO"
}

c_sin_trailer() {
  CASO_ROJO=0; sb_reset
  printf 'extra\n' >> app.sh
  git commit -qam "chore: directo a master"
  git push -q origin master
  MC="$(git rev-parse HEAD)"
  correr
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _no_contiene "no ofrece revert" "$OUT" "PARA REVERTIR"
}

c_no_punta() {
  CASO_ROJO=0; sb_reset
  git checkout -q -b feat/otra master
  printf 'otra\n' >> app.sh
  git commit -qam "feat: otra"
  git checkout -q master
  git merge -q --no-ff feat/otra -m "merge otra"
  git push -q origin master
  correr
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
  _no_contiene "no ofrece revert" "$OUT" "PARA REVERTIR"
}

c_telegram_off() {
  CASO_ROJO=0; sb_reset
  correr
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  [ ! -s "$SAIKIT_TG_LOG" ] || _mal "con telegram:false invoco telegram-send"
}

c_flag_post() {
  CASO_ROJO=0; sb_reset
  OUT="$(timeout 5 bash "$POST" --merge-commit 2>&1)"
  RC=$?
  [ "$RC" -eq 2 ] || _mal "rc esperaba 2, dio $RC: $OUT"
}

c_corto() {
  CASO_ROJO=0; sb_reset
  corto="$(git rev-parse --short HEAD)"
  OUT="$(bash "$POST" --merge-commit "$corto" --rama master 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] || _mal "rc esperaba 0, dio $RC: $OUT"
  _no_contiene "sin falso no-es-punta" "$OUT" "ya no es la punta"
}

c_mezcla() {
  CASO_ROJO=0; sb_reset
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"quality"},{"event":"push","status":"in_progress","conclusion":null,"workflow":"suite"}]' > "$SB/ghfix/runs.json"
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
}

c_rojo_sin_curl() {
  CASO_ROJO=0; sb_reset "https://api.example.com/salud" false
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' > "$SB/ghfix/runs.json"
  export SAIKIT_CURL_BIN=curl-que-no-existe
  correr
  unset SAIKIT_CURL_BIN
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _contiene "ofrece el comando listo" "$OUT" "PARA REVERTIR"
}

c_secreto() {
  CASO_ROJO=0; sb_reset "https://usr:clave-ejemplo@example.com/salud" true
  export SAIKIT_CURL_CODIGO=500
  correr
  [ "$RC" -eq 1 ] || _mal "rc esperaba 1, dio $RC: $OUT"
  _no_contiene "stdout sin el secreto" "$OUT" "clave-ejemplo"
  _no_contiene "telegram sin el secreto" "$(cat "$SAIKIT_TG_LOG")" "clave-ejemplo"
}

while IFS=$'\t' read -r nombre expr fun; do
  [ -n "$nombre" ] || continue
  correr_mutacion "$nombre" "$expr" "$fun"
done <<'MUTS'
trailer_no_se_exige	s|grep -Fq 'Saikit-Merge:'|true|	c_sin_trailer
punta_no_se_exige	s|\[ "\$PUNTA" = "\$MC" \]|true|	c_no_punta
telegram_sin_gate	s|if \[ "\$TG" = "true" \]; then|if true; then|	c_telegram_off
flag_sin_valor_pasa	s|if \[ \$# -lt 2 \]; then|if false; then|	c_flag_post
mc_sin_normalizar	s|MC="\$(git rev-parse "\$MC" 2>/dev/null)"|MC="$MC"|	c_corto
rojo_pierde_con_pendiente	s|if \[ -n "\$rojos" \]; then|if false; then|	c_mezcla
salud_traga_rojo	s|if \[ -n "\$ROJO_MOTIVO" \]; then|if false; then|	c_rojo_sin_curl
aviso_sin_redactar	s|texto="\$(redactar "\$texto")"|texto="$texto"|	c_secreto
telegram_sin_redactar	s|TG_MSG="\$(redactar "\$MENSAJE")"|TG_MSG="$MENSAJE"|	c_secreto
MUTS

if [ "$fail" -ne 0 ]; then
  echo "test_saikit_postmerge: FAIL" >&2
  exit 1
fi
echo "test_saikit_postmerge: OK"
