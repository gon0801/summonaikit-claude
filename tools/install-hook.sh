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
# La vuelta atras (--restore-vendor, Task 2.4) tiene los MISMOS modos de falla
# que la ida, asi que se le exige la misma disciplina y no un `cp`: elige el
# backup del vendor mas reciente, valida el archivo que va a quedar, archiva
# antes lo que habia —volver atras tiene que ser reversible— y recien ahi `mv`.
# Un destino DESCONOCIDO no se pisa ni para deshacer: que el comando se llame
# "restaurar" no lo habilita a destruir el cambio de otro.
#
# Uso:
#   bash tools/install-hook.sh [--dry-run]
#   bash tools/install-hook.sh --dest <path> --source <path> --manifest <path>
#   bash tools/install-hook.sh --restore-vendor [--dest <path>] [--dry-run]
#
# Exit codes (cualquier != 0 significa que el destino quedo INTACTO):
#   0  instalado / reparado / restaurado / ya estaba al dia
#   2  invocacion o fuente invalida
#   3  destino DESCONOCIDO: no se toco
#   4  no observable (unknown): no se toco
#   5  la escritura no se pudo completar: no se toco
#   6  se MIRO y no hay backup del vendor para restaurar (solo --restore-vendor).
#      Es un hecho observado, y por eso no comparte codigo con el 4: confundirlos
#      dejaria al operador sin saber si buscar el archivo o arreglar permisos.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

DEST="${HOME:-}/.claude/hooks/summonaikit-harness.sh"
SOURCE="$repo/hooks/summonaikit-harness.sh"
MANIFEST="$repo/hooks/vendor-manifest.sha256"
DRY_RUN=0
CHECK_REGISTRO=1
RESTORE=0

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
    --restore-vendor) RESTORE=1; shift ;;
    --no-registration-check) CHECK_REGISTRO=0; shift ;;
    -h|--help)  sed -n '2,48p' "$0"; exit 0 ;;
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
# En `--restore-vendor` la fuente no interviene: el archivo que va a quedar es un
# backup, y el backup del vendor por definicion NO lleva nuestro marcador. Pedirle
# los mismos requisitos que a la fuente haria imposible deshacer.
if [ "$RESTORE" -eq 0 ] && { [ ! -f "$SOURCE" ] || [ ! -r "$SOURCE" ]; }; then
  decir "[summonaikit] instalador: no hay fuente legible en $SOURCE"
  exit 2
fi

# Sin marcador, lo que instalemos hoy se clasifica DESCONOCIDO manana y el
# proximo install se planta. La identidad se declara en el archivo (Core Rule 5)
# o no se declara.
if [ "$RESTORE" -eq 0 ] && ! sed -n "${MARCADOR_LINEA}p" "$SOURCE" | grep -Eq "$MARCADOR_RE"; then
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

# --------------------------------------------- escritura atomica y archivado
# Las dos operaciones que TOCAN el destino viven en una funcion cada una, y las
# comparten la ida (instalar) y la vuelta (--restore-vendor). No es estilo: dos
# copias de la misma politica divergen, y cuando divergen lo hacen en silencio —
# es exactamente lo que la Task 0.5 encontro en `hook-acl.ps1`, donde la raiz y
# los descendientes terminaron decidiendo distinto sobre el mismo caso.
tmp_dest=''
limpiar_temporal() { [ -n "$tmp_dest" ] && rm -f "$tmp_dest"; }

abortar() {
  decir "[summonaikit] instalador: $1"
  decir "              El destino quedo INTACTO: $DEST"
  exit 5
}

