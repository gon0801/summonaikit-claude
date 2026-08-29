#!/usr/bin/env bash
# tools/gen-recetas-manifest.sh — Task 16.2 (D1). Escribe recetas/MANIFEST.sha256
# (TSV, LF, ordenado por nombre). Corre el linter ANTES de incluir un archivo:
# un frontmatter roto no entra al manifiesto (la validez se garantiza aqui, no
# en el hook). `--check` compara sin escribir (exit 1 si difiere o si el
# manifiesto no existe). `--dir <ruta>` apunta a un directorio de recetas
# distinto (default: el del repo) para poder probar "manifiesto ausente/stale"
# desde un sandbox sin tocar el repo.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; repo="$(cd "$here/.." && pwd)"
. "$repo/tests/lib/recetas_lint.sh"
dir="$repo/recetas"; modo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2 ;;
    --check) modo=--check; shift ;;
    *) shift ;;
  esac
done
out="$dir/MANIFEST.sha256"
tmp="$(mktemp "${TMPDIR:-/tmp}/saikit-manifest-XXXXXX")" || exit 5
rc=0
for f in "$dir"/*.md; do
  motivo="$(lint_receta "$f")" || { printf '[gen-recetas-manifest] %s: %s\n' "$(basename "$f")" "$motivo" >&2; rc=1; continue; }
  manifest_linea "$f" >> "$tmp"
done
[ "$rc" -eq 0 ] || { rm -f "$tmp"; exit 1; }
sort -t"$(printf '\t')" -k3,3 "$tmp" > "$tmp.sorted" || { rm -f "$tmp" "$tmp.sorted"; exit 5; }
# nombres de receta deben ser unicos: una clave repetida hace ambiguo el mapeo
# por nombre del runtime (D1) y el orden de un sort con dupes depende del locale.
if ! dup="$(manifest_unicos "$tmp.sorted")"; then
  printf '[gen-recetas-manifest] %s\n' "$dup" >&2
  rm -f "$tmp" "$tmp.sorted"; exit 1
fi
if [ "$modo" = "--check" ]; then
  # cmp devuelve 2 si $out no existe: se normaliza a 1 (difiere) para que el
  # llamador no confunda "no hay manifiesto" con "ok" (CodeRabbit, PR #97).
  if [ -f "$out" ] && cmp -s "$tmp.sorted" "$out"; then rc=0; else rc=1; fi
  rm -f "$tmp" "$tmp.sorted"; exit $rc
fi
mv "$tmp.sorted" "$out" || { rm -f "$tmp" "$tmp.sorted"; exit 5; }
rm -f "$tmp"; printf '[gen-recetas-manifest] %s lineas -> %s\n' "$(awk 'END{print NR}' "$out")" "$out"
