#!/usr/bin/env bash
# golden-harness.sh — arnes de salida dorada del hook (Task 1.2).
#
# QUE HACE, en una frase: corre el hook contra escenarios de payloads reales y
# graba, paso por paso, su exit code, su stdout, su stderr y el ESTADO que deja
# en disco. Esa grabacion es la linea base: mientras el hook se comporte igual,
# `--check` sale 0; cuando cambie, dice exactamente en que escenario y en que
# paso cambio.
#
# Para que existe: hoy el hook no tiene ninguna descripcion ejecutable de su
# comportamiento. Sin ella, reemplazarlo (Phase 2) o corregirle un defecto
# (Phase 3) es a ciegas — no habria forma de distinguir "arregle A1" de "rompi
# el gate entero".
#
# ---------------------------------------------------------------------------
# Tres decisiones que conviene entender antes de tocar este archivo:
#
# 1. EL HOOK SE COPIA AL SANDBOX; NUNCA SE CORRE EN SU LUGAR. El hook deriva su
#    directorio de estado de `dirname $0`, asi que correrlo donde vive
#    escribiria en `~/.claude/hooks/state/` — el estado VIVO del gate, en cada
#    corrida del arnes. La copia es byte-identica (el sha queda grabado en la
#    cabecera), y esa es la unica forma de cumplir "el arnes jamas escribe en
#    ~/.claude".
#
# 2. LA COMPARACION ES DE COMPORTAMIENTO, NO DE BYTES. La cabecera (identidad
#    del archivo: sha, tamano, lineas) queda FUERA de la comparacion, que
#    empieza en la primera linea `=== escenario `. Es deliberado: la Phase 2.1
#    le agrega al hook un marcador de propiedad, o sea le cambia el sha a
#    proposito, y ahi el arnes tiene que poder decir "otros bytes, mismo
#    comportamiento". Si comparara la identidad, daria rojo justo en el caso
#    para el que existe. El cambio de identidad se REPORTA como nota.
#
# 3. LO NO DETERMINISTA SE NORMALIZA, Y NADA MAS. Solo tres cosas cambian entre
#    corridas: la ruta del sandbox, el nombre del directorio de estado (un
#    cksum de la ruta del proyecto) y los timestamps UTC del log de evidencia.
#    Se reemplazan por marcadores. El resto se graba literal — incluido el
#    task_hash, que es un cksum del prompt y por lo tanto SI es estable y SI
#    tiene que detectarse si cambia.
#
# Uso:
#   bash tools/golden-harness.sh --print     # registro a stdout
#   bash tools/golden-harness.sh --record    # graba tests/golden/baseline.txt
#   bash tools/golden-harness.sh --check     # compara contra la linea base
#
# Opciones:
#   --hook PATH        archivo a ejercitar (def: $HOME/.claude/hooks/summonaikit-harness.sh)
#   --scenarios DIR    escenarios          (def: <repo>/tests/fixtures/escenarios)
#   --baseline PATH    linea base          (def: <repo>/tests/golden/baseline.txt)
#
# Exit codes (la distincion importa: Core Rule 2, `not_observed != absent`):
#   0  ok — registro generado, o comportamiento identico a la linea base
#   1  DIVERGENCIA — el hook ya no se comporta como la linea base
#   2  unknown — no se pudo mirar (falta el hook, la linea base o los escenarios)
set -u
export LC_ALL=C   # orden de `sort` y de los globs estable entre maquinas

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

HOOK="${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"
ESCENARIOS="$repo/tests/fixtures/escenarios"
BASELINE="$repo/tests/golden/baseline.txt"
MODO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --hook)      HOOK="${2:-}"; shift 2 ;;
    --scenarios) ESCENARIOS="${2:-}"; shift 2 ;;
    --baseline)  BASELINE="${2:-}"; shift 2 ;;
    --print)     MODO="print"; shift ;;
    --record)    MODO="record"; shift ;;
    --check)     MODO="check"; shift ;;
    -h|--help)   sed -n '2,60p' "$0"; exit 0 ;;
    *)           printf 'golden-harness: opcion desconocida: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$MODO" ]; then
  printf 'golden-harness: falta el modo (--print | --record | --check)\n' >&2
  exit 2
