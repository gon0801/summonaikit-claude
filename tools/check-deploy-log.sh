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
#   evidencia (20.27, cordón propio HORA_CONTROL): en entradas con fecha >=
#           HORA_CONTROL, la SECCION Deploy (todos sus bullets `- **Deploy...`
#           y sus lineas de continuacion) con HORA exige evidencia de deploy
#           por tipo/fuente DENTRO de esa seccion: un nombre de backup `.bak`
#           del instalador (nombre de archivo pegado — «no quedo ningun .bak»
#           en prosa ajena no acredita) O el marcador explicito `hora medida
#           en vivo`. Sin evidencia => FAIL: la hora pudo ser copiada del
#           minuto de mergedAt (que acredita el merge, NO el deploy; error
#           historico rectificado 2026-09-07). `hora no recuperada` sin hora
#           pasa (unknown honesto). NUNCA se comparan timestamps: dos horas
#           iguales CON evidencia pasan — se juzga el tipo de evidencia, no
#           la desigualdad.
#
# Lo anterior al CORTE es abuelo y NO se juzga: las invariantes ya estan
# violadas hoy (tres inversiones de fecha; 19 de 78 encabezados fuera de norma,
# medidos) y reescribir el historico falsificaria el log. El corte se declara
# aca, no se esconde. La regla de evidencia tiene su PROPIO cordon
# (HORA_CONTROL) posterior al CORTE: la region juzgada 2026-09-04..2026-09-07
# ya tiene ~10 entradas legitimas con horas medidas en vivo y sin marcador
# (medido 2026-09-08); exigirles el marcador reescribiria historia que ya
# estaba bien.
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
# 20.27: cordón de la regla de evidencia de horas de deploy (propio, posterior
# al CORTE por lo declarado en la cabecera).
HORA_CONTROL='2026-09-08'

while [ $# -gt 0 ]; do
  case "$1" in
    # Clase Task 0.4: `shift 2` con un solo argumento no consume nada y el
    # while gira para siempre. El flag con valor exige su $2 o sale 2.
    --log)
      [ $# -ge 2 ] || { printf '[deploy-log] ERROR: --log exige un valor.\n' >&2; exit 2; }
      LOG="${2:-}"; shift 2 ;;
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

# Cuerpo de la entrada cuyo encabezado vive en la linea $1: desde esa linea
# hasta el siguiente encabezado `## ` (o EOF). Para la regla de evidencia de
# horas: el bullet Deploy y su fuente se leen en la ENTRADA, no en el header.
cuerpo_de() {
  local inicio="$1" fin
  fin="$(awk -v n="$inicio" -F: '$1+0 > n {print $1+0; exit}' "$tmp/headers")"
  if [ -n "$fin" ]; then
    sed -n "${inicio},$((fin - 1))p" "$LOG"
  else
    sed -n "${inicio},\$p" "$LOG"
  fi
}

# Seccion Deploy de una entrada: TODOS los bullets `- **Deploy...` con sus
# lineas de continuacion (hasta que abre otro bullet `- **`). r2c (adversario
# M1/M2): el grep -m1 del primer corte dejaba pasar la hora de un SEGUNDO
# bullet Deploy (convencion real: un bullet por host) y las horas en lineas de
# continuacion del propio bullet. La evidencia se ancla a esta seccion para
# que una NEGACION del backup en prosa ajena o el marcador en otra clave no
# acrediten (M3).
seccion_deploy() {
  printf '%s' "$1" | awk '
    /^[[:space:]]*-[[:space:]]*\*\*Deploy/ { dentro = 1; print; next }
    /^[[:space:]]*-[[:space:]]*\*\*/       { dentro = 0 }
    dentro { print }
  '
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
    # 20.27: hora de deploy con cordón propio. Solo entradas >= HORA_CONTROL;
    # el bullet de merge (mergedAt) NO es evidencia de deploy y no se comparan
    # timestamps — se exige fuente por tipo (backup o marcador en vivo), anclada
    # a la seccion Deploy (todos sus bullets y continuaciones). El .bak cuenta
    # solo como NOMBRE DE ARCHIVO pegado ([A-Za-z0-9._/-]+\.bak: «no quedo
    # ningun .bak» en prosa no acredita) y la hora admite 1-2 digitos (1:05).
    if [ "$fecha" \> "$HORA_CONTROL" ] || [ "$fecha" = "$HORA_CONTROL" ]; then
      seccion="$(seccion_deploy "$(cuerpo_de "$num")")"
      if [ -n "$seccion" ] \
        && printf '%s' "$seccion" | grep -Eq '[0-9]{1,2}:[0-5][0-9]' \
        && ! printf '%s' "$seccion" | grep -Eq '[A-Za-z0-9._/-]+\.bak' \
        && ! printf '%s' "$seccion" | grep -F -q 'hora medida en vivo'; then
        mal "evidencia: hora de deploy sin evidencia (backup o fuente explicita); mergedAt acredita el merge — usa 'hora no recuperada' (entrada $fecha, linea $num)"
      fi
    fi
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