# Deja en $tmp_dest el archivo que va a quedar: copiado EN EL MISMO DIRECTORIO
# del destino (`mv` solo es atomico dentro del mismo sistema de archivos),
# validado con `bash -n` y byte a byte igual al origen. Se valida la COPIA y no
# el origen: es el unico chequeo que cubre tambien la escritura (truncada, con
# permisos raros, o traducida a CRLF).
preparar_temporal() {
  local origen="$1" parse_err
  mkdir -p "$dest_dir" 2>/dev/null || {
    decir "[summonaikit] instalador: no se pudo crear $dest_dir"
    exit 5
  }
  tmp_dest="$(mktemp "$dest_dir/.saikit-install-XXXXXX")" || {
    decir "[summonaikit] instalador: no se pudo crear el temporal en $dest_dir"
    exit 5
  }
  trap 'limpiar_temporal' EXIT
  cat "$origen" > "$tmp_dest" || abortar "fallo la copia a $tmp_dest"
  # El error de bash se conserva y se imprime: un "no parsea" a secas obliga a
  # reproducir a mano lo que el instalador ya sabia.
  if ! parse_err="$(bash -n "$tmp_dest" 2>&1)"; then
    [ -n "$parse_err" ] && decir "$parse_err" >&2
    abortar "el archivo a instalar no parsea (bash -n); no se instala un hook roto"
  fi
  # El spec mide que el archivo vivo es LF puro; una escritura que traduzca los
  # saltos rompe la igualdad byte a byte en la primera corrida y el proximo
  # install ya no reconoceria lo suyo. `cmp` lo dice sin depender de la causa.
  cmp -s "$tmp_dest" "$origen" \
    || abortar "la copia no quedo byte a byte igual al origen (saltos de linea traducidos?)"
  chmod 0755 "$tmp_dest" 2>/dev/null || true
}

# Archiva el destino actual antes de pisarlo. Vale para las dos direcciones: si
# la vuelta atras pisa lo nuestro sin archivarlo, deshacer es un camino de una
# sola direccion y el operador que se arrepiente no tiene a que volver.
backup=''
archivar_destino() {
  local etiqueta="$1" backup_dir sello n
  backup_dir="$dest_dir/saikit-backups"
  mkdir -p "$backup_dir" || abortar "no se pudo crear $backup_dir"
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
}

publicar_temporal() {
  mv -f "$tmp_dest" "$DEST" || abortar "el mv final fallo (destino en uso o sin permiso)"
  tmp_dest=''
  trap - EXIT
}

# La etiqueta del backup describe QUE se archiva, no que operacion lo archiva.
etiqueta_del_estado() {
  case "$estado" in
    VENDOR_CONOCIDO) printf 'vendor' ;;
    *)               printf 'nuestro' ;;
  esac
}

