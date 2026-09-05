#!/usr/bin/env bash
# check-deploy-log.sh — el deploy-log exige por maquina lo que era disciplina.
#
# Reglas (solo region JUZGADA: entradas con fecha >= CORTE):
#   norma:  "## AAAA-MM-DD — PR #N..." | "PRs ..." | "PR kimi#..." |
#           "Deploy correctivo fuera de PR: ...". Fecha calendario valida.
#   orden:  fechas no-crecientes de arriba hacia abajo (el log es newest-first).
#   prefijo: lo juzgado es un PREFIJO: nada juzgado debajo de una abuela
#           (el error historico fue apendar al final en vez de anteponer).
#   unico:  un registro por PR: cada PR en un solo encabezado juzgado.
#
# Lo anterior al CORTE es abuelo y NO se juzga: las invariantes ya estan
# violadas hoy (tres inversiones de fecha; 19 de 78 encabezados fuera de norma,
# medidos) y reescribir el historico falsificaria el log. El corte se declara
# aca, no se esconde.
#
# La extraccion de PRs no es un #[0-9]+ ingenuo: solo corre sobre encabezados
# ## con ancla PR (la prosa trae (#122, hallazgo #3, #72: falsos positivos
# medidos), expande rangos (#84–#86 son tres PRs) y namespacea kimi#N (repo
# distinto). Es ESTRICTA a proposito: todo #N en un header con ancla cuenta,
# incluso menciones ("residual del #72"); las menciones van en el cuerpo.
#
# Uso: bash tools/check-deploy-log.sh [--log PATH]
# Exit: 0 ok; 1 violaciones (nombradas); 2 uso o log ilegible.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
LOG="$repo/docs/deploy-log.md"
# 18.20: corte declarado. Entradas con fecha >= CORTE se juzgan; las viejas no.
CORTE='2026-09-04'

while [ $# -gt 0 ]; do
  case "$1" in
    --log) LOG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) printf '[deploy-log] uso: %s [--log PATH]\n' "$0" >&2; exit 2 ;;
  esac
done

if [ -z "$LOG" ] || [ ! -f "$LOG" ] || [ ! -r "$LOG" ]; then
  printf '[deploy-log] ERROR: log ilegible: %s\n' "${LOG:-vacio}" >&2
  exit 2
fi

fail=0
mal() { printf '[deploy-log] FAIL: %s\n' "$1"; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-deploylog-XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/reg"
grep -n '^## ' "$LOG" > "$tmp/headers" 2>/dev/null || true

# Imprime "ns num" por linea para un encabezado con ancla PR. Sin ancla no
# emite nada: un # suelto en un header no-PR no es un PR.
extraer_prs() {
  case "$1" in
    *'PR #'*|*'PRs #'*|*'kimi#'*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$1" | grep -oE 'kimi#[0-9]+|#[0-9]+(–|-)#?[0-9]+|#[0-9]+' 2>/dev/null | while IFS= read -r m; do
    case "$m" in
      kimi#*) printf 'kimi %s\n' "${m#kimi#}" ;;
      *–*|*-*)
        _rango="$(printf '%s' "$m" | sed 's/–/-/g' | tr -d '#')"
        _a="${_rango%%-*}"; _b="${_rango##*-}"
        case "$_a" in ''|*[!0-9]*) continue ;; esac
        case "$_b" in ''|*[!0-9]*) continue ;; esac
        if [ "$_a" -le "$_b" ] && [ $((_b - _a)) -le 200 ]; then
          _n="$_a"
          while [ "$_n" -le "$_b" ]; do printf 'pr %s\n' "$_n"; _n=$((_n + 1)); done
        else
          printf 'pr %s\n' "$_a"; printf 'pr %s\n' "$_b"
        fi
        ;;
      *) printf 'pr %s\n' "${m###}" ;;
    esac
  done
}

prev_juzgada='9999-99-99'
hay_abuela=0
n_juzgadas=0

while IFS= read -r hlin; do
  [ -n "$hlin" ] || continue
  num="${hlin%%:*}"
  lin="${hlin#*:}"
  resto="${lin#### }"
  fecha="${resto%% *}"
  case "$fecha" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *)
      mal "norma: encabezado sin fecha en linea $num: [$lin]"
      continue ;;
  esac
  mes="${fecha#????-}"; mes="${mes%-*}"; dia="${fecha##*-}"
  case "$mes" in 0[1-9]|1[0-2]) ;; *) mal "norma: mes invalido en linea $num: [$fecha]"; continue ;; esac
  case "$dia" in 0[1-9]|[12][0-9]|3[01]) ;; *) mal "norma: dia invalido en linea $num: [$fecha]"; continue ;; esac
  if [ "$fecha" \> "$CORTE" ] || [ "$fecha" = "$CORTE" ]; then
    n_juzgadas=$((n_juzgadas + 1))
    if [ "$hay_abuela" -eq 1 ]; then
      mal "prefijo: entrada juzgada ($fecha, linea $num) debajo de una abuela: anteponer, no apendar"
    fi
    if [ "$fecha" \> "$prev_juzgada" ]; then
      mal "orden: inversion de fecha ($fecha en linea $num tras $prev_juzgada)"
    fi
    prev_juzgada="$fecha"
    case "$lin" in
      "## $fecha — PR #"*|"## $fecha — PRs #"*|"## $fecha — PR kimi#"*|"## $fecha — PRs kimi#"*|"## $fecha — Deploy correctivo fuera de PR:"*) ;;
      *) mal "norma: encabezado juzgado fuera de norma en linea $num: [$lin]" ;;
    esac
    refs="$(extraer_prs "$lin")"
    while IFS=' ' read -r ns nm; do
      [ -n "${ns:-}" ] || continue
      [ -n "${nm:-}" ] || continue
      prev="$(awk -v ns="$ns" -v nm="$nm" '$1 == ns && $2 == nm { print $3; exit }' "$tmp/reg")"
      if [ -n "$prev" ]; then
        if [ "$ns" = "kimi" ]; then mostrar="kimi#$nm"; else mostrar="#$nm"; fi
        mal "duplicado: PR $mostrar en encabezados de lineas $prev y $num (un registro por PR)"
      else
        printf '%s %s %s\n' "$ns" "$nm" "$num" >> "$tmp/reg"
      fi
    done <<_REFS_EOF
$refs
_REFS_EOF
  else
    hay_abuela=1
  fi
done < "$tmp/headers"

if [ "$n_juzgadas" -eq 0 ]; then
  mal "vacio: sin entradas juzgadas (nada con fecha >= $CORTE): un OK sin cobertura es silencio"
fi

if [ "$fail" -ne 0 ]; then
  printf '[deploy-log] FAIL: ver lineas de arriba\n'
  exit 1
fi
printf '[deploy-log] OK: %s entradas juzgadas desde %s, ordenadas, con norma y sin PR duplicado\n' "$n_juzgadas" "$CORTE"
exit 0
