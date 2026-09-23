#!/usr/bin/env bash
# 23.11(c) — poder discriminante del unknown del matcher en muse: sed sobre
# una copia, SAIKIT_REGISTRO_TOOL=<mutante>, el driver
# test_hook_registration.sh debe ir rojo.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init || exit 1

source_tool="$repo/tools/check-hook-registration.sh"
mutant="$SANDBOX/check-hook-registration.sh"
run_driver() { SAIKIT_REGISTRO_TOOL="$mutant" bash "$here/test_hook_registration.sh"; }

cp "$source_tool" "$mutant"
run_driver > "$SANDBOX/control.log" 2>&1 || { cat "$SANDBOX/control.log"; exit 1; }

fail=0
for mutation in \
  unknown_muse_vuelve_a_agent
do
  case "$mutation" in
    unknown_muse_vuelve_a_agent)
      sed "s/muse) _herr_matcher=\"'subagent_spawn' y 'subagent_wait'\"/muse) _herr_matcher=\"'Agent'\"/" \
        "$source_tool" > "$mutant"
      expected='el unknown muse debe nombrar subagent_spawn' ;;
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
printf 'test_hook_registration_mutations: OK (1 mutacion)\n'
