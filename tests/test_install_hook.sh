#!/usr/bin/env bash
# Task 2.2 — el instalador por REEMPLAZO, con sus tres estados.
#
# Por que tres estados y no dos: "no es nuestro => sobrescribir" es exactamente
# como se destruye en silencio un cambio legitimo. El destino puede ser NUESTRO
# (marcador presente) y entonces se verifica o se repara; puede ser un VENDOR
# CONOCIDO (hash en el manifiesto) y entonces se archiva y se reemplaza; o puede
# ser DESCONOCIDO, y ahi lo unico correcto es no tocarlo y gritar.
#
# El instalador es la UNICA excepcion declarada al fail-open del spec (Core Rule
# 1): el hook corre en cada turno y deja pasar lo que no puede medir, pero
# escribir sobre el a ciegas no admite esa politica. Ante lo no observable, el
# instalador falla CERRADO: no escribe y sale != 0.
#
# Core Rule 4: todo contra un tmpdir. Ningun caso mira ni escribe `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
# El instalador bajo prueba se puede apuntar a otra copia. Es la costura que
# permite correr esta misma suite contra una version MUTADA del tool y exigir
# que se de cuenta: una bateria en verde describe igual de bien a una que no
# prueba nada. Mismo mecanismo que `SAIKIT_HOOK_VIVO` en `tests/run.sh`.
tool="${SAIKIT_INSTALL_TOOL:-$repo/tools/install-hook.sh}"
fuente="$repo/hooks/summonaikit-harness.sh"
manifiesto="$repo/hooks/vendor-manifest.sha256"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-2-2-XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$tool" ]; then
  echo "    FAIL: no existe el instalador en $tool" >&2
  echo "test_install_hook: FAIL" >&2
  exit 1
fi
if [ ! -f "$fuente" ]; then
  echo "    FAIL: no existe la fuente en $fuente" >&2
  echo "test_install_hook: FAIL" >&2
  exit 1
fi

# Cada caso estrena su propio destino: un caso que ensucie el de otro haria
# pasar o fallar por contagio en vez de por lo que afirma.
#
# Asigna `$dest` en vez de imprimirlo: capturarlo con `$(...)` correria el
# contador en una subshell y todos los casos volverian a caer en `destino-1`,
# heredando los backups y los archivos del anterior. Es exactamente el contagio
# que esta funcion existe para evitar, y paso.
n_destino=0
dest=''
nuevo_destino() {
  n_destino=$((n_destino + 1))
  local d="$tmp/destino-$n_destino/.claude/hooks"
  mkdir -p "$d"
  dest="$d/summonaikit-harness.sh"
}

# mtime con nanosegundos: dos corridas seguidas caen en el mismo segundo, asi
# que `%Y` no distinguiria "no lo toco" de "lo reescribio identico".
mtime_de() { stat -c '%y' "$1" 2>/dev/null; }

# Un archivo con marcador propio pero contenido distinto al de la fuente: el
# estado "nuestro, hay que reparar".
escribir_nuestro_viejo() {
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' '# SAIKIT-CLAUDE-OWNED summonaikit-claude 0.0.1'
    printf '%s\n' 'exit 0'
  } > "$1"
}

# Un temporal huerfano dejado en el directorio del destino seria basura que el
# host ve en cada arranque, y ademas la senal de que la escritura no se limpio.
sin_temporales_sueltos() {
  local dir n
  dir="$(dirname "$1")"
  n="$(find "$dir" -maxdepth 1 -type f ! -name 'summonaikit-harness.sh' 2>/dev/null | wc -l)"
  [ "$n" -eq 0 ]
}

# ------------------------------------------------------ 1) destino DESCONOCIDO
# El caso que justifica el tercer estado. Un archivo que no es nuestro y no
# figura en el manifiesto puede ser un cambio legitimo de otro: se reporta, no
# se pisa.
caso "destino DESCONOCIDO => exit != 0, sin escribir, y lo dice fuerte"
nuevo_destino
printf '#!/usr/bin/env bash\n# hook de otro, editado a mano\nexit 0\n' > "$dest"
antes_sha="$(sha256sum < "$dest")"
antes_mtime="$(mtime_de "$dest")"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0 ante un destino desconocido, dio 0"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "REESCRIBIO un destino desconocido"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] || malo "toco el mtime de un destino desconocido"
printf '%s' "$out" | grep -qi 'desconocid' \
  || malo "no reporta el estado desconocido: $out"
