#!/usr/bin/env bash
# decision-blast driver — real saikit-decision.sh and saikit-blast.sh on a
# private fixture repo. Does not claim agents write these artifacts.
# Does not replay the race/lock battery of the unit tests.
set -euo pipefail
driver_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_root="$(cd "$driver_dir/../.." && pwd)"
# shellcheck source=../lib/runtime.sh
. "$skill_root/scripts/lib/runtime.sh"
# shellcheck source=../lib/driver.sh
. "$skill_root/scripts/lib/driver.sh"

: "${VERIFY_HOME:?}" "${VERIFY_REPO:?}" "${VERIFY_TMPDIR:?}"
: "${SAIKIT_FM_ATTEMPT_DIR:?}"

DECISION="$VERIFY_REPO/tools/saikit-decision.sh"
BLAST="$VERIFY_REPO/tools/saikit-blast.sh"

make_fixture() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  git -c init.defaultBranch=master init -q "$dest"
  git -C "$dest" \
    -c user.email='t@example.invalid' -c user.name='t' \
    -c commit.gpgsign=false \
    commit -q --allow-empty -m 'fixture 19.13'
}

form_token() {
  local cola36='FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE'
  local cola16='FAKEFAKEFAKEFAKE'
  case "$1" in
    ghp_)        printf 'ghp_%s' "$cola36" ;;
    github_pat_) printf 'github_pat_%s' "$cola36" ;;
    gho_)        printf 'gho_%s' "$cola36" ;;
    sk-)         printf 'sk-proj-%s' "$cola36" ;;
    AKIA)        printf 'AKIA%s' "$cola16" ;;
    *)           printf '' ;;
  esac
}

run_decision() {
  runtime_exec "$1" bash "$DECISION" "${@:2}"
}

run_blast() {
  runtime_exec "$1" bash "$BLAST" "${@:2}"
}

if fm_only decision-valid; then
  fx="$VERIFY_TMPDIR/fx-decision-valid"
  make_fixture "$fx"
  set +e
  out="$(run_decision "$fx" --append --task fm1913v --etapa Diseno \
    --decision "Usar fixture privado" --por-que "aislamiento del checkout" \
    --evidencia "drive 19.13" --resultado ok 2>&1)"
  rc=$?
  set -e
  fm_action decision-valid act-append "$rc" "$out" bash "$DECISION" --append --task fm1913v
  tsv="$fx/.saikit/decisiones/fm1913v.tsv"
  if [ "$rc" -eq 0 ] && [ -f "$tsv" ] && grep -qF "Usar fixture privado" "$tsv"; then
    fm_pass decision-valid trail_written "fm1913v tsv" "$tsv"
  else
    fm_fail decision-valid trail_written "fm1913v tsv" "rc=$rc out=$out tsv=$tsv"
  fi
  hdr="$(head -n 1 "$tsv" 2>/dev/null || true)"
  if [ -f "$tsv" ] && [ "$hdr" = 'cuando|etapa|decision|por_que|evidencia|resultado' ]; then
    fm_pass decision-valid header_ok "cuando|etapa|decision" "$hdr"
  else
    fm_fail decision-valid header_ok "cuando|etapa|decision" \
      "$(head -n 1 "$tsv" 2>/dev/null || true)"
  fi
  set +e
  chk="$(run_decision "$fx" --check --task fm1913v 2>&1)"
  chk_rc=$?
  set -e
  fm_action decision-valid act-check "$chk_rc" "$chk" bash "$DECISION" --check --task fm1913v
  if [ "$chk_rc" -eq 0 ]; then
    fm_pass decision-valid check_ok "exit 0" "check exit 0"
  else
    fm_fail decision-valid check_ok "exit 0" "check rc=$chk_rc $chk"
  fi
fi

if fm_only decision-reject; then
  fx="$VERIFY_TMPDIR/fx-decision-reject"
  make_fixture "$fx"
  mkdir -p "$fx/.saikit/decisiones"
  mal="$fx/.saikit/decisiones/mal.tsv"
  printf 'cuando|etapa|decision|por_que|evidencia|resultado\n' > "$mal"
  printf 'a|b|c\n' >> "$mal"
  cp "$mal" "$fx/mal.bak"
  set +e
  out="$(run_decision "$fx" --append --task mal --etapa X --decision D \
    --por-que P --evidencia E --resultado ok 2>&1)"
  rc=$?
  set -e
  fm_action decision-reject act-reject "$rc" "$out" bash "$DECISION" --append --task mal
  # assert:reject_exit_2
  if [ "$rc" -eq 2 ]; then
    fm_pass decision-reject reject_exit_2 "exit 2" "rc=2"
  else
    fm_fail decision-reject reject_exit_2 "exit 2" "rc=$rc $out"
  fi
  # assert:reject_exit_2_end
  if printf '%s' "$out" | grep -q 'TSV malformado' \
    && printf '%s' "$out" | grep -q 'linea 2'; then
    fm_pass decision-reject reject_reason "malformado linea 2" \
      "TSV malformado linea 2"
  else
    fm_fail decision-reject reject_reason "malformado linea 2" "$out"
  fi
  if cmp -s "$mal" "$fx/mal.bak"; then
    fm_pass decision-reject file_untouched "untouched" "file untouched identic"
  else
    fm_fail decision-reject file_untouched "untouched" "file modified"
  fi
