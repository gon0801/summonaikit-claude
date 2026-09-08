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
#           HORA_CONTROL, cada bullet que AFIRMA una hora de Deploy (rotulo
#           Deploy, o el rotulo llano «hora [final] del deploy») exige evidencia
#           tipo/fuente DENTRO DE ESE bullet: un nombre de backup `.bak` del
#           instalador (nombre de archivo pegado — el «.bak» pelado en prosa
#           no acredita; LIMITE declarado: una negacion con token
#           filename-shape («no quedo ningun harness.sh.bak») si acredita,
#           el checker juzga texto, no semantica) O el marcador `hora medida en
#           vivo` dentro del MISMO parentesis que la hora y en FORMA DE
#           ETIQUETA: pegado al parentesis que abre («(hora medida en
#           vivo...») o inmediatamente tras coma («..., hora medida en
#           vivo...»), antes o despues de la hora. La forma de etiqueta es la
#           estructural: una NEGACION dentro del parentesis («(21:12 UTC, no
#           es una hora medida en vivo)») no es etiqueta adyacente y no
#           acredita; tampoco la negacion o el marcador en prosa, ni el
#           .bak o el marcador de un bullet hermano. La seccion de un bullet
#           Deploy la cierra CUALQUIER bullet sin sangria (`^-`, con o sin
#           negritas: un `- Nota: ...config.bak` hermano no es continuacion);
#           las continuaciones legitimas van indentadas (el sub-bullet
#           `  - **detalle:**` SI es continuacion). Sin evidencia => FAIL: la
#           hora pudo ser copiada del minuto de mergedAt (que acredita el
#           merge, NO el deploy; error historico rectificado 2026-09-07).
#           `hora no recuperada` sin hora pasa (unknown honesto). NUNCA se
#           comparan timestamps: dos horas iguales CON evidencia pasan — se
#           juzga el tipo de evidencia, no la desigualdad.
#
# Lo anterior al CORTE es abuelo y NO se juzga: las invariantes ya estan
# violadas hoy (tres inversiones de fecha; 19 de 78 encabezados fuera de norma,
# medidos) y reescribir el historico falsificaria el log. El corte se declara
# aca, no se esconde. La regla de evidencia tiene su PROPIO cordon
# (HORA_CONTROL) posterior al CORTE y CUBRE el historico que la rectificacion
# 2026-09-07 reparo: la tanda del 09-07 es exactamente nueve entradas (siete
# `hora no recuperada` sin hora + #264/#271 con .bak citado en su propio
# bullet, medido), asi que el log real pasa y una hora copiada reintroducida
# en una de ellas se rechaza. Las ~11 horas legitimas medidas en vivo y sin
# marcador viven el 2026-09-05/09-06 y quedan grandfathered fuera del cordon.
# LIMITE DECLARADO: una entrada backdateada al 09-06 evade este control — la
# fecha calendario del encabezado no es verificable por el checker.
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
# al CORTE). r4 (hallazgo B1): el 09-08 dejaba FUERA a la tanda reparada del
# 09-07 — una hora copiada de mergedAt reintroducida en #262-#272 pasaba. El
# cordon baja al 09-07 para cubrirla (justificacion y limite en la cabecera).
HORA_CONTROL='2026-09-07'

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
# r4 (adversario M1): la extraccion es CONSCIENTE DE FENCES — un `## ` falso
# pegado dentro de un bloque de codigo cercado NO es encabezado (partia la
# entrada en cuerpo_de y el bullet Deploy real caia fuera del cordon con el
# gate en verde). Solo ``` cercado; ~~~ declarado fuera.
awk '/^```/ { fence = !fence; next } !fence && /^## / { print NR ":" $0 }' "$LOG" > "$tmp/headers" 2>/dev/null || true

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

# Bullets Deploy de una entrada, UNO POR REGISTRO: cada `- **Deploy...` con
# sus lineas de continuacion, separados por una linea centinela jamas
# presente en el log. La seccion la cierra CUALQUIER bullet SIN SANGRIA
# (`^-`, con o sin negritas — r5, revisor (a): el limite `^-[[:space:]]*\*\*`
# dejaba que un bullet hermano sin negritas (`- Nota: backup ajeno
# config.bak.`) siguiera DENTRO de la seccion y su .bak acreditara la hora
# del Deploy; las continuaciones legitimas del log real van INDENTADAS, y un
# sub-bullet indentado `  - **detalle:**` sigue siendo continuacion). r2c
# (adversario M1/M2): el grep -m1 del primer corte dejaba pasar la hora de un
# SEGUNDO bullet Deploy (convencion real: un bullet por host) y las horas en
# lineas de continuacion del propio bullet. r4 (hallazgo B2): la evidencia se
# valida POR BULLET — concatenar la seccion dejaba que el .bak de un bullet
# hermano (la copia de claude) o el marcador en prosa ajena acreditaran la
# hora de OTRO bullet sin respaldo propio.
BULLET_SEP='@@SAIKIT-DEPLOY-BULLET@@'

