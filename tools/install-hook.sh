#!/usr/bin/env bash
# install-hook.sh — instala el hook por REEMPLAZO, con tres estados (Task 2.2).
#
# El problema que resuelve: el archivo que gatea cada turno vive en
# `~/.claude/hooks/`, fuera del repo. Sincronizarlo con un `cp` tiene dos modos
# de falla graves y silenciosos:
#
#   1. Pisa un cambio legitimo que alguien mas hizo en el destino. Un `cp` no
#      sabe distinguir "el archivo de siempre" de "un archivo que no vimos
#      nunca". Por eso hay TRES estados y no dos:
#
#        NUESTRO         (marcador en la linea 2) => verificar; reparar si difiere
#        VENDOR CONOCIDO (sha256 en el manifiesto) => archivar y reemplazar
#        DESCONOCIDO     (ninguna de las dos)      => NO TOCAR y reportar fuerte
#
#   2. Deja el destino a medio escribir. `cp` no es atomico: un hook truncado no
#      rompe el turno que lo instalo, rompe TODOS los siguientes. Por eso se
#      escribe a un temporal EN EL MISMO DIRECTORIO, se valida ahi (`bash -n`
#      mas igualdad byte a byte con la fuente) y recien entonces `mv`.
#
# Politica ante lo no observable: este script es la UNICA excepcion declarada al
# fail-open del spec (Core Rule 1). El hook deja pasar lo que no puede medir
# porque corre en cada turno; escribir sobre el a ciegas no admite esa politica.
# Aca lo no observable falla CERRADO: no escribe y sale != 0. Y se reporta como
# `unknown`, nunca como "el destino es raro" (Core Rule 2): no haber podido
# consultar el manifiesto no es lo mismo que haber visto que el hash no esta.
#
# Uso:
#   bash tools/install-hook.sh [--dry-run]
#   bash tools/install-hook.sh --dest <path> --source <path> --manifest <path>
#
# Exit codes (cualquier != 0 significa que el destino quedo INTACTO):
#   0  instalado / reparado / ya estaba al dia
#   2  invocacion o fuente invalida
#   3  destino DESCONOCIDO: no se toco
#   4  no observable (unknown): no se toco
#   5  la escritura no se pudo completar: no se toco
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

DEST="${HOME:-}/.claude/hooks/summonaikit-harness.sh"
SOURCE="$repo/hooks/summonaikit-harness.sh"
MANIFEST="$repo/hooks/vendor-manifest.sha256"
DRY_RUN=0
CHECK_REGISTRO=1

# Posicion y formato fijos, como los declara el spec (§ La adopcion). La linea 1
# es el shebang: un marcador antes de el rompe la ejecucion. Se lee UNA linea,
# que es justo lo que necesita tambien el skip de quality-kit (Task 2.3).
MARCADOR_LINEA=2
MARCADOR_PREFIJO='# SAIKIT-CLAUDE-OWNED '
MARCADOR_RE='^# SAIKIT-CLAUDE-OWNED summonaikit-claude [^[:space:]]+$'

while [ $# -gt 0 ]; do
  case "$1" in
    --dest)     DEST="${2:-}"; shift 2 ;;
    --source)   SOURCE="${2:-}"; shift 2 ;;
    --manifest) MANIFEST="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --no-registration-check) CHECK_REGISTRO=0; shift ;;
    -h|--help)  sed -n '2,45p' "$0"; exit 0 ;;
    *)
      printf '[summonaikit] instalador: opcion desconocida: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

decir() { printf '%s\n' "$*"; }

# El aviso del REGISTRO (Task 0.3) es el otro requisito del spec para instalar:
# el archivo puede quedar perfecto y el gate no existir si `settings.json` dejo
# de nombrarlo. Es ADVISORY — ese verificador es fail-open y su resultado no
# mueve el exit code de este script. Se le pasa el settings HERMANO del destino
# y no el del HOME real, para que apuntar `--dest` a un fixture no termine
# mirando el perfil vivo (Core Rule 4).
avisar_registro() {
  [ "$CHECK_REGISTRO" -eq 1 ] || return 0
  local verificador settings
  verificador="$here/check-hook-registration.sh"
  [ -r "$verificador" ] || return 0
  settings="$(dirname "$(dirname "$DEST")")/settings.json"
  bash "$verificador" --settings "$settings" --hook-name "$(basename "$DEST")" || true
}

# ------------------------------------------------------------------ la fuente
if [ ! -f "$SOURCE" ] || [ ! -r "$SOURCE" ]; then
  decir "[summonaikit] instalador: no hay fuente legible en $SOURCE"
  exit 2
fi

