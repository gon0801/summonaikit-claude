#!/usr/bin/env bash
# Poder discriminante del driver de instalacion 18.12, sobre copias mutadas.
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
run_driver() { SAIKIT_INSTALL_TOOL="$mutant" bash "$here/test_trail_install.sh"; }
run_driver > "$SANDBOX/control.log" 2>&1 || { cat "$SANDBOX/control.log"; exit 1; }
fail=0
for mutation in quitar_padre omitir_codex omitir_dsh ignorar_error omitir_clasificacion; do
  case "$mutation" in
    quitar_padre)
      sed 's/\[ "$tools_enlace" -eq 0 \] \&\& \[ "$lib_enlace" -eq 0 \]/[ "$lib_enlace" -eq 0 ]/' "$source_tool" > "$mutant"
      expected='quitar borro o cambio el redactar externo' ;;
    omitir_codex)
      sed 's/codex|dsh) publicar_saikit_tools/dsh) publicar_saikit_tools/' "$source_tool" > "$mutant"
      expected='codex: falta o difiere saikit-decision.sh' ;;
    omitir_dsh)
      sed 's/codex|dsh) publicar_saikit_tools/codex) publicar_saikit_tools/' "$source_tool" > "$mutant"
      expected='dsh: falta o difiere saikit-decision.sh' ;;
    ignorar_error)
      sed 's/codex|dsh) publicar_saikit_tools || exit \$?/codex|dsh) publicar_saikit_tools || true/' "$source_tool" > "$mutant"
      expected='codex: declaro exito sin poder plantar tools' ;;
    omitir_clasificacion)
      sed '/^publicar_saikit_tools()/,/^}/s/DESCONOCIDO|NO_OBSERVABLE)/__nunca__)/' "$source_tool" > "$mutant"
      expected='codex: acepto tool enlace saikit-decision.sh' ;;
  esac
  if cmp -s "$source_tool" "$mutant" || ! bash -n "$mutant"; then
    printf 'FAIL: mutacion %s no aplico o no parsea\n' "$mutation"; fail=1; continue
  fi
  run_driver > "$SANDBOX/mutant.log" 2>&1; rc=$?
  if [ "$rc" -ne 1 ] || ! grep -Fq "$expected" "$SANDBOX/mutant.log"; then
    printf 'FAIL: %s no fue atrapada por su caso (exit=%s)\n' "$mutation" "$rc"
    cat "$SANDBOX/mutant.log"; fail=1
  else
    printf 'ATRAPADA %s: %s\n' "$mutation" "$expected"
  fi
done
[ "$fail" -eq 0 ] || exit 1
printf 'test_trail_install_mutations: OK (5 mutaciones)\n'