fi

# --------------------------------------------------------------- utilleria
sha_de() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
sha_corto() { sha_de "$1" | cut -c1-16; }

work="$(mktemp -d "${TMPDIR:-/tmp}/saikit-golden-XXXXXX")" || exit 2
trap 'rm -rf "$work"' EXIT
dedup="$work/.dedup"; mkdir -p "$dedup"

# Segunda forma de la ruta del sandbox: en Windows varias herramientas la
# devuelven como C:/... aunque bash la reciba como /c/... . Se normalizan las
# dos; si apareciera una tercera forma sin normalizar, el caso de
# reproducibilidad del test lo delata (dos corridas darian distinto).
work_win="$work"
if command -v cygpath >/dev/null 2>&1; then
  work_win="$(cygpath -m "$work" 2>/dev/null || printf '%s' "$work")"
fi

normalizar() {
  # Task 5.3: el state-path ahora lleva HOST (state/<host>/<key>/<sess>/...).
  # La 1ra regex come host+key (host = [a-z]+: claude/zcode/other); la 2da
  # cubre cualquier residual pre-5.3 (state/<key>/...). Se uso clase de chars y
  # no (claude|zcode|other) porque el delimitador `|` choca con la alternancia
  # en el sed de MSYS2/Git Bash (BRE \| y ERE | ambos se rompen).
  sed -e "s|$work_win|<SANDBOX>|g" \
      -e "s|$work|<SANDBOX>|g" \
      -e 's|state/[a-z][a-z]*/[0-9][0-9]*|state/<PROJECT_KEY>|g' \
      -e 's|state/[0-9][0-9]*|state/<PROJECT_KEY>|g' \
      -e 's|[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z|<TS>|g'
}

# Emite un stream (stdout o stderr) ya normalizado. Los repetidos se declaran
# una sola vez: el contrato inyectado son ~5.6 KB IDENTICOS en casi todos los
# escenarios, y repetirlo 12 veces convertiria la linea base en un archivo que
# nadie lee. La referencia es exacta (mismo sha), asi que no se pierde nada.
emitir_stream() {
  etiqueta="$1"; archivo="$2"; ref="$3"
  norm="$work/.norm"
  normalizar < "$archivo" > "$norm"
  bytes="$(wc -c < "$norm" | tr -d ' ')"
  if [ "$bytes" = "0" ]; then
    printf '%s <vacio>\n' "$etiqueta"
    return 0
  fi
  sha="$(sha_corto "$norm")"
  if [ -f "$dedup/$sha" ]; then
    printf '%s (sha %s, %s bytes) identico a %s\n' "$etiqueta" "$sha" "$bytes" "$(cat "$dedup/$sha")"
    return 0
  fi
  printf '%s' "$ref" > "$dedup/$sha"
  printf '%s (sha %s, %s bytes)\n' "$etiqueta" "$sha" "$bytes"
  sed 's/^/| /' "$norm"
}

# Todo lo que el hook dejo en el sandbox, no solo lo que se espera de el: si
# alguna version escribiera en otro lado, aparece aca en vez de pasar
# inadvertida. Se excluyen unicamente las ENTRADAS que puso el arnes y la copia
# del propio hook.
#
# Corre una vez por paso y por escenario, o sea decenas de veces por corrida:
# en Windows cada proceso que se lanza cuesta plata, asi que filtra dentro del
# propio `find` y normaliza el stream entero de una sola pasada en vez de dos
# por archivo.
instantanea_estado() {
  sb="$1"
  restos="$work/.restos"
  find "$sb" -type f \
    -not -path "$sb/entrada/*" \
    -not -path "$sb/hooks/summonaikit-harness.sh" 2>/dev/null \
    | sort > "$restos"
  if [ ! -s "$restos" ]; then
    printf '(sin estado)\n'
    return 0
  fi
  while IFS= read -r f; do
    printf '%s\n' "${f#$sb/}"
    sed 's/^/| /' "$f"
  done < "$restos" | normalizar
}

