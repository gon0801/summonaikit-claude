#!/usr/bin/env bash
# 23.11(d) — poder discriminante del chequeo fuera-de-git: sed sobre una
# copia, SAIKIT_INSTALL_TOOL=<mutante>, el driver test_install_provenance.sh
# debe ir rojo.
set -u
# Sin git heredado: GIT_DIR/GIT_WORK_TREE (y las locales GIT_COMMON_DIR,
# GIT_INDEX_FILE, GIT_OBJECT_DIRECTORY) del llamador redirigirian los
# fixtures a OTRO repo; se limpian antes de crear fixtures o leer shas.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1

mkdir -p "$SANDBOX/repo"
for dir in tools hooks agents hosts recetas skills; do
  cp -R "$repo/$dir" "$SANDBOX/repo/$dir" || exit 1
done
# El driver juzga procedencia sobre el checkout que contiene al tool: la
# copia tiene que ser un repo git con ref origin/master, o los casos P1-P4
# fallarian por motivo ajeno a la mutacion.
( cd "$SANDBOX/repo" && git init -q   && git add -A   && git -c user.email=t@t -c user.name=t commit -qm base   && git update-ref refs/remotes/origin/master HEAD ) >/dev/null 2>&1 || exit 1
source_tool="$repo/tools/install-hook.sh"
mutant="$SANDBOX/repo/tools/install-hook.sh"
run_driver() { SAIKIT_INSTALL_TOOL="$mutant" bash "$here/test_install_provenance.sh"; }

cp "$source_tool" "$mutant"
run_driver > "$SANDBOX/control.log" 2>&1 || { cat "$SANDBOX/control.log"; exit 1; }

fail=0
for mutation in \
  chequeo_atiende_git_heredado
do
  case "$mutation" in
    chequeo_atiende_git_heredado)
      sed 's/env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY //' \
        "$source_tool" > "$mutant"
      expected='con GIT_DIR heredado no dio desconocida' ;;
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
printf 'test_install_provenance_mutations: OK (1 mutacion)\n'
