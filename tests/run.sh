#!/usr/bin/env bash
# Runner de tests del repo (Task 1.1).
#
#   1) Gate de sintaxis: `bash -n` sobre todo *.sh del arbol — el hook incluido
#      cuando exista (la Phase 2 lo trae a `hooks/`). Un hook que no parsea
#      rompe TODOS los turnos siguientes, no solo el propio: por eso este gate
#      corre siempre, aunque no haya un solo test.
#   2) Cada `tests/test_*.sh` en su propio proceso, con HOME y temporal
#      redirigidos a un directorio por test (Core Rule 4).
#   3) Guardia de fuga: el arbol del repo tiene que quedar identico despues de
#      cada test. Un test que escribe adentro del repo se reporta y rompe la
#      corrida, aunque el test en si haya pasado.
#
# Sale 0 solo si el gate y todos los tests pasan. Con el repo vacio de logica
# (sin hook y sin tests) sale 0.
#
# Uso: run.sh [repo_root]
# El argumento existe para que el propio runner sea testeable contra repos
# sinteticos (ver tests/test_runner_guards.sh); por defecto es el repo que lo
# contiene. Las libs se resuelven siempre junto a ESTE archivo, no a la raiz
# recibida.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -ge 1 ] && [ -n "$1" ]; then
  repo_root="$(cd "$1" && pwd)" || exit 1
else
  repo_root="$(cd "$script_dir/.." && pwd)"
fi
fail=0

# Huella del arbol: rutas + checksum. Detecta creado, borrado y modificado.
manifiesto() {
  ( cd "$1" 2>/dev/null || return 0
    find . -path './.git' -prune -o -type f -print0 2>/dev/null \
      | sort -z | xargs -0 -r cksum 2>/dev/null )
}

if ! bash "$script_dir/lib/check_syntax.sh" "$repo_root"; then
  fail=1
fi

run_root="$(mktemp -d "${TMPDIR:-/tmp}/saikit-run-XXXXXX")"
trap 'rm -rf "$run_root"' EXIT

shopt -s nullglob
for t in "$repo_root"/tests/test_*.sh; do
  nombre="$(basename "$t" .sh)"
  caja="$run_root/$nombre"
  mkdir -p "$caja/home/.claude/hooks/state" "$caja/tmp"
  if command -v cygpath >/dev/null 2>&1; then
    caja_userprofile="$(cygpath -w "$caja/home")"
  else
    caja_userprofile="$caja/home"
  fi

  antes="$(manifiesto "$repo_root")"
  if env HOME="$caja/home" USERPROFILE="$caja_userprofile" \
         TMPDIR="$caja/tmp" TMP="$caja/tmp" TEMP="$caja/tmp" \
         bash "$t"; then
    echo "PASS: $nombre"
  else
    echo "FAIL: $nombre" >&2
    fail=1
  fi
  despues="$(manifiesto "$repo_root")"

  if [ "$antes" != "$despues" ]; then
    echo "LEAK: $nombre escribio dentro del repo (Core Rule 4)" >&2
    diff <(printf '%s\n' "$antes") <(printf '%s\n' "$despues") >&2 || true
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "tests/run.sh: FAIL" >&2
  exit 1
fi
echo "tests/run.sh: OK"