# Task 5.5: el HOST que --print puede afirmar para el target zcode. `normalizar`
# (arriba) reemplaza state/<host>/<key> por state/<PROJECT_KEY> ANTES de emitir,
# asi que mirando el snapshot normalizado un --print no puede mostrar el host.
# Esta funcion lee el arbol SIN normalizar y devuelve el segmento host
# (state/<host>/...). Si no hay estado (escenario sin armar, o un Stop que ya
# borro), devuelve vacio y la linea no se emite: no se inventa un host. Se llama
# SOLO para objetivo=zcode; los escenarios 01-16 (claude/cursor/auto) no ganan
# esta linea y siguen byte-identicos.
host_del_estado() {
  hb_sb="$1"
  f="$(find "$hb_sb/hooks/state" -type f 2>/dev/null | head -n 1)"
  [ -n "$f" ] || return 1
  printf '%s' "$f" | sed -n 's|.*/state/\([a-z][a-z]*\)/.*|\1|p'
}

# ------------------------------------------------------------- validaciones
if [ ! -r "$HOOK" ] || [ ! -f "$HOOK" ]; then
  printf 'golden-harness: unknown — no hay hook que ejercitar en: %s\n' "$HOOK" >&2
  printf '                No se afirma nada sobre su comportamiento: no se pudo mirar.\n' >&2
  exit 2
fi

if [ ! -d "$ESCENARIOS" ]; then
  printf 'golden-harness: unknown — no existe el directorio de escenarios: %s\n' "$ESCENARIOS" >&2
  exit 2
fi

lista_esc="$work/.escenarios"
# Se ignoran los directorios ocultos: el tooling del entorno deja `.claude` y
# similares tirados en cualquier lado, y uno de esos colandose como "escenario"
# agregaria un bloque vacio a la linea base sin que nadie lo note.
find "$ESCENARIOS" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort > "$lista_esc"
n_esc="$(wc -l < "$lista_esc" | tr -d ' ')"
if [ "$n_esc" = "0" ]; then
  # Cero escenarios no es "todo verde": es cobertura cero. Salir 0 aca seria el
  # mismo modo de falla que el runner cuida cuando lo apuntan a una raiz que no
  # existe.
  printf 'golden-harness: unknown — %s no tiene ningun escenario; no hay nada que grabar\n' "$ESCENARIOS" >&2
  exit 2
fi