# ------------------------------------------------- la vuelta: --restore-vendor
if [ "$RESTORE" -eq 1 ]; then
  bdir="$dest_dir/saikit-backups"
  base_dest="$(basename "$DEST")"

  # Core Rule 2 en el unico comando cuyo proposito es deshacer: no poder LISTAR
  # los backups no es haber visto que no hay ninguno.
  if [ -e "$bdir" ] && [ ! -d "$bdir" ]; then
    decir "[summonaikit] unknown — hay algo en la ruta de backups que no es un directorio."
    decir "              backups: $bdir"
    decir "              No se afirma que no haya backup del vendor: no se pudo mirar adentro."
    exit 4
  fi
  if [ -d "$bdir" ] && { [ ! -r "$bdir" ] || [ ! -x "$bdir" ]; }; then
    decir "[summonaikit] unknown — el directorio de backups no se puede listar."
    decir "              backups: $bdir"
    decir "              No se afirma que no haya backup del vendor: no se pudo mirar."
    exit 4
  fi

  # Se elige por el SELLO del nombre, que es el contrato que dejo la Task 2.2, y
  # no por orden alfabetico: el desempate `-N` del mismo segundo cae ANTES que el
  # que no lo lleva ('-' es 0x2D y '.' es 0x2E), asi que ordenar por nombre a
  # secas restaura el mas VIEJO de los dos, en silencio.
  elegido=''
  mejor_clave=''
  if [ -d "$bdir" ]; then
    for b in "$bdir/$base_dest".vendor.*.bak; do
      [ -f "$b" ] || continue
      resto="${b##*/}"
      resto="${resto#"$base_dest".vendor.}"
      resto="${resto%.bak}"
      case "$resto" in
        *-*-*) sello="${resto%-*}"; idx="${resto##*-}" ;;
        *-*)   sello="$resto";      idx=1 ;;
        *)     sello='';            idx=0 ;;
      esac
      case "$sello" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
        *) sello='' ;;
      esac
      case "$idx" in ''|*[!0-9]*) idx=0 ;; esac
      if [ -n "$sello" ]; then
        clave="$(printf '%s%s%06d' "${sello%%-*}" "${sello##*-}" "$idx")"
      else
        # Nombre fuera del contrato: no se puede fechar, asi que solo gana si no
        # hay ningun candidato bien formado. Se toma igual antes que dejar al
        # operador sin restaurar teniendo el archivo delante.
        clave='0'
      fi
      if [ -z "$mejor_clave" ] || [ "$clave" \> "$mejor_clave" ]; then
        mejor_clave="$clave"
        elegido="$b"
      fi
    done
  fi

  if [ -z "$elegido" ]; then
    # Se miro y no hay. Es un hecho OBSERVADO y por eso no comparte codigo con el
    # 4: el operador tiene que poder distinguir "busca el archivo en otro lado"
    # de "arregla los permisos".
    decir "[summonaikit] NO HAY BACKUP DEL VENDOR para restaurar — no se toco nada."
    decir "              destino: $DEST"
    decir "              backups: $bdir"
    decir "              Se busco $base_dest.vendor.<fecha>.bak, que es el nombre que deja este instalador."
    exit 6
  fi

  if [ ! -r "$elegido" ]; then
    decir "[summonaikit] unknown — el backup elegido no se puede leer."
    decir "              backup: $elegido"
    exit 4
  fi

  # Idempotencia, y va ANTES de juzgar el destino: si ya es byte a byte el backup
  # que ibamos a poner, no hay nada que pisar ni nada que decidir. Sin esto, una
  # segunda restauracion clasificaria el vendor recien puesto como DESCONOCIDO
  # (no lleva marcador, y su hash no tiene por que estar en el manifiesto) y
  # abortaria acusando al archivo que ella misma dejo.
  if [ -f "$DEST" ] && cmp -s "$DEST" "$elegido"; then
    decir "[summonaikit] YA RESTAURADO: el destino ya es byte a byte ese backup."
    decir "              destino: $DEST"
    decir "              backup:  $elegido"
    avisar_registro
    exit 0
  fi

  case "$estado" in
    DESCONOCIDO)
      decir "[summonaikit] DESTINO DESCONOCIDO — no se toco nada, tampoco para restaurar."
      decir "              destino: $DEST"
      decir "              $detalle"
      decir "              Volver atras no habilita a destruir un cambio que nadie miro."
      exit 3
      ;;
    NO_OBSERVABLE)
      decir "[summonaikit] unknown — no se pudo clasificar el destino, asi que no se escribio."
      decir "              destino: $DEST"
      decir "              $detalle"
      exit 4
      ;;
  esac

  if [ "$DRY_RUN" -eq 1 ]; then
    decir "[summonaikit] dry-run: se restauraria el backup del vendor."
    decir "              destino: $DEST"
    decir "              backup:  $elegido"
    avisar_registro
    exit 0
  fi

  preparar_temporal "$elegido"
  [ "$estado" != 'AUSENTE' ] && archivar_destino "$(etiqueta_del_estado)"
  publicar_temporal

  decir "[summonaikit] RESTAURADO: el destino volvio al backup del vendor."
  decir "              destino: $DEST"
  decir "              backup:  $elegido"
  [ -n "$backup" ] && decir "              lo anterior quedo archivado en: $backup"
  avisar_registro
  exit 0
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
# Las tres operaciones son las mismas que usa `--restore-vendor`, con el mismo
# orden: preparar y validar la copia, archivar lo que habia, y recien entonces
# publicar. Lo unico que cambia entre la ida y la vuelta es el ORIGEN.
preparar_temporal "$SOURCE"
[ "$estado" != 'AUSENTE' ] && archivar_destino "$(etiqueta_del_estado)"
publicar_temporal

case "$estado" in
  AUSENTE)          decir "[summonaikit] INSTALADO: el destino no existia." ;;
  NUESTRO_DISTINTO) decir "[summonaikit] REPARADO: el destino era nuestro y difiere de la fuente." ;;
  VENDOR_CONOCIDO)  decir "[summonaikit] REEMPLAZADO: el destino era un vendor conocido ($detalle)." ;;
esac
decir "              destino: $DEST"
[ -n "$backup" ] && decir "              backup:  $backup"
avisar_registro
exit 0
