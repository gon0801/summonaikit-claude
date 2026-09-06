#!/usr/bin/env bash
# Corre `bash -n` sobre todo *.sh bajo el directorio dado.
# Uso: check_syntax.sh <root>
# Sale 0 si todos parsean; 1 si alguno falla o si `find` no pudo recorrer el arbol
# (un find roto no puede pasar como "todo verde" con cobertura parcial).
set -u -o pipefail

root="${1:?uso: check_syntax.sh <root>}"
fail=0

list="$(mktemp)"
trap 'rm -f "$list"' EXIT

if ! find "$root" -name '*.sh' \
  -not -path '*/.git/*' \
  -not -path '*/.claude/*' \
  -not -path '*/out/*' \
  -not -path '*/sandbox/*' \
  -not -path '*/node_modules/*' | sort > "$list"; then
  echo "check_syntax: find fallo recorriendo $root" >&2
  exit 1
fi

# Phase 19.1: el controlador de la skill no tiene extensión .sh; incluirlo
# explícitamente cuando exista en el checkout.
ctrl="$root/.cursor/skills/verify-summonaikit/scripts/control-summonaikit"
if [ -f "$ctrl" ]; then
  printf '%s\n' "$ctrl" >> "$list"
fi

while IFS= read -r f; do
  if ! bash -n "$f"; then
    echo "SYNTAX FAIL: $f" >&2
    fail=1
  fi
done < "$list"

exit "$fail"
