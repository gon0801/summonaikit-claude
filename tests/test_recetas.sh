#!/usr/bin/env bash
# tests/test_recetas.sh — Task 16.2: forma de las recetas + manifiesto candado.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"; sandbox_init
. "$here/lib/recetas_lint.sh"
fail=0; caso() { printf '  caso: %s\n' "$1"; }; malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

buena() {  # $1=ruta → escribe una receta valida minima (nombre: bug)
  mkdir -p "$(dirname "$1")"
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
Understand: … Receta: bug.
EOF
}

# Nota: `buena` escribe `nombre: bug`; el linter exige nombre == archivo, asi
# que las fixtures que deben ser VALIDAS se llaman bug.md (en subdirs propios).

caso "receta valida => 0"
buena "$SANDBOX/ok/bug.md"; lint_receta "$SANDBOX/ok/bug.md" >/dev/null || malo "rechazo una receta valida"

caso "termino prohibido => 1 con motivo"
buena "$SANDBOX/p/bug.md"; printf 'Usa Graphite para el stack.\n' >> "$SANDBOX/p/bug.md"
out="$(lint_receta "$SANDBOX/p/bug.md")" && malo "acepto 'Graphite'"; printf '%s' "$out" | grep -q prohibido || malo "motivo sin 'prohibido': $out"

caso "termino prohibido con otra caja => 1"
buena "$SANDBOX/pc/bug.md"; printf 'Usa graphite en minusculas.\n' >> "$SANDBOX/pc/bug.md"
lint_receta "$SANDBOX/pc/bug.md" >/dev/null && malo "acepto 'graphite' en minusculas"

caso "termino prohibido Cursor (sensible a caja) => 1"
buena "$SANDBOX/pcu/bug.md"; printf 'El Cursor me ayuda a editar.\n' >> "$SANDBOX/pcu/bug.md"
lint_receta "$SANDBOX/pcu/bug.md" >/dev/null && malo "acepto 'Cursor'"

caso "el cursor del mouse NO es termino prohibido => 0"
buena "$SANDBOX/cur/bug.md"; printf 'Mueve el cursor del mouse hacia el boton.\n' >> "$SANDBOX/cur/bug.md"
lint_receta "$SANDBOX/cur/bug.md" >/dev/null || malo "rechazo 'el cursor del mouse' como si fuera Cursor"

caso "'right ' no es termino prohibido; 'gt' token si => 1"
buena "$SANDBOX/r/bug.md"; printf 'Mueve el boton a la right side.\n' >> "$SANDBOX/r/bug.md"
lint_receta "$SANDBOX/r/bug.md" >/dev/null || malo "rechazo 'right ' como si fuera 'gt'"
buena "$SANDBOX/gt/bug.md"; printf 'Usa gt para filtrar.\n' >> "$SANDBOX/gt/bug.md"
lint_receta "$SANDBOX/gt/bug.md" >/dev/null && malo "acepto 'gt' como token"

caso "'gt' al final de linea => 1 (frontera de token)"
buena "$SANDBOX/gtf/bug.md"; printf 'pasa el flag gt' >> "$SANDBOX/gtf/bug.md"
lint_receta "$SANDBOX/gtf/bug.md" >/dev/null && malo "acepto 'gt' al final de linea (sin espacio)"

caso "operador shell -gt NO es termino prohibido => 0"
buena "$SANDBOX/sgt/bug.md"; printf 'Comprueba que [ "$n" -gt 10 ].\n' >> "$SANDBOX/sgt/bug.md"
lint_receta "$SANDBOX/sgt/bug.md" >/dev/null || malo "rechazo '-gt' (operador shell) como si fuera 'gt'"

caso "token unido por guion (x-gt-y, gt-x) NO es termino prohibido => 0"
buena "$SANDBOX/sgxy/bug.md"; printf 'Compara con x-gt-y y el flag gt-x.\n' >> "$SANDBOX/sgxy/bug.md"
lint_receta "$SANDBOX/sgxy/bug.md" >/dev/null || malo "rechazo 'x-gt-y'/'gt-x' como si fuera 'gt'"

caso "termino prohibido Bugbot => 1"
buena "$SANDBOX/bb/bug.md"; printf 'Bugbot lo reporta.\n' >> "$SANDBOX/bb/bug.md"
lint_receta "$SANDBOX/bb/bug.md" >/dev/null && malo "acepto 'Bugbot'"

caso "termino prohibido AskQuestion => 1"
buena "$SANDBOX/aq/bug.md"; printf 'AskQuestion resuelve la duda.\n' >> "$SANDBOX/aq/bug.md"
lint_receta "$SANDBOX/aq/bug.md" >/dev/null && malo "acepto 'AskQuestion'"

caso "termino prohibido /loop => 1"
buena "$SANDBOX/lp/bug.md"; printf 'Corre con /loop.\n' >> "$SANDBOX/lp/bug.md"
lint_receta "$SANDBOX/lp/bug.md" >/dev/null && malo "acepto '/loop'"

