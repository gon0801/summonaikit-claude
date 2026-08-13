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

# ============================================================================
# Task 5.4 — --host zcode: append-only al user-config de zcode (no toca DEST)
# ============================================================================
# La segunda forma de registro (hooks.events.*) vive en ~/.zcode/cli/config.json.
# --host zcode appendea las 3 fases ahi; NO instala el archivo (va antes, sin
# --host). Preflight: config JSON, enabled==true estricto, DEST NUESTRO_IDENTICO
# + linea de codigo 5.3. --quitar-zcode saca solo las entradas 5.4 (nivel entrada,
# r2.2) sin ese preflight (r3.3). Task 5.6: ademas instala/quita los
# perfiles en SAIKIT_ZCODE_AGENTS_DIR (nunca el HOME real).

n_cfg=0
zcode_cfg=''
zcode_agents=''
nuevo_zcode_cfg() {
  n_cfg=$((n_cfg + 1))
  local c="$tmp/zcode-cfg-$n_cfg"
  mkdir -p "$c/agents"
  zcode_cfg="$c/config.json"
  # Core Rule 4: nunca escribir ~/.zcode/agents del HOME real. El override
  # apunta al sandbox de ESTE caso. El instalador post-5.6 instala ahi los
  # perfiles implementer/verifier/reviewer.
  zcode_agents="$c/agents"
  # config minimo con enabled:true + vecinos (SessionStart dummy, Stop tokentracker)
  cat > "$zcode_cfg" <<'JSON'
{
  "hooks": {
    "enabled": true,
    "events": {
      "SessionStart": [
        { "hooks": [ { "type": "command", "command": "echo arranque-dummy" } ] }
      ],
      "Stop": [
        { "hooks": [ { "type": "command", "command": "echo tokentracker-dummy" } ] }
      ]
    }
  }
}
JSON
}
# DEST listo = copia identica de la fuente (NUESTRO_IDENTICO + lleva la linea 5.3).
dest_listo() { nuevo_destino; cp "$fuente" "$dest"; }

# Corre --host zcode contra el config y el dir de agentes del caso. --dest se
# fija al DEST listo del caso; flags extra (--quitar-zcode) van en "$@".
host_zcode() {
  SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
  SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
    bash "$tool" --host zcode --dest "$dest" "$@"
}

# --- B3.1) appendea 3 fases, sin matcher UPS/Stop, PTU cubre Task|Agent; no toca DEST
caso "zcode: --host zcode appendea 3 fases y NO toca DEST"
dest_listo; nuevo_zcode_cfg
dest_ck="$(cksum < "$dest")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ "$dest_ck" = "$(cksum < "$dest")" ] || malo "--host zcode no debe tocar DEST (cksum cambio)"
python - "$zcode_cfg" <<'PY' || malo "estructura appendeada distinta de la esperada"
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ev = d["hooks"]["events"]
def canon(fase, matcher_esperado):
    for g in ev.get(fase, []):
        hs = g.get("hooks", [])
        if len(hs) == 1 and hs[0].get("type") == "command" and hs[0].get("timeout") == 15 \
           and "saikit-harness-id 5.4" in hs[0].get("command", ""):
            if matcher_esperado is None:
                if "matcher" not in g: return True
            elif g.get("matcher") == matcher_esperado:
                return True
    return False
assert canon("UserPromptSubmit", None), "UPS sin matcher / type command / timeout 15"
assert canon("PostToolUse", "Bash|Edit|Write|Read|apply_patch|Task|Agent"), "PTU matcher"
assert canon("Stop", None), "Stop sin matcher"
assert any("arranque-dummy" in h.get("command","") for g in ev.get("SessionStart",[]) for h in g.get("hooks",[])), "vecino SessionStart borrado"
PY

