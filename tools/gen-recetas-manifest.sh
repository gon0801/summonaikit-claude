#!/usr/bin/env bash
# tools/gen-recetas-manifest.sh — Task 16.2 (D1). Escribe recetas/MANIFEST.sha256
# (TSV, LF, ordenado por nombre). Corre el linter ANTES de incluir un archivo:
# un frontmatter roto no entra al manifiesto (la validez se garantiza aqui, no
# en el hook). `--check` compara sin escribir (exit 1 si difiere).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; repo="$(cd "$here/.." && pwd)"
. "$repo/tests/lib/recetas_lint.sh"
dir="$repo/recetas"; out="$dir/MANIFEST.sha256"; modo="${1:-}"
tmp="$(mktemp "${TMPDIR:-/tmp}/saikit-manifest-XXXXXX")" || exit 5
rc=0
for f in "$dir"/*.md; do
  motivo="$(lint_receta "$f")" || { printf '[gen-recetas-manifest] %s: %s\n' "$(basename "$f")" "$motivo" >&2; rc=1; continue; }
  manifest_linea "$f" >> "$tmp"
done
[ "$rc" -eq 0 ] || { rm -f "$tmp"; exit 1; }
sort -t"$(printf '\t')" -k3,3 "$tmp" > "$tmp.sorted"
# nombres de receta deben ser unicos: una clave repetida hace ambiguo el mapeo
# por nombre del runtime (D1) y el orden de un sort con dupes depende del locale.
if ! dup="$(manifest_unicos "$tmp.sorted")"; then
  printf '[gen-recetas-manifest] %s\n' "$dup" >&2
  rm -f "$tmp" "$tmp.sorted"; exit 1
fi
if [ "$modo" = "--check" ]; then
  cmp -s "$tmp.sorted" "$out"; rc=$?; rm -f "$tmp" "$tmp.sorted"; exit $rc
fi
mv "$tmp.sorted" "$out"; rm -f "$tmp"; printf '[gen-recetas-manifest] %s lineas -> %s\n' "$(wc -l < "$out" | tr -d ' ')" "$out"