# --------------------------------------------------------- generar registro
generar() {
  printf '# summonaikit-claude — linea base de salida dorada (Task 1.2)\n'
  printf '#\n'
  printf '# Generada por `bash tools/golden-harness.sh --record`. NO editar a mano:\n'
  printf '# es una GRABACION del comportamiento del hook, no una especificacion de\n'
  printf '# como deberia comportarse. Cuando cambie a proposito, se regraba y el\n'
  printf '# diff del commit es la declaracion de que cambio.\n'
  printf '#\n'
  printf '# La comparacion de `--check` empieza en la primera linea `=== escenario `:\n'
  printf '# la identidad de aca abajo es informativa (ver decision 2 en el arnes).\n'
  printf '#\n'
  printf '# hook_sha256: %s\n' "$(sha_de "$HOOK")"
  printf '# hook_bytes: %s\n' "$(wc -c < "$HOOK" | tr -d ' ')"
  printf '# hook_lineas: %s\n' "$(wc -l < "$HOOK" | tr -d ' ')"
  printf '# escenarios: %s\n' "$n_esc"
  printf '#\n'
  printf '# Normalizaciones aplicadas (lo unico que cambia entre corridas):\n'
  printf '#   <SANDBOX>      la raiz temporal de cada escenario\n'
  printf '#   <PROJECT_KEY>  el cksum de la ruta del proyecto que llavea el estado\n'
  printf '#   <TS>           timestamps UTC del log de evidencia\n'
  printf '# `bytes` es el tamano del stream YA normalizado; un stream sin salto de\n'
  printf '# linea final se distingue por ahi (las lineas se muestran con prefijo "| ").\n'

  while IFS= read -r esc; do
    nombre="$(basename "$esc")"
    printf '\n=== escenario %s\n' "$nombre"
    if [ -f "$esc/README" ]; then
      sed 's/^/# /' "$esc/README"
    fi

    sb="$work/$nombre"
    mkdir -p "$sb/hooks" "$sb/proyecto" "$sb/home" "$sb/entrada"
    cp "$HOOK" "$sb/hooks/summonaikit-harness.sh"

    # Se reinicia por escenario y vive FUERA del sandbox: adentro seria un
    # archivo mas y se grabaria a si mismo como estado del hook.
    estado_previo="$work/.estado-previo"
    rm -f "$estado_previo"

    pasos="$work/.pasos"
    find "$esc" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort > "$pasos"
    if [ ! -s "$pasos" ]; then
      # Un escenario sin pasos no corre NADA y aun asi ocupa un bloque en la
      # linea base: cobertura fantasma, la misma trampa que el caso de "cero
      # escenarios". Se rompe la corrida en vez de dejar un comentario.
      printf 'golden-harness: el escenario %s no tiene ningun paso (*.json).\n' "$nombre" >&2
      printf '                Un escenario vacio pasaria el --check sin ejecutar nada.\n' >&2
      return 2
    fi

    while IFS= read -r paso; do
      archivo="$(basename "$paso")"
      base="${archivo%.json}"
      n="${base%%.*}"
      resto="${base#*.}"
      fase="${resto%%.*}"
      objetivo="${resto#*.}"

      # Transcript del paso, si lo tiene. El token __TRANSCRIPT__ del payload se
      # reemplaza por su ruta real; sin companion apunta a un archivo que no
      # existe, que tambien es un caso real (transcript ilegible => tail vacio).
      tr_dst="$sb/entrada/transcript-$n.jsonl"
      if [ -f "$esc/$base.transcript.jsonl" ]; then
        cp "$esc/$base.transcript.jsonl" "$tr_dst"
      else
        tr_dst="$sb/entrada/transcript-inexistente-$n.jsonl"
      fi
      entrada="$sb/entrada/paso-$n.json"
      sed "s|__TRANSCRIPT__|$tr_dst|g" "$paso" > "$entrada"

      printf -- '--- paso %s  phase=%s target=%s  payload=%s\n' "$n" "$fase" "$objetivo" "$archivo"

      # `auto` = la variable NO se exporta. Es un caso real: si el registro en
      # settings.json no las pone, el hook deriva la fase del propio payload.
      # Task 5.3: se unsetean tambien ZCODE_SESSION_ID / ZCODE_PROJECT_DIR (la
      # senal de host de zcode, medida Task 5.1). Sin esto, un --check corrido
      # DENTRO de zcode escribe state/zcode/... y uno desde Claude state/other/...
      # => divergencia falsa por host, no por comportamiento.
      cmd=(env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE -u SUMMONAIKIT_HOOK_TARGET
           -u CLAUDECODE -u ZCODE_SESSION_ID -u ZCODE_PROJECT_DIR
           HOME="$sb/home" USERPROFILE="$sb/home")
      [ "$fase" != "auto" ] && cmd+=(SUMMONAIKIT_HOOK_PHASE="$fase")
      # Task 5.5: el token `zcode` del filename NO exporta SUMMONAIKIT_HOOK_TARGET
      # (5.2 declaro que TARGET=claude alcanza; 5.4 lo cablea por fallback). En
      # su lugar pone la senal de host que zcode inyecta en produccion (5.1):
      # ZCODE_SESSION_ID / ZCODE_PROJECT_DIR. Asi el golden ejercita el camino
      # vivo (HOST=zcode + TARGET=claude por el fallback de 5.4), no un
      # TARGET=zcode inventado que nadie probo; si el fallback de 5.4 se
      # rompiera, este escenario lo delata. Las dos constantes son literales
      # fijas (no la ruta del sandbox): si algo filtrara al estado, romperia
      # --check entre corridas. auto/claude/cursor siguen como antes.
      if [ "$objetivo" = "zcode" ]; then
        cmd+=(ZCODE_SESSION_ID=sess_golden_zcode ZCODE_PROJECT_DIR=C:/dev/saikit-golden-zcode)
      elif [ "$objetivo" != "auto" ]; then
        cmd+=(SUMMONAIKIT_HOOK_TARGET="$objetivo")
      fi

      out="$work/.out"; err="$work/.err"
      ( cd "$sb/proyecto" && "${cmd[@]}" bash "$sb/hooks/summonaikit-harness.sh" ) \
        < "$entrada" > "$out" 2> "$err"
      rc=$?

      printf 'exit %s\n' "$rc"
      emitir_stream "stdout" "$out" "$nombre/paso $n"
      emitir_stream "stderr" "$err" "$nombre/paso $n (stderr)"

      # El estado en disco es comportamiento igual que el stdout: el Stop gate
      # decide leyendolo, no leyendo el transcript. Se graba DESPUES DE CADA
      # PASO y solo cuando cambio — asi se ve en que paso exacto el hook anota
      # cada cosa, sin repetir el mismo bloque cinco veces.
      estado_ahora="$work/.estado-ahora"
      instantanea_estado "$sb" > "$estado_ahora"
      if [ -f "$estado_previo" ] && cmp -s "$estado_previo" "$estado_ahora"; then
        printf 'estado sin cambios\n'
      else
        printf -- '--- estado tras el paso %s\n' "$n"
        cat "$estado_ahora"
      fi
      cp "$estado_ahora" "$estado_previo"

      # Task 5.5: para el target zcode, afirmar el HOST que el fallback de 5.4
      # resolvio (debe ser zcode). Se lee del arbol SIN normalizar (ver
      # host_del_estado): el snapshot de arriba ya perdio el segmento host. Si el
      # token fallara y el hook escribiera state/other/ o state/claude/, la linea
      # diria eso y --check daria rojo contra una baseline que espera zcode. Sin
      # estado (sin armar / Stop que borro) no se emite: 01-16 tampoco la tienen.
      # Task 6.6: mismo mecanismo para codex — el snapshot normaliza el segmento
      # host, asi que esta linea es lo UNICO que pinna en la linea base que el
      # estado quedo bajo state/codex/ (D2, Task 6.4) y no bajo other/claude.
      if [ "$objetivo" = "zcode" ] || [ "$objetivo" = "codex" ]; then
        _hh="$(host_del_estado "$sb")"
        # if/then (no `[ ] && printf`): cuando no hay estado _hh queda vacio y
        # este bloque NO puede devolver non-zero, o se vuelve el exit status del
        # while interno y generar cae en `|| exit 2` (medido: escenarios zcode
        # sin estado, p.ej. el 17 sin armar). Un if sin rama tomada retorna 0.
        if [ -n "$_hh" ]; then
          printf 'estado_host: %s\n' "$_hh"
        fi
      fi
    done < "$pasos"
  done < "$lista_esc"
}