fi

if fm_only blast-valid; then
  fx="$VERIFY_TMPDIR/fx-blast-valid"
  make_fixture "$fx"
  set +e
  out="$(run_blast "$fx" --write --task fm1913b \
    --hecho "el cambio mantiene los registros" \
    --comando "true" --salida "ok" --nivel 4 2>&1)"
  rc=$?
  set -e
  fm_action blast-valid act-write "$rc" "$out" bash "$BLAST" --write --task fm1913b
  bf="$fx/.saikit/findings/blast-fm1913b.json"
  if [ "$rc" -eq 0 ] && [ -f "$bf" ]; then
    fm_pass blast-valid blast_written "findings/blast-fm1913b.json" "$bf"
  else
    fm_fail blast-valid blast_written "findings/blast-fm1913b.json" \
      "rc=$rc out=$out"
  fi
  if [ -f "$bf" ] \
    && grep -Fq '"hecho"' "$bf" \
    && grep -Fq '"comando"' "$bf" \
    && grep -Fq '"salida"' "$bf" \
    && grep -Fq '"nivel"' "$bf"; then
    fm_pass blast-valid schema_keys '"hecho"|"comando"|"salida"|"nivel"' \
      "$(cat "$bf")"
  else
    fm_fail blast-valid schema_keys '"hecho"|"comando"|"salida"|"nivel"' \
      "$(cat "$bf" 2>/dev/null || true)"
  fi
  if [ -f "$bf" ] && grep -Fq '"nivel":4' "$bf"; then
    fm_pass blast-valid nivel_4 '"nivel":4' "$(cat "$bf")"
  else
    fm_fail blast-valid nivel_4 '"nivel":4' "$(cat "$bf" 2>/dev/null || true)"
  fi
fi

if fm_only blast-reject; then
  fx="$VERIFY_TMPDIR/fx-blast-reject"
  make_fixture "$fx"
  set +e
  lvl_out="$(run_blast "$fx" --write --task fm1913lvl \
    --hecho "hecho" --comando "cmd" --salida "s" --nivel 6 2>&1)"
  lvl_rc=$?
  set -e
  fm_action blast-reject act-level "$lvl_rc" "$lvl_out" bash "$BLAST" --write --task fm1913lvl --nivel 6
  # assert:level_exit_2
  if [ "$lvl_rc" -eq 2 ]; then
    fm_pass blast-reject level_exit_2 "exit 2" "rc=2"
  else
    fm_fail blast-reject level_exit_2 "exit 2" "rc=$lvl_rc $lvl_out"
  fi
  # assert:level_exit_2_end
  if [ ! -e "$fx/.saikit/findings/blast-fm1913lvl.json" ]; then
    fm_pass blast-reject level_no_file "not created" "no file ausente"
  else
    fm_fail blast-reject level_no_file "not created" "file created"
  fi

  set +e
  ok_out="$(run_blast "$fx" --write --task fm1913cmd \
    --hecho "el cambio mantiene los registros" \
    --comando "true" --salida "ok" --nivel 4 2>&1)"
  ok_rc=$?
  set -e
  cmdf="$fx/.saikit/findings/blast-fm1913cmd.json"
  if [ "$ok_rc" -ne 0 ] || [ ! -f "$cmdf" ]; then
    fm_fail blast-reject command_exit_2 "exit 2" "setup write failed rc=$ok_rc $ok_out"
    fm_fail blast-reject command_untouched "untouched" "setup write failed"
  else
    prev="$(cat "$cmdf")"
    set +e
    cmd_out="$(run_blast "$fx" --write --task fm1913cmd \
      --hecho "hecho" --salida "ok" --nivel 4 2>&1)"
    cmd_rc=$?
    set -e
    fm_action blast-reject act-command "$cmd_rc" "$cmd_out" \
      bash "$BLAST" --write --task fm1913cmd --nivel 4
    # assert:command_exit_2
    if [ "$cmd_rc" -eq 2 ]; then
      fm_pass blast-reject command_exit_2 "exit 2" "rc=2"
    else
      fm_fail blast-reject command_exit_2 "exit 2" "rc=$cmd_rc $cmd_out"
    fi
    # assert:command_exit_2_end
    if [ "$(cat "$cmdf")" = "$prev" ]; then
      fm_pass blast-reject command_untouched "untouched" "file untouched identic"
    else
      fm_fail blast-reject command_untouched "untouched" "file modified"
    fi
  fi
