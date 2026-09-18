#!/usr/bin/env bash
# Poder discriminante del instalador muse: sed sobre una copia,
# SAIKIT_INSTALL_TOOL=<mutante>, el driver test_install_muse.sh debe ir rojo.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1

mkdir -p "$SANDBOX/repo"
for dir in tools hooks agents hosts recetas skills; do
  cp -R "$repo/$dir" "$SANDBOX/repo/$dir" || exit 1
done
source_tool="$repo/tools/install-hook.sh"
mutant="$SANDBOX/repo/tools/install-hook.sh"
run_driver() { SAIKIT_INSTALL_TOOL="$mutant" bash "$here/test_install_muse.sh"; }

cp "$source_tool" "$mutant"
run_driver > "$SANDBOX/control.log" 2>&1 || { cat "$SANDBOX/control.log"; exit 1; }

fail=0
for mutation in omitir_muse_check_host ignorar_marcas omitir_comparacion_avisos omitir_target_muse; do
  case "$mutation" in
    omitir_muse_check_host)
      # La guarda de --check --host (no la lista de --host) debe nombrar muse.
      sed '/# saikit-23.3-muse-check-host/{n;s/ || \[ "$HOST" = "muse" \]//;}' \
        "$source_tool" > "$mutant"
      expected='--check --host muse salio' ;;
    ignorar_marcas)
      # Si las tres pruebas de marca se invierten, un Muse mudo instala.
      sed \
        -e 's/\[ ! -f "$marcas_cand\/SessionStart" \]/[ -f "$marcas_cand\/SessionStart" ]/' \
        -e 's/\[ ! -f "$marcas_cand\/UserPromptSubmit" \]/[ -f "$marcas_cand\/UserPromptSubmit" ]/' \
        -e 's/\[ ! -f "$marcas_cand\/Stop" \]/[ -f "$marcas_cand\/Stop" ]/' \
        "$source_tool" > "$mutant"
      expected='sin marcas debia rechazar' ;;
    omitir_comparacion_avisos)
      sed 's/if ! muse_detalle_subconjunto "$cand_det" "$cur_det" || \[ "$cand_m" -gt "$cur_m" \]; then/if false; then/' \
        "$source_tool" > "$mutant"
      expected='campo desconocido en PreToolUse nuestro debia rechazar' ;;
    omitir_target_muse)
      sed 's/SUMMONAIKIT_HOOK_TARGET=muse /SUMMONAIKIT_HOOK_TARGET=other /g' \
        "$source_tool" > "$mutant"
      expected='cada comando debe setear TARGET=muse' ;;
  esac
  if cmp -s "$source_tool" "$mutant" || ! bash -n "$mutant"; then
    printf 'FAIL: mutacion %s no aplico o no parsea\n' "$mutation"; fail=1; continue
  fi
  run_driver > "$SANDBOX/mutant.log" 2>&1; rc=$?
  if [ "$rc" -ne 1 ] || ! grep -Fq -- "$expected" "$SANDBOX/mutant.log"; then
    printf 'FAIL: %s no fue atrapada por su caso (exit=%s)\n' "$mutation" "$rc"
    cat "$SANDBOX/mutant.log"; fail=1
  else
    printf 'ATRAPADA %s: %s\n' "$mutation" "$expected"
  fi
done
[ "$fail" -eq 0 ] || exit 1
printf 'test_install_muse_mutations: OK (4 mutaciones)\n'