# --- B3.2) idempotente + repara malformada
caso "zcode: segunda vez no duplica (idempotencia por entrada canonica)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
antes=$(grep -c 'saikit-harness-id 5[.]4' "$zcode_cfg")
host_zcode >/dev/null 2>&1
despues=$(grep -c 'saikit-harness-id 5[.]4' "$zcode_cfg")
[ "$antes" = "$despues" ] || malo "segunda vez duplico ($antes -> $despues)"

caso "zcode: una entrada 5.4 malformada se repara (r2.3/r3.2: command canonico exacto)"
dest_listo; nuevo_zcode_cfg
python - "$zcode_cfg" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
d["hooks"]["events"].setdefault("UserPromptSubmit", []).append(
  {"hooks": [{"type": "process", "command": 'echo bash.exe DEST --saikit-harness-id 5.4', "timeout": 500}]})
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reparando, dio $rc: $out"
python - "$zcode_cfg" <<'PY' || malo "la malformada (type process/timeout 500) no se reparo"
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for g in d["hooks"]["events"]["UserPromptSubmit"]:
    for h in g.get("hooks", []):
        if "saikit-harness-id 5.4" in h.get("command", ""):
            assert h["type"] == "command" and h["timeout"] == 15, f"sigue malformada: {h}"
PY

# --- B3.3) parcial (falta Stop) => completa sin tocar las otras
caso "zcode: parcial (falta Stop) => re-anade solo Stop"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
python - "$zcode_cfg" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding='utf-8')); del d["hooks"]["events"]["Stop"]
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
n=$(grep -c 'saikit-harness-id 5[.]4' "$zcode_cfg")
[ "$n" = "3" ] || malo "deben quedar 3 entradas 5.4, hay $n"

# --- B3.4) --dest bajo ~/.zcode => exit 2 (una sola copia, hallazgo 6)
caso "zcode: --dest bajo ~/.zcode => exit 2 (con y sin --host)"
mkdir -p "$tmp/fake-zc-home/.zcode/hooks"
bad_dest="$tmp/fake-zc-home/.zcode/hooks/summonaikit-harness.sh"
out="$(HOME="$tmp/fake-zc-home" bash "$tool" --dest "$bad_dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--dest bajo .zcode (sin --host) debe salir 2, dio $rc"
dest_listo
out="$(HOME="$tmp/fake-zc-home" bash "$tool" --host zcode --dest "$bad_dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--dest bajo .zcode (con --host) debe salir 2, dio $rc"

# --- B3.5) enabled != true => exit 2 y config intacto
for val in 'false' '"yes"' '1'; do
  caso "zcode: enabled=$val => exit 2 y config byte-igual"
  dest_listo; nuevo_zcode_cfg
  python - "$zcode_cfg" "$val" <<'PY'
import json, sys
p, val = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding='utf-8')); d["hooks"]["enabled"] = json.loads(val)
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
  cb="$(cksum < "$zcode_cfg")"
  out="$(host_zcode 2>&1)"; rc=$?
  [ "$rc" -eq 2 ] || malo "enabled=$val debe salir 2, dio $rc"
  [ "$cb" = "$(cksum < "$zcode_cfg")" ] || malo "config debe quedar intacto con enabled=$val"
done
caso "zcode: enabled ausente => exit 2"
dest_listo; nuevo_zcode_cfg
python - "$zcode_cfg" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding='utf-8')); del d["hooks"]["enabled"]
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "enabled ausente debe salir 2, dio $rc"

# --- B3.6) DEST sin controlar (NUESTRO_DISTINTO) => exit 2, config intacto
caso "zcode: DEST NUESTRO_DISTINTO => exit 2 (preflight r1.3)"
dest_listo; nuevo_zcode_cfg
escribir_nuestro_viejo "$dest"   # marcador propio pero contenido != fuente
cb="$(cksum < "$zcode_cfg")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "DEST sin controlar debe salir 2, dio $rc: $out"
[ "$cb" = "$(cksum < "$zcode_cfg")" ] || malo "config debe quedar intacto"

