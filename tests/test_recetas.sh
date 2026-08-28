#!/usr/bin/env bash
# tests/test_recetas.sh — Task 16.2: forma de las recetas + manifiesto candado.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
. "$here/lib/recetas_lint.sh"
fail=0; caso() { printf '  caso: %s\n' "$1"; }; malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

buena() {  # $1=ruta → escribe una receta valida minima
  cat > "$1" <<'EOF'
---
saikit_owned: summonaikit-claude
nombre: bug
titulo: Arreglar algo que no funciona
carril: full
cuando: ["no funciona", "da error"]
adversary: opcional
---
## Pasos
1. Reproducir.
## Qué le dices al usuario
Primero qué cambia para ti.
## Recibo
Understand: Receta: bug.
EOF
}

caso "receta valida => 0"
buena "$SANDBOX/ok.md"; lint_receta "$SANDBOX/ok.md" >/dev/null || malo "rechazo una receta valida"

caso "termino prohibido => 1 con motivo"
buena "$SANDBOX/p.md"; printf 'Usa Graphite para el stack.\n' >> "$SANDBOX/p.md"
out="$(lint_receta "$SANDBOX/p.md")" && malo "acepto 'Graphite'"; printf '%s' "$out" | grep -q prohibido || malo "motivo sin 'prohibido': $out"

caso "termino prohibido con otra caja => 1"
buena "$SANDBOX/pc.md"; printf 'Usa graphite en minusculas.\n' >> "$SANDBOX/pc.md"
lint_receta "$SANDBOX/pc.md" >/dev/null && malo "acepto 'graphite' en minusculas"

caso "termino prohibido Cursor => 1"
buena "$SANDBOX/pcu.md"; printf 'El Cursor me ayuda a editar.\n' >> "$SANDBOX/pcu.md"
lint_receta "$SANDBOX/pcu.md" >/dev/null && malo "acepto 'Cursor'"

caso "frontmatter sin linea de cierre => 1"
printf -- '---\nsaikit_owned: summonaikit-claude\nnombre: bug\ntitulo: Arreglar algo\ncarril: full\ncuando: ["x"]\nadversary: opcional\n## Pasos\n1. a\n## Qué le dices al usuario\nb\n## Recibo\nc\n' > "$SANDBOX/fsc.md"
lint_receta "$SANDBOX/fsc.md" >/dev/null && malo "acepto frontmatter sin '---' de cierre"

caso "titulo plegado o literal => 1"
buena "$SANDBOX/pg.md"; sed -i 's/^titulo: .*/titulo: >/' "$SANDBOX/pg.md"
lint_receta "$SANDBOX/pg.md" >/dev/null && malo "acepto titulo plegado (>)"

caso "titulo plegado con chomping => 1"
buena "$SANDBOX/pgc.md"; sed -i 's/^titulo: .*/titulo: >-/' "$SANDBOX/pgc.md"
lint_receta "$SANDBOX/pgc.md" >/dev/null && malo "acepto titulo plegado con chomping (>-)"

caso "link relativo con espacios resuelve"
mkdir -p "$SANDBOX/sub"; : > "$SANDBOX/sub/mi archivo.md"
buena "$SANDBOX/ly.md"; printf '[esto](sub/mi archivo.md)\n' >> "$SANDBOX/ly.md"
lint_receta "$SANDBOX/ly.md" >/dev/null || malo "rechazo un link relativo con espacios que existe"

caso "carril invalido => 1"
buena "$SANDBOX/c.md"; sed -i 's/^carril: full/carril: rapido/' "$SANDBOX/c.md"
lint_receta "$SANDBOX/c.md" >/dev/null && malo "acepto carril: rapido"

caso "mas de 80 lineas => 1"
buena "$SANDBOX/l.md"; yes 'relleno' | head -n 80 >> "$SANDBOX/l.md"
lint_receta "$SANDBOX/l.md" >/dev/null && malo "acepto 90 lineas"

caso "TAB en el titulo => 1"
buena "$SANDBOX/t.md"; sed -i "s/^titulo: .*/titulo: Con\ttab/" "$SANDBOX/t.md"
lint_receta "$SANDBOX/t.md" >/dev/null && malo "acepto TAB en el titulo"

caso "CRLF se tolera en lectura"
buena "$SANDBOX/crlf.md"; sed -i 's/$/\r/' "$SANDBOX/crlf.md"
lint_receta "$SANDBOX/crlf.md" >/dev/null || malo "rechazo una receta CRLF"

caso "manifest_linea: 5 campos TAB y el titulo de varias palabras entero"
buena "$SANDBOX/m.md"
linea="$(manifest_linea "$SANDBOX/m.md")"
[ "$(printf '%s' "$linea" | awk -F'\t' '{print NF}')" = 5 ] || malo "no son 5 campos: $linea"
[ "$(printf '%s' "$linea" | cut -f5)" = "Arreglar algo que no funciona" ] || malo "titulo partido: $linea"

caso "manifest_linea hashea normalizado a LF (receta CRLF => hash == sha de los bytes LF)"
buena "$SANDBOX/nl.md"; sed -i 's/$/\r/' "$SANDBOX/nl.md"
sha_lf="$(tr -d '\r' < "$SANDBOX/nl.md" | sha256sum | cut -c1-64)"
sha_man="$(manifest_linea "$SANDBOX/nl.md" | cut -f1)"
[ "$sha_man" = "$sha_lf" ] || malo "manifest_linea no normaliza a LF (esperado $sha_lf, got $sha_man)"

caso "manifest_unicos detecta nombres duplicados"
printf 'a\treceta\tbug\tfull\tT\nb\treceta\tbug\tfast\tT2\n' > "$SANDBOX/dup.tsv"
manifest_unicos "$SANDBOX/dup.tsv" >/dev/null && malo "acepto nombres duplicados"
printf 'a\treceta\tbug\tfull\tT\nb\treceta\tboceto\tfast\tT2\n' > "$SANDBOX/un.tsv"
manifest_unicos "$SANDBOX/un.tsv" >/dev/null || malo "rechazo nombres unicos"

caso "00-lider marcado tipo: receta => 1 (no tiene Pasos/Recibo)"
printf -- '---\nsaikit_owned: summonaikit-claude\ntipo: receta\nnombre: lider\ntitulo: Lider\ncarril: full\ncuando: ["x"]\nadversary: opcional\n---\n## Principios\n' > "$SANDBOX/lider-mal.md"
lint_receta "$SANDBOX/lider-mal.md" >/dev/null && malo "acepto un lider marcado receta sin secciones de receta"

# ---------------------------------------------------------- el repo real
caso "todas las recetas del repo pasan el linter"
for f in "$repo"/recetas/*.md; do
  out="$(lint_receta "$f")" || malo "$(basename "$f"): $out"
done
caso "el manifiesto esta al dia (gen --check)"
bash "$repo/tools/gen-recetas-manifest.sh" --check >/dev/null || malo "MANIFEST.sha256 desactualizado: corre tools/gen-recetas-manifest.sh"

[ "$fail" -eq 0 ] && echo "test_recetas: OK" || { echo "test_recetas: FAIL" >&2; exit 1; }