sin_temporales_sueltos "$dest" || malo "dejo temporales sueltos junto al destino"

# ----------------------------------------------------- 2) destino VENDOR conocido
caso "destino VENDOR (hash en el manifiesto) => backup fechado + reemplazo byte a byte"
nuevo_destino
# El manifiesto lista hashes de destinos reales; para el test se agrega uno
# propio a una copia, asi el caso no depende de tener el archivo vivo a mano.
vendor="$tmp/vendor.sh"
printf '#!/usr/bin/env bash\n# vendor conocido, sin marcador propio\nexit 0\n' > "$vendor"
vendor_sha="$(sha256sum < "$vendor" | cut -d' ' -f1)"
cp "$vendor" "$dest"
mani_test="$tmp/manifiesto-test.sha256"
{ cat "$manifiesto" 2>/dev/null; printf '%s  vendor sintetico del test\n' "$vendor_sha"; } > "$mani_test"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$mani_test" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reemplazando un vendor conocido, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el destino no quedo byte a byte igual a la fuente"
backup="$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null | head -n 1)"
[ -n "$backup" ] || malo "no dejo backup del vendor antes de reemplazarlo"
if [ -n "$backup" ]; then
  cmp -s "$backup" "$vendor" || malo "el backup no tiene el contenido previo del destino"
  printf '%s' "$(basename "$backup")" | grep -Eq '[0-9]{8}-[0-9]{6}' \
    || malo "el backup no lleva fecha en el nombre: $(basename "$backup")"
fi
sin_temporales_sueltos "$dest" || malo "dejo temporales sueltos junto al destino"

# El spec avisa que el archivo vivo es LF puro y que escribir CRLF romperia la
# igualdad byte a byte en la primera corrida. `cmp` ya lo cubre, pero un CR en
# el destino merece decirse por su nombre.
caso "el destino queda sin CR (LF puro, como declara el spec)"
if grep -q $'\r' "$dest" 2>/dev/null; then
  malo "el destino tiene CR: la escritura convirtio los saltos de linea"
fi

# ------------------------------------------- 3) destino NUESTRO e IDENTICO
caso "destino NUESTRO e identico => no reescribe (mtime intacto) y no hace backup"
nuevo_destino
cp "$fuente" "$dest"
antes_mtime="$(mtime_de "$dest")"
sleep 1
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 con el destino ya al dia, dio $rc: $out"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] \
  || malo "reescribio un destino que ya era identico (mtime cambio)"
[ -z "$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null)" ] \
  || malo "hizo backup sin haber reemplazado nada"

# ------------------------------------------- 4) destino NUESTRO pero DISTINTO
caso "destino NUESTRO con otra version => backup + reparacion"
nuevo_destino
escribir_nuestro_viejo "$dest"
previo_sha="$(sha256sum < "$dest")"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reparando lo nuestro, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "no reparo el destino a la fuente del repo"
backup="$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null | head -n 1)"
[ -n "$backup" ] || malo "reemplazo sin dejar backup"
[ -n "$backup" ] && [ "$(sha256sum < "$backup")" = "$previo_sha" ] \
  || malo "el backup no conserva el contenido previo"

# ------------------------------------------------------ 5) el temporal invalido
# La escritura es atomica justamente para esto: se valida el archivo que VA a
# quedar, y recien ahi se hace `mv`. Un hook truncado no rompe el turno que lo
# instalo: rompe TODOS los siguientes.
caso "una fuente que no parsea NUNCA llega al destino"
nuevo_destino
cp "$fuente" "$dest"
antes_sha="$(sha256sum < "$dest")"
rota="$tmp/rota.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# SAIKIT-CLAUDE-OWNED summonaikit-claude 9.9.9'
  printf '%s\n' 'if [ 1 -eq 1 ]; then'   # sin `fi`: `bash -n` la rechaza
} > "$rota"
out="$(bash "$tool" --dest "$dest" --source "$rota" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "instalo una fuente que no parsea"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "el destino cambio pese a la fuente rota"
sin_temporales_sueltos "$dest" || malo "dejo el temporal invalido junto al destino"

# ------------------------------------------------------------ 6) idempotencia
caso "2 corridas dejan el archivo byte-identico, y la segunda no reescribe"
nuevo_destino
cp "$vendor" "$dest"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$mani_test" 2>&1)"; rc1=$?
sha_1="$(sha256sum < "$dest")"
mtime_1="$(mtime_de "$dest")"
sleep 1
out2="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$mani_test" 2>&1)"; rc2=$?
sha_2="$(sha256sum < "$dest")"
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] || malo "las dos corridas deberian salir 0 (dio $rc1 y $rc2)"
[ "$sha_1" = "$sha_2" ] || malo "la segunda corrida cambio el archivo"
[ "$(mtime_de "$dest")" = "$mtime_1" ] \
  || malo "la segunda corrida reescribio un destino que ya era identico"