# --- B3.7) --quitar-zcode: nivel entrada (r2.2) + sin preflight (r3.3)
caso "zcode: --quitar-zcode saca 5.4 y deja vecinos, incluido en el MISMO hooks[] (r2.2)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
python - "$zcode_cfg" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding='utf-8'))
for g in d["hooks"]["events"]["UserPromptSubmit"]:
    hs = g.get("hooks", [])
    if any("saikit-harness-id 5.4" in h.get("command","") for h in hs):
        hs.append({"type": "command", "command": "echo vecino-mismo-grupo"})
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
out="$(host_zcode --quitar-zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
n=$(grep -c 'saikit-harness-id 5[.]4' "$zcode_cfg")
[ "$n" = "0" ] || malo "deben quedar 0 entradas 5.4, hay $n"
grep -q 'vecino-mismo-grupo' "$zcode_cfg" || malo "r2.2: el vecino del mismo hooks[] fue borrado"
grep -q 'arranque-dummy' "$zcode_cfg" || malo "vecino SessionStart borrado"
grep -q 'tokentracker-dummy' "$zcode_cfg" || malo "vecino tokentracker borrado"

caso "zcode: --quitar-zcode corre con enabled:false y DEST ausente (r3.3)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
python - "$zcode_cfg" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p, encoding='utf-8')); d["hooks"]["enabled"] = False
json.dump(d, open(p, 'w', encoding='utf-8'))
PY
rm -f "$dest"
out="$(host_zcode --quitar-zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "quitar debe correr sin preflight (r3.3), dio $rc: $out"

# --- B3.8) --host inventado => exit 2
caso "zcode: --host inventado => exit 2"
dest_listo
out="$(bash "$tool" --host inventado --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--host inventado debe salir 2, dio $rc"

# --- B3.9) regresion: sin --host no toca el user-config; --dest Claude legal OK
caso "zcode: regresion — sin --host no toca el user-config de zcode"
dest_listo; nuevo_zcode_cfg
cb="$(cksum < "$zcode_cfg")"
SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" >/dev/null 2>&1
[ "$cb" = "$(cksum < "$zcode_cfg")" ] || malo "sin --host no debe tocar el user-config de zcode"

caso "zcode: regresion — un --dest Claude legal sigue funcionando"
nuevo_destino; cp "$fuente" "$dest"
out="$(bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un --dest Claude legal debe seguir funcionando: $rc: $out"

# ============================================================================
# Task 5.6 — --host zcode tambien instala implementer/verifier/reviewer
# ============================================================================
# zcode solo conoce tipos registrados en ~/.zcode/agents/<name>.md (medido:
# Agent type 'implementer' not found. Available: general-purpose, Explore).
# Sin esos tres archivos el candado de secuencia es inalcanzable. Misma
# disciplina de tres estados que DEST: AUSENTE instala, NUESTRO_IDENTICO no
# reescribe, NUESTRO_DISTINTO repara, DESCONOCIDO no se toca. --quitar-zcode
# solo borra los que llevan saikit_owned. Fuente = agents/ del repo.

agentes_fuente="$repo/agents"
cmp_agente() {
  cmp -s "$agentes_fuente/$1.md" "$zcode_agents/$1.md"
}

caso "zcode: --host zcode instala implementer/verifier/reviewer en AGENTS_DIR"
dest_listo; nuevo_zcode_cfg
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
for rol in implementer verifier reviewer; do
  [ -f "$zcode_agents/$rol.md" ] || malo "falta $rol.md en AGENTS_DIR"
  cmp_agente "$rol" || malo "$rol.md no quedo byte a byte igual a agents/$rol.md"
  grep -q '^name: '"$rol"'$' "$zcode_agents/$rol.md" \
    || malo "$rol.md no declara name: $rol"
  grep -Eq '^saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$' "$zcode_agents/$rol.md" \
    || malo "$rol.md no lleva el marcador saikit_owned"
done
printf '%s' "$out" | grep -qi 'AGENTE' \
  || malo "no reporta la instalacion de agentes: $out"