caso "frontmatter sin linea de cierre => 1"
printf -- '---\nsaikit_owned: summonaikit-claude\nnombre: bug\ntitulo: Arreglar algo\ncarril: full\ncuando: ["x"]\nadversary: opcional\n## Pasos\n1. a\n## Qué le dices al usuario\nb\n## Recibo\nc\n' > "$SANDBOX/fsc.md"
lint_receta "$SANDBOX/fsc.md" >/dev/null && malo "acepto frontmatter sin '---' de cierre"

caso "titulo plegado o literal => 1"
buena "$SANDBOX/pg/bug.md"; sed -i 's/^titulo: .*/titulo: >/' "$SANDBOX/pg/bug.md"
lint_receta "$SANDBOX/pg/bug.md" >/dev/null && malo "acepto titulo plegado (>)"

caso "titulo plegado con chomping => 1"
buena "$SANDBOX/pgc/bug.md"; sed -i 's/^titulo: .*/titulo: >-/' "$SANDBOX/pgc/bug.md"
lint_receta "$SANDBOX/pgc/bug.md" >/dev/null && malo "acepto titulo plegado con chomping (>-)"

caso "link relativo con espacios resuelve"
mkdir -p "$SANDBOX/ly/sub"; : > "$SANDBOX/ly/sub/mi archivo.md"
buena "$SANDBOX/ly/bug.md"; printf '[esto](sub/mi archivo.md)\n' >> "$SANDBOX/ly/bug.md"
lint_receta "$SANDBOX/ly/bug.md" >/dev/null || malo "rechazo un link relativo con espacios que existe"

caso "carril invalido => 1"
buena "$SANDBOX/c/bug.md"; sed -i 's/^carril: full/carril: rapido/' "$SANDBOX/c/bug.md"
lint_receta "$SANDBOX/c/bug.md" >/dev/null && malo "acepto carril: rapido"

caso "mas de 80 lineas => 1"
buena "$SANDBOX/l/bug.md"; yes 'relleno' | head -n 80 >> "$SANDBOX/l/bug.md"
lint_receta "$SANDBOX/l/bug.md" >/dev/null && malo "acepto 90 lineas"

caso "81 lineas SIN salto final => 1 (wc -l las subcontaria a 80)"
buena "$SANDBOX/l81/bug.md"
cur="$(wc -l < "$SANDBOX/l81/bug.md" | tr -d ' ')"; add=$((81 - cur - 1))
yes 'relleno' | head -n "$add" >> "$SANDBOX/l81/bug.md"; printf 'ultima sin salto' >> "$SANDBOX/l81/bug.md"
# wc -l cuenta los \n de las 80 primeras lineas (la 81 no tiene salto) => 80, el
# tope no se dispara con wc -l; la regla de lineas LOGICAS (awk END NR) cuenta 81
# y debe rechazar. 'cur' es lo que aporta buena, para dejar 81 lineales exactos.
[ "$(wc -l < "$SANDBOX/l81/bug.md" | tr -d ' ')" = 80 ] || malo "precondicion rota: wc -l no es 80 (el caso no discrimina)"
lint_receta "$SANDBOX/l81/bug.md" >/dev/null && malo "acepto 81 lineas por falta de salto final"

caso "nombre distinto del archivo => 1; igual => 0"
buena "$SANDBOX/otro.md"     # nombre: bug pero archivo otro.md
lint_receta "$SANDBOX/otro.md" >/dev/null && malo "acepto nombre != archivo"
buena "$SANDBOX/eq/bug.md"; lint_receta "$SANDBOX/eq/bug.md" >/dev/null || malo "rechazo bug.md con nombre: bug"

caso "TAB en el titulo => 1"
buena "$SANDBOX/t/bug.md"; sed -i "s/^titulo: .*/titulo: Con\ttab/" "$SANDBOX/t/bug.md"
lint_receta "$SANDBOX/t/bug.md" >/dev/null && malo "acepto TAB en el titulo"

caso "CRLF se tolera en lectura"
buena "$SANDBOX/crlf/bug.md"; sed -i 's/$/\r/' "$SANDBOX/crlf/bug.md"
lint_receta "$SANDBOX/crlf/bug.md" >/dev/null || malo "rechazo una receta CRLF"

caso "manifest_linea: 5 campos TAB y el titulo de varias palabras entero"
buena "$SANDBOX/m/bug.md"
linea="$(manifest_linea "$SANDBOX/m/bug.md")"
[ "$(printf '%s' "$linea" | awk -F'\t' '{print NF}')" = 5 ] || malo "no son 5 campos: $linea"
[ "$(printf '%s' "$linea" | cut -f5)" = "Arreglar algo que no funciona" ] || malo "titulo partido: $linea"

caso "manifest_linea hashea normalizado a LF (receta CRLF => hash == sha de los bytes LF)"
buena "$SANDBOX/nl/bug.md"; sed -i 's/$/\r/' "$SANDBOX/nl/bug.md"
sha_lf="$(tr -d '\r' < "$SANDBOX/nl/bug.md" | sha256sum | cut -c1-64)"
sha_man="$(manifest_linea "$SANDBOX/nl/bug.md" | cut -f1)"
[ "$sha_man" = "$sha_lf" ] || malo "manifest_linea no normaliza a LF (esperado $sha_lf, got $sha_man)"