# Sin marcador, lo que instalemos hoy se clasifica DESCONOCIDO manana y el
# proximo install se planta. La identidad se declara en el archivo (Core Rule 5)
# o no se declara.
if ! sed -n "${MARCADOR_LINEA}p" "$SOURCE" | grep -Eq "$MARCADOR_RE"; then
  decir "[summonaikit] instalador: la fuente no lleva el marcador de propiedad en la linea $MARCADOR_LINEA."
  decir "              Instalarla dejaria un archivo que el proximo install no puede reconocer."
  decir "              fuente: $SOURCE"
  exit 2
fi

sha_bin=''
for c in sha256sum shasum; do
  if command -v "$c" >/dev/null 2>&1; then sha_bin="$c"; break; fi
done
sha_de() {
  case "$sha_bin" in
    sha256sum) sha256sum < "$1" | cut -d' ' -f1 ;;
    shasum)    shasum -a 256 < "$1" | cut -d' ' -f1 ;;
    *)         return 1 ;;
  esac
}

# ------------------------------------------------------- clasificar el destino
dest_dir="$(dirname "$DEST")"

estado=''
detalle=''

if [ ! -e "$DEST" ]; then
  estado='AUSENTE'
elif [ ! -f "$DEST" ]; then
  # Un directorio o un dispositivo donde deberia haber un script: no se sabe que
  # es ni que se rompe al moverlo.
  estado='NO_OBSERVABLE'
  detalle="el destino existe pero no es un archivo regular"
elif [ ! -r "$DEST" ]; then
  estado='NO_OBSERVABLE'
  detalle="el destino existe pero no se puede leer"
elif sed -n "${MARCADOR_LINEA}p" "$DEST" | grep -Eq "$MARCADOR_RE"; then
  if cmp -s "$DEST" "$SOURCE"; then
    estado='NUESTRO_IDENTICO'
  else
    estado='NUESTRO_DISTINTO'
  fi
elif grep -q "^$MARCADOR_PREFIJO" "$DEST"; then
  # Lleva la marca pero no donde ni como se declaro. Puede ser una version
  # futura, otra herramienta, o alguien editando a mano: ninguna de las tres
  # habilita a pisarlo.
  estado='DESCONOCIDO'
  detalle="tiene el marcador fuera de la linea $MARCADOR_LINEA o con otro formato"
elif [ -z "$sha_bin" ]; then
  estado='NO_OBSERVABLE'
  detalle="no hay sha256sum ni shasum para comparar contra el manifiesto"
elif [ ! -r "$MANIFEST" ]; then
  # Core Rule 2: no poder consultar el manifiesto NO es haber visto que el hash
  # falta. El destino no queda acusado de nada.
  estado='NO_OBSERVABLE'
  detalle="el manifiesto no se puede leer: $MANIFEST"
else
  dest_sha="$(sha_de "$DEST")" || dest_sha=''
  if [ -z "$dest_sha" ]; then
    estado='NO_OBSERVABLE'
    detalle="no se pudo calcular el sha256 del destino"
  # El `\r` se saca antes de comparar: en un checkout Windows el manifiesto
  # puede llegar con CRLF, y ahi una linea que tenga SOLO el hash dejaria el
  # `\r` pegado al campo 1. El vendor conocido pasaria a "desconocido" y el
  # instalador se plantaria en una maquina y no en otra — la peor forma de
  # romperse. `.gitattributes` ya lo fuerza a LF; esto cubre el archivo que
  # llegue editado por otra herramienta.
  elif awk -v h="$dest_sha" '
         { sub(/\r$/, "") }
         /^[[:space:]]*(#|$)/ { next }
         $1 == h { found = 1; exit }
         END { exit found ? 0 : 1 }' "$MANIFEST"; then
    estado='VENDOR_CONOCIDO'
    detalle="$(awk -v h="$dest_sha" '
         { sub(/\r$/, "") }
         $1 == h { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "$MANIFEST")"
  else
    estado='DESCONOCIDO'
    detalle="sha256 $dest_sha, que no figura en el manifiesto"
  fi
fi

# --------------------------------------------------- los dos estados que paran
case "$estado" in
  DESCONOCIDO)
    decir "[summonaikit] DESTINO DESCONOCIDO — no se toco nada."
    decir "              destino: $DEST"
    decir "              $detalle"
    decir "              No lleva el marcador de propiedad y su contenido no esta en el manifiesto."
    decir "              Puede ser un cambio legitimo de otro: revisarlo, y si corresponde"
    decir "              agregar su sha256 a $MANIFEST con una etiqueta que diga que es."
    exit 3
    ;;
  NO_OBSERVABLE)
    decir "[summonaikit] unknown — no se pudo clasificar el destino, asi que no se escribio."
    decir "              destino: $DEST"
    decir "              $detalle"
    decir "              No se afirma que el destino sea desconocido: no se pudo mirar (Core Rule 2)."
    decir "              El instalador falla CERRADO: es la excepcion declarada al fail-open."
    exit 4
    ;;
esac