caso "zcode: segunda vez no reescribe agentes identicos (mtime intacto)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
mtime_1="$(mtime_de "$zcode_agents/implementer.md")"
sleep 1
host_zcode >/dev/null 2>&1
[ "$(mtime_de "$zcode_agents/implementer.md")" = "$mtime_1" ] \
  || malo "reescribio un agente que ya era identico (mtime cambio)"

caso "zcode: agente DESCONOCIDO no se pisa y el hook igual se registra"
dest_listo; nuevo_zcode_cfg
printf '%s\n' '---' 'name: implementer' 'description: de otro' '---' '# custom' \
  > "$zcode_agents/implementer.md"
antes_sha="$(sha256sum < "$zcode_agents/implementer.md")"
cb="$(cksum < "$zcode_cfg")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "DESCONOCIDO no debe abortar el registro, dio $rc: $out"
[ "$(sha256sum < "$zcode_agents/implementer.md")" = "$antes_sha" ] \
  || malo "piso un implementer.md DESCONOCIDO"
grep -q 'saikit-harness-id 5[.]4' "$zcode_cfg" \
  || malo "el hook tenia que registrarse igual con un agente DESCONOCIDO"
printf '%s' "$out" | grep -qi 'desconocid' \
  || malo "no reporta el agente desconocido: $out"
# verifier y reviewer no existian: se instalan
cmp_agente verifier || malo "verifier.md tenia que instalarse (solo implementer era ajeno)"
cmp_agente reviewer || malo "reviewer.md tenia que instalarse"

caso "zcode: agente NUESTRO_DISTINTO se repara (con backup)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
{
  printf '%s\n' '---'
  printf '%s\n' 'name: implementer'
  printf '%s\n' 'description: viejo'
  printf '%s\n' 'saikit_owned: summonaikit-claude'
  printf '%s\n' '---'
  printf '%s\n' '# implementer viejo'
} > "$zcode_agents/implementer.md"
previo_sha="$(sha256sum < "$zcode_agents/implementer.md")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reparando, dio $rc: $out"
cmp_agente implementer || malo "no reparo implementer.md a la plantilla del repo"
backup="$(find "$zcode_agents" -type f -name 'implementer.md*.bak' 2>/dev/null | head -n 1)"
[ -n "$backup" ] || malo "reparo sin dejar backup"
[ -n "$backup" ] && [ "$(sha256sum < "$backup")" = "$previo_sha" ] \
  || malo "el backup no conserva el implementer previo"

caso "zcode: --quitar-zcode borra SOLO los agentes nuestros (implementer DESCONOCIDO se queda, con backup de los nuestros)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
ver_sha="$(sha256sum < "$zcode_agents/verifier.md")"
printf '%s\n' '---' 'name: implementer' 'description: de otro' '---' '# custom' \
  > "$zcode_agents/implementer.md"
ajeno_sha="$(sha256sum < "$zcode_agents/implementer.md")"
out="$(host_zcode --quitar-zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$zcode_agents/implementer.md" ] || malo "quitar borro un implementer DESCONOCIDO"
[ "$(sha256sum < "$zcode_agents/implementer.md")" = "$ajeno_sha" ] \
  || malo "quitar reescribio el implementer DESCONOCIDO"
[ ! -e "$zcode_agents/verifier.md" ] || malo "quitar debio borrar verifier.md (era nuestro)"
[ ! -e "$zcode_agents/reviewer.md" ] || malo "quitar debio borrar reviewer.md (era nuestro)"
backup="$(find "$zcode_agents" -type f -name 'verifier.md*.bak' 2>/dev/null | head -n 1)"
[ -n "$backup" ] || malo "quitar borro verifier.md sin dejar backup"
[ -n "$backup" ] && [ "$(sha256sum < "$backup")" = "$ver_sha" ] \
  || malo "el backup de verifier no conserva el contenido previo"

caso "zcode: --quitar-zcode no toca un implementer DESCONOCIDO"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
printf '%s\n' '---' 'name: implementer' 'description: de otro' '---' '# custom' \
  > "$zcode_agents/implementer.md"