fi

if fm_only redact; then
  fx="$VERIFY_TMPDIR/fx-redact"
  make_fixture "$fx"
  tok="$(form_token ghp_)"
  set +e
  d_out="$(run_decision "$fx" --append --task fm1913rd --etapa Diseno \
    --decision "usar el token $tok" --por-que "el por que trae $tok" \
    --evidencia "la evidencia trae $tok" --resultado ok 2>&1)"
  d_rc=$?
  set -e
  fm_action redact act-decision "$d_rc" "$d_out" bash "$DECISION" --append --task fm1913rd
  dtsv="$fx/.saikit/decisiones/fm1913rd.tsv"
  if [ "$d_rc" -eq 0 ] && [ -f "$dtsv" ] && grep -qF '[REDACTED]' "$dtsv"; then
    fm_pass redact decision_redacted "[REDACTED]" "[REDACTED] in trail"
  else
    fm_fail redact decision_redacted "[REDACTED]" "rc=$d_rc missing marker"
  fi
  # assert:decision_no_secret
  if [ -f "$dtsv" ] && ! grep -qF "$tok" "$dtsv" && ! grep -qF 'FAKEFAKEFAKE' "$dtsv"; then
    fm_pass redact decision_no_secret "sin secreto" "no token redact"
  else
    fm_fail redact decision_no_secret "sin secreto" "token leaked in trail"
  fi
  # assert:decision_no_secret_end

  set +e
  b_out="$(run_blast "$fx" --write --task fm1913rb \
    --hecho "hecho" --comando "true" --salida "ok token=$tok done" --nivel 4 2>&1)"
  b_rc=$?
  set -e
  fm_action redact act-blast "$b_rc" "$b_out" bash "$BLAST" --write --task fm1913rb
  bjson="$fx/.saikit/findings/blast-fm1913rb.json"
  if [ "$b_rc" -eq 0 ] && [ -f "$bjson" ] && grep -qF '[REDACTED]' "$bjson"; then
    fm_pass redact blast_redacted "[REDACTED]" "[REDACTED] in blast"
  else
    fm_fail redact blast_redacted "[REDACTED]" "rc=$b_rc missing marker"
  fi
  # assert:blast_no_secret
  if [ -f "$bjson" ] && ! grep -qF "$tok" "$bjson" && ! grep -qF 'FAKEFAKEFAKE' "$bjson"; then
    fm_pass redact blast_no_secret "sin secreto" "no token redact"
  else
    fm_fail redact blast_no_secret "sin secreto" "token leaked in blast"
  fi
  # assert:blast_no_secret_end
fi

if fm_only output-location; then
  fx="$VERIFY_TMPDIR/fx-location"
  make_fixture "$fx"
  set +e
  d_out="$(run_decision "$fx" --append --task fm1913loc --etapa Diseno \
    --decision "ubicacion" --por-que "fixture" --evidencia "path" --resultado ok 2>&1)"
  d_rc=$?
  b_out="$(run_blast "$fx" --write --task fm1913loc \
    --hecho "ubicacion" --comando "true" --salida "ok" --nivel 4 2>&1)"
  b_rc=$?
  set -e
  fm_action output-location act-decision "$d_rc" "$d_out" bash "$DECISION" --append --task fm1913loc
  fm_action output-location act-blast "$b_rc" "$b_out" bash "$BLAST" --write --task fm1913loc
  dtsv="$fx/.saikit/decisiones/fm1913loc.tsv"
  bjson="$fx/.saikit/findings/blast-fm1913loc.json"
  if [ -f "$dtsv" ]; then
    fm_pass output-location decision_in_fixture ".saikit/decisiones/" "$dtsv"
  else
    fm_fail output-location decision_in_fixture ".saikit/decisiones/" "missing $dtsv"
  fi
  if [ -f "$bjson" ]; then
    fm_pass output-location blast_in_fixture ".saikit/findings/" "$bjson"
  else
    fm_fail output-location blast_in_fixture ".saikit/findings/" "missing $bjson"
  fi
  # assert:not_on_checkout
  checkout_d="$VERIFY_REPO/.saikit/decisiones/fm1913loc.tsv"
  checkout_b="$VERIFY_REPO/.saikit/findings/blast-fm1913loc.json"
  if [ ! -e "$checkout_d" ] && [ ! -e "$checkout_b" ]; then
    fm_pass output-location not_on_checkout "ausente en checkout" \
      "checkout intact no checkout"
  else
    fm_fail output-location not_on_checkout "ausente en checkout" \
      "wrote onto checkout"
  fi
  # assert:not_on_checkout_end
fi

exit 0