# ------------------------------------------------- el estado que no escribe nada
if [ "$estado" = 'NUESTRO_IDENTICO' ]; then
  # No se reescribe "por las dudas": un `mv` cambia el mtime y con el la unica
  # senal barata de cuando cambio de verdad el archivo que gatea cada turno.
  decir "[summonaikit] YA AL DIA: el destino es nuestro y byte a byte igual a la fuente."
  decir "              destino: $DEST"
  avisar_registro
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  case "$estado" in
    AUSENTE)         decir "[summonaikit] dry-run: el destino no existe; se instalaria la fuente." ;;
    NUESTRO_DISTINTO) decir "[summonaikit] dry-run: destino NUESTRO pero distinto; se repararia (con backup)." ;;
    VENDOR_CONOCIDO) decir "[summonaikit] dry-run: destino VENDOR CONOCIDO ($detalle); se archivaria y reemplazaria." ;;
  esac
  decir "              destino: $DEST"
  decir "              fuente:  $SOURCE"
  avisar_registro
  exit 0
fi

# ------------------------------------------------------------ escritura atomica
mkdir -p "$dest_dir" 2>/dev/null || {
  decir "[summonaikit] instalador: no se pudo crear $dest_dir"
  exit 5
}

# El temporal va en el MISMO directorio que el destino a proposito: `mv` solo es
# atomico dentro del mismo sistema de archivos. Desde `$TMPDIR` seria una copia
# con ventana de archivo a medio escribir, que es justo lo que hay que evitar.
tmp_dest="$(mktemp "$dest_dir/.saikit-install-XXXXXX")" || {
  decir "[summonaikit] instalador: no se pudo crear el temporal en $dest_dir"
  exit 5
}
trap 'rm -f "$tmp_dest"' EXIT

abortar() {
  decir "[summonaikit] instalador: $1"
  decir "              El destino quedo INTACTO: $DEST"
  exit 5
}

cat "$SOURCE" > "$tmp_dest" || abortar "fallo la copia a $tmp_dest"

# Se valida el archivo que VA A QUEDAR, no la fuente: es el unico chequeo que
# cubre tambien la copia (truncada, con permisos raros, o traducida a CRLF).
# El error de bash se conserva y se imprime: un "no parsea" a secas obliga a
# reproducir a mano lo que el instalador ya sabia.
if ! parse_err="$(bash -n "$tmp_dest" 2>&1)"; then
  [ -n "$parse_err" ] && decir "$parse_err" >&2
  abortar "el archivo a instalar no parsea (bash -n); no se instala un hook roto"
fi

# El spec mide que el archivo vivo es LF puro; una escritura que traduzca los
# saltos rompe la igualdad byte a byte en la primera corrida y el proximo
# install ya no reconoceria lo suyo. `cmp` lo dice sin depender de la causa.
cmp -s "$tmp_dest" "$SOURCE" \
  || abortar "la copia no quedo byte a byte igual a la fuente (saltos de linea traducidos?)"

chmod 0755 "$tmp_dest" 2>/dev/null || true

# ---------------------------------------------------------------- backup fechado
backup=''
if [ "$estado" != 'AUSENTE' ]; then
  backup_dir="$dest_dir/saikit-backups"
  mkdir -p "$backup_dir" || abortar "no se pudo crear $backup_dir"
  case "$estado" in
    VENDOR_CONOCIDO) etiqueta='vendor' ;;
    *)               etiqueta='nuestro' ;;
  esac
  sello="$(date +%Y%m%d-%H%M%S)"
  backup="$backup_dir/$(basename "$DEST").$etiqueta.$sello.bak"
  # Dos corridas dentro del mismo segundo no se pisan el backup: el segundo
  # archivo seria el que se quiere conservar y lo perderia.
  n=2
  while [ -e "$backup" ]; do
    backup="$backup_dir/$(basename "$DEST").$etiqueta.$sello-$n.bak"
    n=$((n + 1))
  done
  cp "$DEST" "$backup" || abortar "no se pudo archivar el destino en $backup"
  cmp -s "$backup" "$DEST" || abortar "el backup no reproduce el destino; no se reemplaza sin respaldo"
fi

if ! mv -f "$tmp_dest" "$DEST"; then
  abortar "el mv final fallo (destino en uso o sin permiso)"
fi
trap - EXIT

case "$estado" in
  AUSENTE)          decir "[summonaikit] INSTALADO: el destino no existia." ;;
  NUESTRO_DISTINTO) decir "[summonaikit] REPARADO: el destino era nuestro y difiere de la fuente." ;;
  VENDOR_CONOCIDO)  decir "[summonaikit] REEMPLAZADO: el destino era un vendor conocido ($detalle)." ;;
esac
decir "              destino: $DEST"
[ -n "$backup" ] && decir "              backup:  $backup"
avisar_registro
exit 0