registro="$work/registro.txt"
generar > "$registro" || exit 2

case "$MODO" in
  print)
    cat "$registro"
    exit 0
    ;;
  record)
    mkdir -p "$(dirname "$BASELINE")" || exit 2
    cp "$registro" "$BASELINE" || exit 2
    printf 'golden-harness: linea base grabada en %s (%s escenarios)\n' "$BASELINE" "$n_esc"
    exit 0
    ;;
esac

# ------------------------------------------------------------------ --check
if [ ! -s "$BASELINE" ]; then
  printf 'golden-harness: unknown — no hay linea base en %s contra que comparar.\n' "$BASELINE" >&2
  printf '                Grabar una con --record (y revisar el diff antes de commitear).\n' >&2
  exit 2
fi

# Nota de identidad: informativa, NUNCA decide el veredicto (decision 2).
sha_base="$(grep -m1 '^# hook_sha256: ' "$BASELINE" | sed 's/^# hook_sha256: //')"
sha_ahora="$(sha_de "$HOOK")"
if [ -n "$sha_base" ] && [ "$sha_base" != "$sha_ahora" ]; then
  printf '[nota] el hook cambio de identidad desde la linea base:\n'
  printf '       grabado: %s\n' "$sha_base"
  printf '       ahora:   %s\n' "$sha_ahora"
  printf '       La comparacion de abajo es de COMPORTAMIENTO, no de bytes.\n'