# Secciones JUZGABLES de una entrada: un rotulo Deploy (con o sin negritas) o
# el rotulo llano «hora [final] del deploy» abre una seccion. CUALQUIER bullet sin
# sangria la cierra, aunque no sea juzgable: asi un hermano `- Nota:` no puede
# prestar su .bak o marcador. r5 conserva la forma real sin negritas
# `- hora final del deploy: ...`; r6 evita tratar horas de Verificacion,
# duraciones mm:ss y puertos como si fueran deployed_at.
secciones_deploy() {
  printf '%s' "$1" | awk '
    function es_deploy(linea, etiqueta) {
      linea = tolower(linea)
      if (linea ~ /^-[[:space:]]*\*\*deploy([[:space:](]|:|\*)/) return 1
      etiqueta = linea
      sub(/:[[:space:]].*$/, "", etiqueta)
      return etiqueta ~ /^-[[:space:]]*(deploy|hora[[:space:]]+(final[[:space:]]+)?del[[:space:]]+deploy)([[:space:]]|:|$)/
    }
    /^-/ { dentro = es_deploy($0); if (dentro) print; next }
    dentro { print }
  '
}

seccion_bullets() {
  printf '%s' "$1" | awk -v sep="$BULLET_SEP" '
    /^-/ { if (n++) print sep; dentro = 1; print; next }
    dentro { print }
  '
}

# Cierto si el bullet (texto del bullet ya unido) cita hora de deploy SIN
# fuente en SUS PROPIAS lineas: .bak pegado o marcador `hora medida en vivo`
# en el MISMO parentesis que la hora, en CUALQUIER orden. r5 (revisor (b)):
# el marcador cuenta solo en FORMA DE ETIQUETA — pegado al parentesis que
# abre (`[(][[:space:]]*hora medida en vivo`) o inmediatamente tras coma
# (`,[[:space:]]*hora medida en vivo`); una NEGACION dentro del parentesis
# («(21:12 UTC, no es una hora medida en vivo)») no es etiqueta adyacente y
# quedaba acreditada por la regex laxa `[^)]*hora medida en vivo` (rc=0
# medido). r4 (adversario M2/L1/L3/L4): solo un bullet SIN SANGRIA corta la
# seccion (un sub-bullet `  - **detalle:**` indentado es continuacion del
# Deploy — su hora cuenta); `deploy` en minuscula tambien es bullet Deploy;
# el NBSP (U+00A0) y el espacio fino (U+202F) se normalizan antes de matchear
# (el copy-paste de la web de GitHub es justo lo que los arrastra); el
# marcador cuenta antes o despues de la hora dentro del mismo parentesis.
bullet_sin_evidencia() {
  # El NBSP (U+00A0) y el espacio fino (U+202F) se normalizan por SECUENCIA
  # (tr por bytes los partiria en dos espacios y romperia la hora); la raya
  # (U+2014) se normaliza a COMA para que la forma honesta «(14:30 — hora
  # medida en vivo)» sea etiqueta valida sin regex multibyte (bash compara
  # bytes, inmune al locale). El marcador cuenta solo como ETIQUETA con
  # TERMINADOR: pegado al parentesis que abre y seguida de dos puntos
  # («(hora medida en vivo: 14:40 ...)»), o inmediatamente tras coma y hasta
  # el parentesis que cierra («(..., hora medida en vivo)»). Una negacion
  # antes o despues de la etiqueta («no es una...», «..., hora medida en
  # vivo no es)») no tiene terminador y no acredita (adversario M1/M3).
  local texto nbsp nnbsp raya
  nbsp="$(printf '\302\240')"
  nnbsp="$(printf '\342\200\257')"
  raya="$(printf '\342\200\224')"
  texto="${1//$nbsp/ }"
  texto="${texto//$nnbsp/ }"
  texto="${texto//$raya/,}"
  printf '%s' "$texto" | grep -Eq '[0-9]{1,2}[[:space:]]*:[[:space:]]*[0-5][0-9]' \
    && ! printf '%s' "$texto" | grep -Eq '[A-Za-z0-9._/-]+\.bak' \
    && ! printf '%s' "$texto" | grep -Eq '[(][^)]*[0-9]{1,2}[[:space:]]*:[[:space:]]*[0-5][0-9][^)]*,[[:space:]]*hora medida en vivo[)]' \
    && ! printf '%s' "$texto" | grep -Eq '[(][[:space:]]*hora medida en vivo:[^)]*[0-9]{1,2}[[:space:]]*:[[:space:]]*[0-5][0-9][^)]*[)]'
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
    # timestamps — se exige fuente por tipo (backup o marcador en vivo),
    # validada POR BULLET (r4, hallazgo B2): cada bullet Deploy que cita hora
    # debe llevar su .bak o su marcador en las lineas de ESE bullet. El .bak
    # cuenta solo como NOMBRE DE ARCHIVO pegado ([A-Za-z0-9._/-]+\.bak: el
    # «.bak» pelado en prosa no acredita; limite declarado en cabecera para
    # la negacion con token filename-shape) y la hora admite 1-2 digitos
    # (1:05). Las lineas del bullet se unen con espacio: los parentesis no
    # cruzan lineas y la union preserva la forma estructural del marcador.
    if [ "$fecha" \> "$HORA_CONTROL" ] || [ "$fecha" = "$HORA_CONTROL" ]; then
      falta_evid=''
      bullet=''
      while IFS= read -r blin; do
        if [ "$blin" = "$BULLET_SEP" ]; then
          if [ -n "$bullet" ] && bullet_sin_evidencia "$bullet"; then
            falta_evid=1
          fi
          bullet=''
        else
          bullet="$bullet $blin"
        fi
      done < <(seccion_bullets "$(secciones_deploy "$(cuerpo_de "$num")")"; printf '%s\n' "$BULLET_SEP")
      if [ -n "$falta_evid" ]; then
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