antes_sha="$(sha256sum < "$zcode_agents/implementer.md")"
host_zcode --quitar-zcode >/dev/null 2>&1
[ -f "$zcode_agents/implementer.md" ] || malo "quitar borro un implementer DESCONOCIDO"
[ "$(sha256sum < "$zcode_agents/implementer.md")" = "$antes_sha" ] \
  || malo "quitar reescribio un implementer DESCONOCIDO"
[ ! -e "$zcode_agents/verifier.md" ] || malo "quitar debio borrar verifier.md (era nuestro)"

caso "zcode: fuente de agentes ausente => exit 2, config intacto, dir vacio"
dest_listo; nuevo_zcode_cfg
src_vacio="$tmp/agents-vacio"
mkdir -p "$src_vacio"
cb="$(cksum < "$zcode_cfg")"
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
       SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
       SAIKIT_ZCODE_AGENTS_SOURCE="$src_vacio" \
       bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "fuente ausente debe salir 2, dio $rc: $out"
[ "$cb" = "$(cksum < "$zcode_cfg")" ] || malo "config debe quedar intacto si faltan las plantillas"
[ ! -e "$zcode_agents/implementer.md" ] || malo "no debe instalar agentes si la fuente esta vacia"

caso "zcode: marca solo en el body (no en frontmatter) => DESCONOCIDO, no se pisa"
dest_listo; nuevo_zcode_cfg
{
  printf '%s\n' '---'
  printf '%s\n' 'name: implementer'
  printf '%s\n' 'description: de otro'
  printf '%s\n' '---'
  printf '%s\n' '# custom'
  printf '%s\n' 'saikit_owned: summonaikit-claude'
} > "$zcode_agents/implementer.md"
antes_sha="$(sha256sum < "$zcode_agents/implementer.md")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ "$(sha256sum < "$zcode_agents/implementer.md")" = "$antes_sha" ] \
  || malo "una marca solo en el body no debe contar como nuestro"
printf '%s' "$out" | grep -qi 'desconocid' \
  || malo "debia reportar DESCONOCIDO (marca fuera del frontmatter): $out"

caso "zcode: plantilla con CRLF en name: sigue siendo valida"
dest_listo; nuevo_zcode_cfg
src_crlf="$tmp/agents-crlf"
mkdir -p "$src_crlf"
for rol in implementer verifier reviewer; do
  python - "$agentes_fuente/$rol.md" "$src_crlf/$rol.md" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read().replace('\r\n', '\n').replace('\n', '\r\n')
open(dst, 'w', encoding='utf-8', newline='').write(text)
PY
done
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
       SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
       SAIKIT_ZCODE_AGENTS_SOURCE="$src_crlf" \
       bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "plantilla CRLF debe instalarse, dio $rc: $out"
[ -f "$zcode_agents/implementer.md" ] || malo "no instalo implementer.md desde plantilla CRLF"

caso "zcode: sin bash.exe no escribe agentes ni config (preflight #3)"
dest_listo; nuevo_zcode_cfg
cb="$(cksum < "$zcode_cfg")"
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
       SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
       SAIKIT_ZCODE_BASH_WIN= \
       bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "sin bash.exe debe salir 2, dio $rc: $out"
[ "$cb" = "$(cksum < "$zcode_cfg")" ] || malo "config debe quedar intacto si falta bash.exe"
[ ! -e "$zcode_agents/implementer.md" ] \
  || malo "no debe instalar agentes si bash.exe no se encontro"

caso "zcode: sin --host no escribe AGENTS_DIR"
dest_listo; nuevo_zcode_cfg
SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
  bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" >/dev/null 2>&1
[ ! -e "$zcode_agents/implementer.md" ] \
  || malo "sin --host no debe escribir implementer.md en AGENTS_DIR"

if [ "$fail" -ne 0 ]; then
  echo "test_install_hook: FAIL" >&2
  exit 1
fi
echo "test_install_hook: OK"