fi

# El nombre del escenario se usa como NOMBRE DE ARCHIVO al partir el registro.
# La linea base es un archivo de texto: uno manipulado con `../` en ese nombre
# haria que `--check` anexara contenido fuera de su tmpdir. No es el ataque mas
# probable del mundo, pero un verificador que escribe donde le digan deja de
# ser un verificador.
nombre_de_escenario_valido() {
  case "$1" in
    ''|.|..)             return 1 ;;
    *[!A-Za-z0-9._-]*)   return 1 ;;
  esac
  return 0
}

partir() {
  # Parte un registro en un archivo por escenario, para poder decir cual
  # diverge en vez de tirar un diff de 2000 lineas.
  origen="$1"; destino="$2"
  mkdir -p "$destino"

  nombres="$work/.nombres"
  sed -n 's/^=== escenario //p' "$origen" > "$nombres"
  while IFS= read -r n; do
    if ! nombre_de_escenario_valido "$n"; then
      printf 'golden-harness: nombre de escenario invalido en %s: "%s"\n' "$origen" "$n" >&2
      printf '                Se usa como nombre de archivo; no se aceptan rutas.\n' >&2
      return 2
    fi
  done < "$nombres"

  awk -v out="$destino" '
    /^=== escenario /{ f = out "/" $3 }
    f { print >> f }
  ' "$origen"
}

partir "$BASELINE" "$work/base" || exit 2
partir "$registro" "$work/ahora" || exit 2

divergentes=""
faltantes=""
sobrantes=""

for f in "$work/base"/*; do
  [ -e "$f" ] || continue
  nombre="$(basename "$f")"
  if [ ! -f "$work/ahora/$nombre" ]; then
    faltantes="$faltantes $nombre"
  elif ! cmp -s "$f" "$work/ahora/$nombre"; then
    divergentes="$divergentes $nombre"
  fi
done
for f in "$work/ahora"/*; do
  [ -e "$f" ] || continue
  nombre="$(basename "$f")"
  [ -f "$work/base/$nombre" ] || sobrantes="$sobrantes $nombre"
done

if [ -z "$divergentes" ] && [ -z "$faltantes" ] && [ -z "$sobrantes" ]; then
  printf 'golden-harness: OK — %s escenarios se comportan igual que la linea base\n' "$n_esc"
  exit 0
fi

printf 'golden-harness: DIVERGENCIA — el hook ya no se comporta como la linea base\n' >&2
[ -n "$divergentes" ] && printf '  escenarios que cambiaron:%s\n' "$divergentes" >&2
[ -n "$faltantes" ]   && printf '  escenarios de la linea base que ya no existen:%s\n' "$faltantes" >&2
[ -n "$sobrantes" ]   && printf '  escenarios nuevos, sin linea base:%s\n' "$sobrantes" >&2
for nombre in $divergentes; do
  printf '\n--- diff de %s (linea base -> ahora)\n' "$nombre" >&2
  diff -u "$work/base/$nombre" "$work/ahora/$nombre" | head -n 60 >&2
done
exit 1