caso "manifest_unicos detecta nombres duplicados"
printf 'a\treceta\tbug\tfull\tT\nb\treceta\tbug\tfast\tT2\n' > "$SANDBOX/dup.tsv"
manifest_unicos "$SANDBOX/dup.tsv" >/dev/null && malo "acepto nombres duplicados"
printf 'a\treceta\tbug\tfull\tT\nb\treceta\tboceto\tfast\tT2\n' > "$SANDBOX/un.tsv"
manifest_unicos "$SANDBOX/un.tsv" >/dev/null || malo "rechazo nombres unicos"

caso "00-lider marcado tipo: receta => 1 (no tiene Pasos/Recibo)"
printf -- '---\nsaikit_owned: summonaikit-claude\ntipo: receta\nnombre: lider\ntitulo: Lider\ncarril: full\ncuando: ["x"]\nadversary: opcional\n---\n## Principios\n' > "$SANDBOX/lider-mal.md"
lint_receta "$SANDBOX/lider-mal.md" >/dev/null && malo "acepto un lider marcado receta sin secciones de receta"

caso "--check: manifiesto ausente => 1 (via --dir)"
gen_dir="$SANDBOX/gen"; mkdir -p "$gen_dir"; buena "$gen_dir/bug.md"
bash "$repo/tools/gen-recetas-manifest.sh" --dir "$gen_dir" --check >/dev/null; rc=$?
[ "$rc" -eq 1 ] || malo "--check con manifiesto AUSENTE devolvio $rc (esperado 1)"

caso "--check: manifiesto al dia => 0; stale => 1 (via --dir)"
bash "$repo/tools/gen-recetas-manifest.sh" --dir "$gen_dir" >/dev/null || malo "generar el manifiesto del sandbox fallo"
bash "$repo/tools/gen-recetas-manifest.sh" --dir "$gen_dir" --check >/dev/null; rc=$?
[ "$rc" -eq 0 ] || malo "--check AL DIA devolvio $rc (esperado 0)"
sed -i 's/^titulo: .*/titulo: Otro/' "$gen_dir/bug.md"
bash "$repo/tools/gen-recetas-manifest.sh" --dir "$gen_dir" --check >/dev/null; rc=$?
[ "$rc" -eq 1 ] || malo "--check con manifiesto STALE devolvio $rc (esperado 1)"

# ---------------------------------------------------------- el repo real
caso "todas las recetas del repo pasan el linter"
for f in "$repo"/recetas/*.md; do
  out="$(lint_receta "$f")" || malo "$(basename "$f"): $out"
done
caso "cuidar-pr: los pasos numerados respetan el orden fijo que la receta declara"
# Regresion (regla de hierro): la receta declaraba "conflictos -> hilos -> CI" y
# despues numeraba conflictos(3), CI(4), hilos(5). Un modelo que sigue los pasos
# en orden invertia el orden que la propia receta fija. El linter no lo veia
# porque cada paso, por separado, era valido.
cp_receta="$repo/recetas/cuidar-pr.md"
if [ -r "$cp_receta" ]; then
  grep -Fq 'Orden fijo' "$cp_receta" || malo "cuidar-pr ya no declara un orden fijo"
  ln_conf="$(grep -nE '^[0-9]+\. \*\*Conflictos\*\*' "$cp_receta" | head -n1 | cut -d: -f1)"
  ln_hilos="$(grep -nE '^[0-9]+\. \*\*Hilos de bots\*\*' "$cp_receta" | head -n1 | cut -d: -f1)"
  ln_ci="$(grep -nE '^[0-9]+\. \*\*CI rojo\*\*' "$cp_receta" | head -n1 | cut -d: -f1)"
  if [ -z "$ln_conf" ] || [ -z "$ln_hilos" ] || [ -z "$ln_ci" ]; then
    malo "cuidar-pr: no se ubicaron los tres pasos (conflictos=$ln_conf hilos=$ln_hilos ci=$ln_ci)"
  else
    [ "$ln_conf" -lt "$ln_hilos" ] || malo "cuidar-pr: conflictos (linea $ln_conf) no va antes que hilos (linea $ln_hilos)"
    [ "$ln_hilos" -lt "$ln_ci" ]   || malo "cuidar-pr: hilos (linea $ln_hilos) no va antes que CI (linea $ln_ci) — contradice el orden fijo declarado"
  fi
else
  malo "no se puede leer recetas/cuidar-pr.md"
fi

caso "el manifiesto esta al dia (gen --check)"
bash "$repo/tools/gen-recetas-manifest.sh" --check >/dev/null || malo "MANIFEST.sha256 desactualizado: corre tools/gen-recetas-manifest.sh"

[ "$fail" -eq 0 ] && echo "test_recetas: OK" || { echo "test_recetas: FAIL" >&2; exit 1; }