# -------------------------------------------------------- 7) destino AUSENTE
caso "destino AUSENTE => instala y no inventa un backup"
nuevo_destino
rm -f "$dest"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 instalando sobre destino ausente, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "no instalo la fuente en un destino ausente"
[ -z "$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null)" ] \
  || malo "hizo backup de un archivo que no existia"

# ---------------------------------------------- 8) no observable != desconocido
# Core Rule 2. Sin manifiesto no se puede afirmar que el hash NO esta en el
# manifiesto: no se pudo mirar. El resultado practico es el mismo (no se toca),
# pero el reporte tiene que decir `unknown` y no acusar al destino de raro.
caso "manifiesto ilegible => 'unknown', no 'desconocido', y no escribe"
nuevo_destino
cp "$vendor" "$dest"
antes_sha="$(sha256sum < "$dest")"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$tmp/no-existe.sha256" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0 sin manifiesto legible, dio 0"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "escribio sin poder consultar el manifiesto"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "Core Rule 2: sin manifiesto es unknown, no una acusacion al destino: $out"

# ------------------------------------------- 8-bis) el manifiesto con CRLF
# La maquina de este repo clona con `core.autocrlf=true`, y un manifiesto en
# CRLF deja el `\r` pegado al ULTIMO campo: una linea con solo el hash pasaria a
# ser `<hash>\r` y el vendor conocido se clasificaria DESCONOCIDO — el
# instalador plantandose en una maquina y no en otra.
#
# DECLARADO: este caso pasa CON y SIN el `sub(/\r$/, "")` del instalador. El
# gawk 5.4 de esta maquina ya descarta el `\r` al partir campos (medido), asi
# que aca el guardia es portabilidad hacia los awk que no lo hacen (mawk,
# busybox) y no un defecto corregido. El caso queda igual porque afirma el
# REQUISITO —un manifiesto CRLF tiene que reconocerse— y ese requisito seguiria
# valiendo el dia que cambie el awk. Quien lea "13 de 13" en esta bateria no
# debe contar esta linea entre lo demostrado.
caso "manifiesto con CRLF y una linea de solo hash => sigue reconociendo el vendor"
nuevo_destino
cp "$vendor" "$dest"
mani_crlf="$tmp/manifiesto-crlf.sha256"
printf '# comentario\r\n%s\r\n' "$vendor_sha" > "$mani_crlf"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$mani_crlf" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un manifiesto en CRLF hizo fallar el reconocimiento (exit $rc): $out"
cmp -s "$dest" "$fuente" || malo "no reemplazo el vendor listado en un manifiesto CRLF"

# --------------------------------------------------------------- 9) dry-run
caso "--dry-run clasifica y no escribe nada"
nuevo_destino
cp "$vendor" "$dest"
antes_sha="$(sha256sum < "$dest")"
antes_mtime="$(mtime_de "$dest")"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$mani_test" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--dry-run sobre un vendor conocido deberia salir 0, dio $rc: $out"
[ "$(sha256sum < "$dest")" = "$antes_sha" ] || malo "--dry-run escribio el destino"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] || malo "--dry-run toco el mtime"
[ -z "$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null)" ] \
  || malo "--dry-run dejo un backup"

# ------------------------------------------------- 10) el REGISTRO, no solo el contenido
# Requisito del spec (§ Instalacion): un hook perfecto que `settings.json` dejo
# de nombrar es un gate que no existe. El instalador lo mira al terminar, y ese
# aviso es advisory: no cambia su exit code (el chequeo es fail-open, Task 0.3).
caso "tras instalar avisa si el hook no esta REGISTRADO, sin cambiar el exit code"
nuevo_destino
printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "echo hola" } ] } ] } }\n' \
  > "$(dirname "$(dirname "$dest")")/settings.json"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "el aviso de registro no debe cambiar el exit code (dio $rc): $out"
printf '%s' "$out" | grep -qi 'REGISTRO' \
  || malo "no verifico el registro tras instalar: $out"

if [ "$fail" -ne 0 ]; then
  echo "test_install_hook: FAIL" >&2
  exit 1
fi
echo "test_install_hook: OK"
