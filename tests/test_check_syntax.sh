#!/usr/bin/env bash
# El gate de sintaxis pasa con un script valido y falla con uno roto.
# Corre contra un sandbox propio: nunca toca el repo ni el perfil vivo.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

arbol="$SANDBOX/arbol"
mkdir -p "$arbol"

caso "solo scripts validos => exit 0"
printf 'echo ok\n' > "$arbol/good.sh"
if ! out="$(bash "$here/lib/check_syntax.sh" "$arbol" 2>&1)"; then
  malo "esperaba exit 0 con solo good.sh: $out"
fi

caso "un script que no parsea => exit != 0 y lo nombra"
printf 'if then fi (\n' > "$arbol/bad.sh"
if out="$(bash "$here/lib/check_syntax.sh" "$arbol" 2>&1)"; then
  malo "esperaba exit != 0 con bad.sh presente"
fi
printf '%s' "$out" | grep -q 'bad.sh' || malo "no nombra el archivo culpable: $out"

caso "arbol sin ningun *.sh => exit 0 (repo vacio de logica)"
rm -rf "$arbol"
mkdir -p "$arbol"
if ! bash "$here/lib/check_syntax.sh" "$arbol" >/dev/null 2>&1; then
  malo "un arbol sin scripts no es un fallo"
fi

if [ "$fail" -ne 0 ]; then
  echo "test_check_syntax: FAIL" >&2
  exit 1
fi
echo "test_check_syntax: OK"
