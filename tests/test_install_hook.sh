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
# Task 12.5: el router de modelo/effort que agente_traducido() consume.
router="$repo/tools/model-routing.sh"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-2-2-XXXXXX")" || exit 1
# Task 16.5: el instalador por defecto publica tambien el recetario y /sencillo
# ($HOME/.claude/skills). Core Rule 4: jamas `~/.claude`. Se apunta HOME (y
# USERPROFILE, como hacen los casos codex) al sandbox y se crea el padre del
# skill para que la publicacion por dos renames tenga donde mktemp.
export HOME="$tmp"
export USERPROFILE="$tmp"
mkdir -p "$tmp/.claude/skills"

# CodeRabbit (PR #62, CR2): el caso de lookup multi-hash muta TEMPORALMENTE
# el manifiesto TRACKEADO del repo (agents/vendor-manifest.sha256) para
# probar el lookup real -- necesario porque el instalador no tiene una
# costura de manifiesto de agentes por env (a diferencia de --manifest para
# el del hook). Sin proteccion, una interrupcion a mitad del caso deja ese
# archivo sucio en el arbol real. MANIFEST_AGENTES_BACKUP se declara ANTES
# del trap de salida principal y se restaura ahi, antes de borrar $tmp (que
# es donde vive el backup) -- cubre exit normal, exit por error y la mayoria
# de las señales de interrupcion (bash sigue corriendo el trap EXIT incluso
# terminando por señal, salvo SIGKILL/SIGSTOP).
MANIFEST_AGENTES_BACKUP=''
restaurar_manifiesto_agentes() {
  if [ -n "$MANIFEST_AGENTES_BACKUP" ] && [ -f "$MANIFEST_AGENTES_BACKUP" ]; then
    cp "$MANIFEST_AGENTES_BACKUP" "$repo/agents/vendor-manifest.sha256" 2>/dev/null
  fi
}
trap 'restaurar_manifiesto_agentes; rm -rf "$tmp"' EXIT

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
# --host zcode appendea las 4 fases ahi (la 4a, SessionStart, la habilito la
# medicion de la Task 10.9); NO instala el archivo (va antes, sin
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
  # perfiles implementer/verifier/reviewer (y adversary desde la Task 13.8).
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

# --- B3.1) appendea 4 fases, sin matcher UPS/Stop/SessionStart, PTU cubre Task|Agent; no toca DEST
caso "zcode: --host zcode appendea 4 fases y NO toca DEST"
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
assert canon("SessionStart", None), "SessionStart sin matcher (4a fase, Task 10.9)"
assert any("arranque-dummy" in h.get("command","") for g in ev.get("SessionStart",[]) for h in g.get("hooks",[])), "vecino SessionStart borrado"
PY

# --- B3.1-bis) la 4a fase SI se registra en zcode, y solo porque se MIDIO (10.9)
# Este caso nacio invertido y se dio vuelta el mismo dia, a proposito.
#
# El POLIZON: el guard de la 10.6 dice, en su comentario, que las reglas
# permanentes salen "solo en Claude", pero el codigo pregunta por TARGET=claude —
# y TARGET para zcode resuelve JUSTAMENTE a `claude` por el fallback
# ZCODE_SESSION_ID/ZCODE_PROJECT_DIR (decision de la 5.4: las formas de salida
# medidas en 5.2 son las mismas). O sea que el hook YA emitiria en zcode; lo
# unico que lo frenaba era que el instalador registraba 3 fases y no la de
# arranque, equilibrio que ningun caso sostenia.
#
# Mientras zcode estuvo `unknown` este caso exigia lo CONTRARIO (que la 4a fase
# NO se registrara), y dejaba escrito que se invertiria cuando hubiera veredicto
# — para que el cambio de este archivo fuera la declaracion de que la medicion
# existio, en vez de un aflojamiento silencioso. El veredicto llego el
# 2026-08-16 y es ACEPTADA, con los dos oraculos en la misma linea del rollout:
# el texto entra al request del modelo como mensaje role="system" con el prefijo
# `SessionStart hook additional context:` y numeracion `#1` (la MISMA forma que
# 5.2 midio para UPS, solo cambia el nombre de la fase), y el modelo devolvio el
# token literal que ese texto le pedia.
#
# Las dos mitades siguen exigidas: que este la nuestra NO puede lograrse pisando
# la ajena.
caso "zcode: registra la 4a fase (SessionStart) — habilitado por la medicion de la 10.9"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1
python - "$zcode_cfg" <<'PY' || malo "zcode: la 4a fase no quedo registrada como la medicion habilito"
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ev = d["hooks"]["events"]
grupos = [g for g in ev.get("SessionStart", [])
          if any("saikit-harness-id 5.4" in h.get("command", "") for h in g.get("hooks", []))]
assert len(grupos) == 1, f"SessionStart debe tener exactamente 1 grupo canonico, tiene {len(grupos)}"
assert "matcher" not in grupos[0], "el grupo de SessionStart va sin matcher (vacuo = startup y resume)"
hs = grupos[0]["hooks"]
assert len(hs) == 1 and hs[0].get("type") == "command" and hs[0].get("timeout") == 15, \
    "la entrada de SessionStart tiene que ser canonica igual que las otras tres"
# La otra mitad: registrar la nuestra no puede lograrse pisando la ajena.
vecino = [h for g in ev.get("SessionStart", []) for h in g.get("hooks", [])
          if "arranque-dummy" in h.get("command", "")]
assert vecino, "el vecino ajeno de SessionStart tiene que seguir ahi"
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
[ "$n" = "4" ] || malo "deben quedar 4 entradas 5.4, hay $n"

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

caso "zcode: --host zcode instala implementer/verifier/reviewer/adversary en AGENTS_DIR"
# Task 13.8: adversary es el cuarto perfil. Corre con el router REAL y la
# fila zcode esta vacia a proposito (12.1): el adversary instalado NO lleva
# claves de ruteo y hereda del padre.
dest_listo; nuevo_zcode_cfg
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
# Deploy 13.9 (bug vivo): limpiar_trads_vendor se declaraba DESPUES del
# dispatch de zcode y el instalador gritaba `command not found` sin mover
# ningun veredicto (trads sin limpiar, stderr sucio). Ningun caso lo
# atrapaba porque todos afirman strings esperados, no ausencia de ruido.
printf '%s' "$out" | grep -q 'command not found' \
  && malo "el instalador grito 'command not found' (funcion usada antes de declararse): $out"
for rol in implementer verifier reviewer adversary; do
  [ -f "$zcode_agents/$rol.md" ] || malo "falta $rol.md en AGENTS_DIR"
  cmp_agente "$rol" || malo "$rol.md no quedo byte a byte igual a agents/$rol.md"
  grep -q '^name: '"$rol"'$' "$zcode_agents/$rol.md" \
    || malo "$rol.md no declara name: $rol"
  grep -Eq '^saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$' "$zcode_agents/$rol.md" \
    || malo "$rol.md no lleva el marcador saikit_owned"
done
grep -q '^model:' "$zcode_agents/adversary.md" \
  && malo "adversary.md en zcode no debe llevar model: (fila vacia, 12.1)"
grep -q '^thoughtLevel:' "$zcode_agents/adversary.md" \
  && malo "adversary.md en zcode no debe llevar thoughtLevel: (fila vacia, 12.1)"
printf '%s' "$out" | grep -qi 'AGENTE' \
  || malo "no reporta la instalacion de agentes: $out"

caso "zcode: adversary DESCONOCIDO no se pisa y el resto se instala"
# Misma regla de la linea base (5.6) aplicada al cuarto rol: un adversary.md
# ajeno (sin marca) no se toca, se reporta, y no aborta nada.
dest_listo; nuevo_zcode_cfg
printf '%s\n' '---' 'name: adversary' 'description: de otro' '---' '# custom' \
  > "$zcode_agents/adversary.md"
antes_sha="$(sha256sum < "$zcode_agents/adversary.md")"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "adversary DESCONOCIDO no debe abortar, dio $rc: $out"
[ "$(sha256sum < "$zcode_agents/adversary.md")" = "$antes_sha" ] \
  || malo "piso un adversary.md DESCONOCIDO"
printf '%s' "$out" | grep -qi 'desconocid' \
  || malo "no reporta el adversary desconocido: $out"
cmp_agente reviewer || malo "reviewer.md tenia que instalarse (solo adversary era ajeno)"

caso "zcode: NO_OBSERVABLE en el ULTIMO rol no deja los tres primeros publicados (grok r1 #1 / codex r1 #1)"
# El mismo 12.9 #1 que claude/kimi ya cerraron, aplicado a zcode: el bucle
# clasificaba el DESTINO y publicaba en la misma vuelta — un adversary.md
# NO_OBSERVABLE (directorio) salia exit 5 con los tres anteriores YA
# escritos: instalacion a medias que el exit != 0 ademas desmiente.
dest_listo; nuevo_zcode_cfg
mkdir -p "$zcode_agents/adversary.md"
out="$(host_zcode 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "esperaba exit 5 (NO_OBSERVABLE), dio $rc: $out"
[ -e "$zcode_agents/implementer.md" ] && malo "implementer.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (zcode a medias)"
[ -e "$zcode_agents/verifier.md" ] && malo "verifier.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (zcode a medias)"
[ -e "$zcode_agents/reviewer.md" ] && malo "reviewer.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (zcode a medias)"

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
[ ! -e "$zcode_agents/adversary.md" ] || malo "quitar debio borrar adversary.md (era nuestro)"
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
for rol in implementer verifier reviewer adversary; do
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

# ===================================================== Task 6.5 — --host codex
# El destino lo decide --host y cada host declara su ruta (D1): --host codex
# escribe la SEGUNDA copia en <home>/.codex/hooks/ con los MISMOS tres estados
# y la misma escritura atomica del flujo normal — a diferencia de --host zcode,
# que es registro-only y nunca toca DEST. ~/.zcode sigue rechazado siempre;
# ~/.codex se habilita SOLO con --host codex.
# Task 13.8: codex NO tiene costura de perfiles (--host codex instala solo la
# segunda copia del hook); como se instalaria/rutearia adversary en codex queda
# UNKNOWN declarado — no medido, no se afirma nada aca.
n_codex=0
home_cx=''
nuevo_home_codex() {
  n_codex=$((n_codex + 1))
  home_cx="$tmp/codex-$n_codex"
  mkdir -p "$home_cx/.codex/hooks"
  dest="$home_cx/.codex/hooks/summonaikit-harness.sh"
}

caso "codex: destino AUSENTE + --host codex => instala en <home>/.codex/hooks (ruta por defecto del host)"
nuevo_home_codex
rm -f "$dest"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 instalando codex sobre ausente, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el destino codex no quedo byte a byte igual a la fuente"
sin_temporales_sueltos "$dest" || malo "dejo temporales sueltos junto al destino codex"

caso "codex: destino VENDOR conocido => backup fechado + reemplazo byte a byte"
nuevo_home_codex
vendor_cx="$tmp/vendor-codex.sh"
printf '#!/usr/bin/env bash\n# fork codex del vendor, sin marcador propio\nexit 0\n' > "$vendor_cx"
cp "$vendor_cx" "$dest"
mani_cx="$tmp/manifiesto-codex.sha256"
{ cat "$manifiesto" 2>/dev/null; printf '%s  vendor codex sintetico del test\n' "$(sha256sum < "$vendor_cx" | cut -d' ' -f1)"; } > "$mani_cx"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --source "$fuente" --manifest "$mani_cx" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reemplazando vendor codex conocido, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el destino codex no quedo igual a la fuente"
bak_cx="$(find "$(dirname "$dest")" -type f -name '*.bak' 2>/dev/null | head -n 1)"
[ -n "$bak_cx" ] || malo "no dejo backup del vendor codex antes de reemplazarlo"
if [ -n "$bak_cx" ]; then
  cmp -s "$bak_cx" "$vendor_cx" || malo "el backup codex no tiene el contenido previo del destino"
fi

caso "codex: destino DESCONOCIDO => se planta, no escribe, y lo dice"
nuevo_home_codex
printf '#!/usr/bin/env bash\n# hook de otro en .codex, editado a mano\nexit 0\n' > "$dest"
antes_cx="$(sha256sum < "$dest")"
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --host codex --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "esperaba exit != 0 ante un destino codex desconocido, dio 0"
[ "$(sha256sum < "$dest")" = "$antes_cx" ] || malo "REESCRIBIO un destino codex desconocido"
printf '%s' "$out" | grep -qi 'desconocid' || malo "no reporta el estado desconocido en codex: $out"

caso "codex: --dest bajo <home>/.codex SIN --host codex => rechazado con la regla nueva"
nuevo_home_codex
out="$(HOME="$home_cx" USERPROFILE="$home_cx" bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un --dest bajo ~/.codex sin --host codex debe rechazarse, dio 0"
printf '%s' "$out" | grep -q -- '--host' || malo "el rechazo debe nombrar la regla del --host: $out"
[ ! -f "$dest" ] || malo "escribio bajo .codex sin --host codex"

caso "codex: el rechazo de ~/.zcode ya no afirma 'Una sola copia' (quedo falso con la copia codex)"
zc_dest="$tmp/zhome/.zcode/hooks/summonaikit-harness.sh"; mkdir -p "$(dirname "$zc_dest")"
out="$(HOME="$tmp/zhome" USERPROFILE="$tmp/zhome" bash "$tool" --dest "$zc_dest" --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "~/.zcode debe seguir rechazado, dio 0"
if printf '%s' "$out" | grep -qi 'Una sola copia'; then
  malo "el mensaje viejo ('Una sola copia...') quedo falso con la copia codex y debia reescribirse: $out"
fi
printf '%s' "$out" | grep -qi -- '--host' || malo "el rechazo debe explicar la regla nueva (el destino lo decide --host): $out"

# ================================================================ Task 7.5 — grok
# --host grok publica TRES cosas en orden (D1): (1) el hook por el flujo comun
# de 3 estados, (2) el JSON de registro propio ~/.grok/hooks/summonaikit.json
# (entero: ausente o nuestro => publicar; desconocido => PLANTARSE con CERO
# cambios), (3) los perfiles en ~/.grok/agents con frontmatter TRADUCIDO (la
# clave skills: como string no parsea en Grok — lo midio la 7.1). El PREFLIGHT
# clasifica TODO antes de escribir: hook o JSON desconocidos dejan intacto
# cualquier destino. Un agente desconocido NO aborta (D7): se instala el resto
# y se reporta. --quitar-grok retira solo lo nuestro con backup; el verifier
# ajeno del operador sobrevive.
n_grok=0
home_gk=''
gk_json=''
gk_agents=''
nuevo_home_grok() {
  n_grok=$((n_grok + 1))
  home_gk="$tmp/grok-home-$n_grok"
  gk_agents="$home_gk/.grok/agents"
  gk_json="$home_gk/.grok/hooks/summonaikit.json"
  mkdir -p "$home_gk/.grok/hooks" "$gk_agents"
  dest="$home_gk/.grok/hooks/summonaikit-harness.sh"
}
# bash.exe FALSO pero existente: la validacion del override exige un archivo
# real, y asi el command del JSON es determinista (no depende del PATH de la
# maquina ni de un Git real instalado).
bash_gk="$tmp/fake-bash.exe"
: > "$bash_gk"
host_grok() {
  HOME="$home_gk" USERPROFILE="$home_gk" \
  SAIKIT_GROK_BASH_WIN="$bash_gk" SAIKIT_GROK_AGENTS_DIR="$gk_agents" \
    bash "$tool" --host grok --source "$fuente" --manifest "$manifiesto" --no-registration-check "$@"
}

# La estructura del JSON canonico (D1, forma PowerShell medida en 7.1), dicha
# desde el test y no desde el instalador: eventos, matcher SOLO en PTU/PTUF,
# timeout 30 (Stop 600), env por handler y saikit_owned top-level. El command
# esperado viaja por ENV y no por argv: el python de Windows convierte las
# rutas POSIX de los argumentos (medido: /tmp/... llega como C:/...Temp/...) y
# la comparacion contra el contenido del JSON daria un falso por el motivo
# equivocado. Los valores de entorno no se convierten.
grok_json_asserts() {
  GROK_EXPECT_CMD="$(printf '& "%s" "%s"' "$bash_gk" "$dest")" \
  python - "$1" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert d["saikit_owned"] == "summonaikit-claude", "falta saikit_owned top-level"
h = d["hooks"]
assert set(h) == {"UserPromptSubmit","PostToolUse","PostToolUseFailure","SubagentStart","Stop"}, set(h)
cmd = os.environ["GROK_EXPECT_CMD"]
for fase, grupos in h.items():
    for g in grupos:
        if "matcher" in g:
            assert fase in ("PostToolUse", "PostToolUseFailure"), "matcher indebido en %s" % fase
        for e in g["hooks"]:
            assert e["type"] == "command", e
            assert e["command"] == cmd, "command: %r (esperaba %r)" % (e["command"], cmd)
            assert e["env"] == {"SUMMONAIKIT_HOOK_TARGET": "grok"}, e.get("env")
            assert e["timeout"] == (600 if fase == "Stop" else 30), (fase, e.get("timeout"))
assert h["PostToolUse"][0]["matcher"] == \
    "Bash|Edit|Write|apply_patch|Task|Agent|spawn_subagent|run_terminal_command|search_replace|write"
assert h["PostToolUseFailure"][0]["matcher"] == "Bash|run_terminal_command"
PY
}

# Como sin_temporales_sueltos, pero para el dir de hooks de grok: ahi el JSON
# de registro vive HERMANO del hook por diseño, no es un temporal.
sin_grok_temporales() {
  local n
  n="$(find "$(dirname "$1")" -maxdepth 1 -type f -name '.saikit-*' 2>/dev/null | wc -l)"
  [ "$n" -eq 0 ]
}

caso "grok: AUSENTE publica hook + JSON canonico + agentes (hook byte a byte)"
nuevo_home_grok
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el hook grok no quedo byte a byte igual a la fuente"
[ -f "$gk_json" ] || malo "no publico el JSON de registro"
grok_json_asserts "$gk_json" || malo "el JSON publicado no es el canonico del diseño (D1)"
sin_grok_temporales "$dest" || malo "dejo temporales sueltos junto al hook grok"
printf '%s' "$out" | grep -q 'REGISTRO GROK' || malo "no reporta la publicacion del JSON: $out"

# El caso que ATA la traduccion de frontmatter (D7 + 7.1: skills: como string
# no parsea en Grok) Y la inyeccion de model:/effort: (Task 12.5, Task 12.2
# midio que grok SI las honra). La copia instalada debe ser la fuente MENOS
# exactamente la linea skills: MAS exactamente las dos lineas model:/effort:
# que emite tools/model-routing.sh para ese rol — ni una linea de mas, ni de
# menos, en ninguna de las dos direcciones.
caso "grok: perfiles instalados = fuente MENOS skills: MAS model:/effort: del router"
for rol in implementer verifier reviewer adversary; do
  [ -f "$gk_agents/$rol.md" ] || { malo "falta $rol.md en ~/.grok/agents"; continue; }
  esperado_model="$(bash "$router" --host grok --role "$rol" --field model)"
  esperado_effort="$(bash "$router" --host grok --role "$rol" --field effort)"
  d_out="$(diff "$agentes_fuente/$rol.md" "$gk_agents/$rol.md")"
  [ "$(printf '%s' "$d_out" | grep -c '^<')" -eq 1 ] \
    || malo "$rol: la traduccion debe quitar EXACTAMENTE una linea: $d_out"
  printf '%s' "$d_out" | grep -q '^< skills: ' \
    || malo "$rol: la unica linea quitada debe ser skills: (no parsea en Grok)"
  [ "$(printf '%s' "$d_out" | grep -c '^>')" -eq 2 ] \
    || malo "$rol: la traduccion debe agregar EXACTAMENTE model:/effort: del router: $d_out"
  printf '%s' "$d_out" | grep -q "^> model: $esperado_model\$" \
    || malo "$rol: no inyecto el model: ruteado ($esperado_model): $d_out"
  printf '%s' "$d_out" | grep -q "^> effort: $esperado_effort\$" \
    || malo "$rol: no inyecto el effort: ruteado ($esperado_effort): $d_out"
  grep -Eq '^saikit_owned:[[:space:]]*summonaikit-claude[[:space:]]*$' "$gk_agents/$rol.md" \
    || malo "$rol.md instalado no lleva la marca saikit_owned"
  grep -q "^name: $rol\$" "$gk_agents/$rol.md" || malo "$rol.md no declara name: $rol"
done
printf '%s' "$out" | grep -q 'AGENTE GROK' || malo "no reporta los agentes instalados: $out"

caso "grok: adversary instalado lleva model:/effort: del router y NO skills: (13.8)"
# La fuente agents/adversary.md SI declara skills:; la traduccion 7.5 la
# omite en grok (el loader no la acepta como string). Los valores esperados
# se derivan del router REAL (tier review, fila grok medida en la 12.2) --
# los IDs de modelo viven solo en tools/model-routing.sh.
nuevo_home_grok
grep -q '^skills:' "$agentes_fuente/adversary.md" \
  || malo "la fuente agents/adversary.md deberia declarar skills: (premisa del caso)"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ -f "$gk_agents/adversary.md" ] || malo "no instalo adversary.md en ~/.grok/agents"
sed -n '/^---/,/^---/p' "$gk_agents/adversary.md" | grep -q '^skills:' \
  && malo "adversary.md en grok no debe llevar skills: en el frontmatter"
esp_model="$(bash "$router" --host grok --role adversary --field model)"
esp_effort="$(bash "$router" --host grok --role adversary --field effort)"
[ -n "$esp_model" ] || malo "la fila grok/adversary del router no deberia estar vacia"
grep -q "^model: ${esp_model}\$" "$gk_agents/adversary.md" \
  || malo "adversary.md no lleva el model: que emite el router ($esp_model)"
grep -q "^effort: ${esp_effort}\$" "$gk_agents/adversary.md" \
  || malo "adversary.md no lleva el effort: que emite el router ($esp_effort)"

caso "grok: adversary DESCONOCIDO no aborta el resto ni se pisa (13.8)"
nuevo_home_grok
printf '%s\n' '---' 'name: adversary' 'description: del operador' '---' '# adversary propio' \
  > "$gk_agents/adversary.md"
antes_sha="$(sha256sum < "$gk_agents/adversary.md")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un adversary desconocido NO aborta (D7), dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el hook tenia que instalarse igual"
[ -f "$gk_agents/reviewer.md" ] || malo "reviewer tenia que instalarse"
[ "$(sha256sum < "$gk_agents/adversary.md")" = "$antes_sha" ] \
  || malo "piso el adversary.md ajeno (D7: no se toca)"
printf '%s' "$out" | grep -qi 'desconocid' || malo "debe reportar el adversary desconocido: $out"

caso "grok: JSON DESCONOCIDO => exit != 0, hook NO publicado, CERO cambios"
nuevo_home_grok
printf '{ "hooks": { "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "echo ajeno" } ] } ] } }\n' > "$gk_json"
antes_sha="$(sha256sum < "$gk_json")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un JSON ajeno debe plantar (exit != 0), dio 0"
[ ! -e "$dest" ] || malo "publico el hook pese al JSON desconocido"
[ "$(sha256sum < "$gk_json")" = "$antes_sha" ] || malo "toco el JSON ajeno"
[ ! -e "$gk_agents/implementer.md" ] || malo "instalo agentes pese al JSON desconocido"
printf '%s' "$out" | grep -qi 'desconocid' || malo "no reporta el JSON desconocido: $out"

caso "grok: JSON que no parsea => DESCONOCIDO (existe y no es nuestro), exit != 0"
nuevo_home_grok
printf '{ roto\n' > "$gk_json"
antes_sha="$(sha256sum < "$gk_json")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un JSON ilegible debe plantar, dio 0"
[ ! -e "$dest" ] || malo "publico el hook pese al JSON ilegible"
[ "$(sha256sum < "$gk_json")" = "$antes_sha" ] || malo "toco el JSON ilegible"

caso "grok: JSON NO_OBSERVABLE (es un directorio) => unknown, exit != 0, sin escribir"
nuevo_home_grok
mkdir "$gk_json"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un JSON no observable debe plantar, dio 0"
printf '%s' "$out" | grep -qi 'unknown' || malo "Core Rule 2: lo no observable es unknown: $out"
[ ! -e "$dest" ] || malo "publico el hook sin poder clasificar el JSON"

caso "grok: agente DESCONOCIDO (el verifier del operador) => NO aborta: el resto se instala y se reporta"
nuevo_home_grok
printf '%s\n' '---' 'name: verifier' 'description: del operador' '---' '# verifier propio' > "$gk_agents/verifier.md"
antes_sha="$(sha256sum < "$gk_agents/verifier.md")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un agente desconocido NO aborta (D7), dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "el hook tenia que instalarse igual"
[ -f "$gk_json" ] || malo "el JSON tenia que publicarse igual"
[ -f "$gk_agents/implementer.md" ] || malo "implementer tenia que instalarse"
[ -f "$gk_agents/reviewer.md" ] || malo "reviewer tenia que instalarse"
[ "$(sha256sum < "$gk_agents/verifier.md")" = "$antes_sha" ] \
  || malo "piso el verifier.md ajeno (D7: no se toca)"
printf '%s' "$out" | grep -qi 'desconocid' || malo "debe reportar el agente desconocido: $out"

caso "grok: hook YA AL DIA igual publica el JSON y los agentes"
nuevo_home_grok
cp "$fuente" "$dest"
antes_mtime="$(mtime_de "$dest")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ "$(mtime_de "$dest")" = "$antes_mtime" ] || malo "reescribio el hook que ya estaba al dia"
[ -f "$gk_json" ] || malo "falta publicar el JSON cuando el hook ya esta al dia"
[ -f "$gk_agents/implementer.md" ] || malo "falta instalar agentes cuando el hook ya esta al dia"

caso "grok: NUESTRO_DISTINTO en hook y JSON => repara ambos con backup"
nuevo_home_grok
host_grok >/dev/null 2>&1
escribir_nuestro_viejo "$dest"
previo_hook="$(sha256sum < "$dest")"
printf '{ "saikit_owned": "summonaikit-claude", "hooks": {} }\n' > "$gk_json"
previo_json="$(sha256sum < "$gk_json")"
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0 reparando, dio $rc: $out"
cmp -s "$dest" "$fuente" || malo "no reparo el hook a la fuente"
grok_json_asserts "$gk_json" || malo "no reparo el JSON al canonico"
bakh="$(find "$home_gk/.grok/hooks/saikit-backups" -type f -name 'summonaikit-harness.sh*.bak' 2>/dev/null | head -n 1)"
[ -n "$bakh" ] || malo "reparo el hook sin backup"
[ -n "$bakh" ] && [ "$(sha256sum < "$bakh")" = "$previo_hook" ] \
  || malo "el backup del hook no conserva el contenido previo"
bakj="$(find "$home_gk/.grok/hooks/saikit-backups" -type f -name 'summonaikit.json*.bak' 2>/dev/null | head -n 1)"
[ -n "$bakj" ] || malo "republico el JSON sin backup"
[ -n "$bakj" ] && [ "$(sha256sum < "$bakj")" = "$previo_json" ] \
  || malo "el backup del JSON no conserva el contenido previo"

caso "grok: segunda corrida no reescribe NADA (mtime de hook, JSON y agente intactos)"
nuevo_home_grok
host_grok >/dev/null 2>&1
m_h="$(mtime_de "$dest")"; m_j="$(mtime_de "$gk_json")"; m_a="$(mtime_de "$gk_agents/implementer.md")"
sleep 1
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ "$(mtime_de "$dest")" = "$m_h" ] || malo "reescribio un hook identico"
[ "$(mtime_de "$gk_json")" = "$m_j" ] || malo "reescribio un JSON identico"
[ "$(mtime_de "$gk_agents/implementer.md")" = "$m_a" ] || malo "reescribio un agente identico"

caso "grok: --quitar-grok retira JSON+hook+agentes NUESTROS con backup; el verifier ajeno sobrevive"
nuevo_home_grok
host_grok >/dev/null 2>&1
printf '%s\n' '---' 'name: verifier' 'description: del operador' '---' '# verifier propio' > "$gk_agents/verifier.md"
ver_sha="$(sha256sum < "$gk_agents/verifier.md")"
out="$(host_grok --quitar-grok 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
[ ! -e "$gk_json" ] || malo "no retiro el JSON nuestro"
[ ! -e "$dest" ] || malo "no retiro el hook nuestro"
[ ! -e "$gk_agents/implementer.md" ] || malo "no retiro implementer.md (era nuestro)"
[ ! -e "$gk_agents/reviewer.md" ] || malo "no retiro reviewer.md (era nuestro)"
[ ! -e "$gk_agents/adversary.md" ] || malo "no retiro adversary.md (era nuestro)"
[ "$(sha256sum < "$gk_agents/verifier.md")" = "$ver_sha" ] \
  || malo "--quitar-grok toco el verifier ajeno"
[ -n "$(find "$home_gk/.grok/hooks/saikit-backups" -type f -name 'summonaikit.json*.bak' 2>/dev/null)" ] \
  || malo "quito el JSON sin backup"
[ -n "$(find "$home_gk/.grok/hooks/saikit-backups" -type f -name 'summonaikit-harness.sh*.bak' 2>/dev/null)" ] \
  || malo "quito el hook sin backup"
[ -n "$(find "$gk_agents" -type f -name 'implementer.md*.bak' 2>/dev/null)" ] \
  || malo "quito implementer.md sin backup"

caso "grok: sin bash.exe => exit 2 sin escribir nada"
nuevo_home_grok
out="$(HOME="$home_gk" USERPROFILE="$home_gk" \
       SAIKIT_GROK_BASH_WIN= SAIKIT_GROK_AGENTS_DIR="$gk_agents" \
       bash "$tool" --host grok --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "sin bash.exe debe salir 2, dio $rc: $out"
[ ! -e "$dest" ] || malo "sin bash.exe no debe publicar el hook"
[ ! -e "$gk_json" ] || malo "sin bash.exe no debe publicar el JSON"
[ ! -e "$gk_agents/implementer.md" ] || malo "sin bash.exe no debe instalar agentes"

caso "grok: fallo al publicar agentes => ROLLBACK de hook y JSON (exit 5, perfil como estaba)"
nuevo_home_grok
rm -rf "$gk_agents"
: > "$gk_agents"   # un ARCHIVO donde va el dir de agentes: la publicacion falla
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "el fallo de publicacion debe salir 5, dio $rc: $out"
[ ! -e "$dest" ] || malo "el hook publicado en esta corrida debia volver atras"
[ ! -e "$gk_json" ] || malo "el JSON publicado en esta corrida debia volver atras"
printf '%s' "$out" | grep -qi 'rollback' || malo "debe reportar el ROLLBACK: $out"

# r2/CodeRabbit: un agente publicado ANTES del fallo tambien vuelve atras —
# si no, el perfil queda a medio cablear (hook y JSON retirados, agente suelto
# que ningun flujo vuelve a mirar). El fallo se provoca en el archivado del
# SEGUNDO rol (saikit-backups como archivo), despues de que implementer ya se
# publico como AUSENTE.
caso "grok: fallo a MITAD de agentes => ROLLBACK tambien del agente ya publicado"
nuevo_home_grok
{
  printf '%s\n' '---'
  printf '%s\n' 'name: verifier'
  printf '%s\n' 'description: nuestro viejo'
  printf '%s\n' 'saikit_owned: summonaikit-claude'
  printf '%s\n' '---'
  printf '%s\n' '# verifier viejo'
} > "$gk_agents/verifier.md"
ver_previo_sha="$(sha256sum < "$gk_agents/verifier.md")"
: > "$gk_agents/saikit-backups"   # archivo donde va el dir de backups: archivar falla
out="$(host_grok 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "el fallo de publicacion debe salir 5, dio $rc: $out"
[ ! -e "$dest" ] || malo "el hook publicado en esta corrida debia volver atras"
[ ! -e "$gk_json" ] || malo "el JSON publicado en esta corrida debia volver atras"
[ ! -e "$gk_agents/implementer.md" ] \
  || malo "implementer se publico en ESTA corrida y el rollback debia retirarlo"
[ ! -e "$gk_agents/reviewer.md" ] \
  || malo "reviewer nunca se llego a publicar y no debe existir"
[ ! -e "$gk_agents/adversary.md" ] \
  || malo "adversary nunca se llego a publicar (va despues del punto de fallo) y no debe existir"
[ "$(sha256sum < "$gk_agents/verifier.md")" = "$ver_previo_sha" ] \
  || malo "verifier debia quedar intacto (el fallo fue ANTES de escribirlo)"
printf '%s' "$out" | grep -qi 'rollback' || malo "debe reportar el ROLLBACK: $out"
# r3/Greptile P1: el mensaje de exito del rollback solo se afirma cuando TODO
# volvio — con todo efectivamente restituido, la corrida lo dice.
printf '%s' "$out" | grep -q 'El perfil queda como estaba antes de la corrida' \
  || malo "el rollback completo debe afirmar que el perfil quedo como estaba: $out"

caso "grok: --dest bajo ~/.grok SIN --host grok => rechazado"
mkdir -p "$tmp/gk-guard/.grok/hooks"
gd="$tmp/gk-guard/.grok/hooks/summonaikit-harness.sh"
out="$(HOME="$tmp/gk-guard" USERPROFILE="$tmp/gk-guard" \
       bash "$tool" --dest "$gd" --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un --dest bajo ~/.grok sin --host grok debe rechazarse, dio 0"
printf '%s' "$out" | grep -q -- '--host' || malo "el rechazo debe nombrar la regla del --host: $out"
[ ! -f "$gd" ] || malo "escribio bajo ~/.grok sin --host grok"

caso "grok: --quitar-grok sin --host grok => exit 2"
out="$(bash "$tool" --quitar-grok 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--quitar-grok sin --host grok debe salir 2, dio $rc: $out"

# El aviso de registro es advisory (fail-open): con el install completo y
# canonico el verificador calla, asi que este caso solo ata que el cableado
# grok del aviso NO rompe la corrida ni mueve el exit code. Las TRES
# afirmaciones del verificador se atan en test_hook_registration.sh.
caso "grok: tras instalar corre el verificador de registro sin cambiar el exit code"
nuevo_home_grok
out="$(HOME="$home_gk" USERPROFILE="$home_gk" \
       SAIKIT_GROK_BASH_WIN="$bash_gk" SAIKIT_GROK_AGENTS_DIR="$gk_agents" \
       bash "$tool" --host grok --source "$fuente" --manifest "$manifiesto" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "el aviso de registro no debe cambiar el exit code (dio $rc): $out"

# ============================================================================
# Task 12.5 — traduccion por host generalizada + inyeccion de model:/effort:
# ============================================================================
# grok_agente_traducido() se generaliza a agente_traducido <host> <fuente>: la
# traduccion sigue omitiendo lo que el host no acepta (skills: en grok, Task
# 7.5) y ADEMAS inyecta model:/effort: del router (Task 12.4). zcode pasa a
# clasificar y publicar contra la plantilla TRADUCIDA (antes comparaba contra
# la cruda, Task 5.6): con inyeccion por host, comparar contra la cruda daria
# NUESTRO_DISTINTO en cada corrida y reescribiria el perfil siempre, con
# backup cada vez — el defecto que este cambio introduce si se hace a medias.
#
# Costura: router de prueba con las cuatro filas llenas, mismo mecanismo que
# SAIKIT_INSTALL_TOOL. Sin esto, si 12.1/12.2 dejaron alguna fila vacia (zcode:
# catalogo real de la cuenta NO OBSERVADO, docs/task-12.1-medicion.md), estos
# casos solo probarian la medicion, no la INYECCION.
router_stub="$tmp/router-stub.sh"
cat > "$router_stub" <<'STUB'
#!/usr/bin/env bash
set -u
host=''; role=''; format='json'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --format) format="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$format" = 'frontmatter' ] || exit 0
printf 'model: modelo-de-prueba-%s-%s\neffort: low\n' "$host" "$role"
STUB

host_zcode_stub() {
  SAIKIT_MODEL_ROUTING_TOOL="$router_stub" host_zcode "$@"
}

caso "12.5 zcode: el perfil instalado lleva el model/effort que emite el router"
dest_listo; nuevo_zcode_cfg
host_zcode_stub >/dev/null 2>&1
grep -q '^model: modelo-de-prueba-zcode-reviewer$' "$zcode_agents/reviewer.md" \
  || malo "el perfil de zcode no lleva el modelo ruteado"
grep -q '^effort: low$' "$zcode_agents/reviewer.md" \
  || malo "el perfil de zcode no lleva el effort ruteado"

caso "12.5 zcode: la inyeccion cae DENTRO del primer bloque frontmatter, una sola vez"
n="$(grep -c '^model: ' "$zcode_agents/reviewer.md")"
[ "$n" = "1" ] || malo "esperaba 1 linea model:, hay $n"
linea_model="$(grep -n '^model: ' "$zcode_agents/reviewer.md" | cut -d: -f1)"
linea_cierre="$(grep -n '^---' "$zcode_agents/reviewer.md" | sed -n 2p | cut -d: -f1)"
[ "$linea_model" -lt "$linea_cierre" ] || malo "model: cayo fuera del frontmatter"

caso "12.5 zcode: un --- EXTRA en el BODY no rompe: la inyeccion sigue cayendo UNA sola vez, antes del cierre REAL del frontmatter"
src_extra_dash="$tmp/agents-extra-dash"
mkdir -p "$src_extra_dash"
for rol in implementer verifier reviewer adversary; do
  {
    cat "$agentes_fuente/$rol.md"
    printf '\n---\n'
    printf 'Una linea de ejemplo con una raya --- que no es un cierre de frontmatter.\n'
  } > "$src_extra_dash/$rol.md"
done
dest_listo; nuevo_zcode_cfg
out_ed="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
          SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
          SAIKIT_ZCODE_AGENTS_SOURCE="$src_extra_dash" \
          SAIKIT_MODEL_ROUTING_TOOL="$router_stub" \
          bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc_ed=$?
[ "$rc_ed" -eq 0 ] || malo "esperaba exit 0, dio $rc_ed: $out_ed"
n_model_ed="$(grep -c '^model: ' "$zcode_agents/reviewer.md")"
[ "$n_model_ed" = "1" ] || malo "un --- extra en el body duplico la inyeccion: hay $n_model_ed lineas model:"
linea_model_ed="$(grep -n '^model: ' "$zcode_agents/reviewer.md" | cut -d: -f1)"
linea_cierre_ed="$(grep -n '^---' "$zcode_agents/reviewer.md" | sed -n 2p | cut -d: -f1)"
[ "$linea_model_ed" -lt "$linea_cierre_ed" ] \
  || malo "model: no cayo antes del cierre REAL del frontmatter (con un --- extra en el body)"
[ "$(grep -c '^---' "$zcode_agents/reviewer.md")" = "3" ] \
  || malo "el --- extra del body debia conservarse (apertura + cierre + la del body = 3)"

caso "12.5 zcode: agente_traducido descarta un thoughtLevel: preexistente de la fuente (no lo duplica) y usa el nombre de clave del router (Task 12.1)"
src_thoughtlevel="$tmp/agents-thoughtlevel"
mkdir -p "$src_thoughtlevel"
for rol in implementer verifier reviewer adversary; do
  awk '/^name: /{print; print "thoughtLevel: viejo-de-la-fuente"; next} {print}' \
    "$agentes_fuente/$rol.md" > "$src_thoughtlevel/$rol.md"
done
router_stub_tl="$tmp/router-stub-thoughtlevel.sh"
cat > "$router_stub_tl" <<'STUB'
#!/usr/bin/env bash
set -u
host=''; role=''; format='json'; field=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --format) format="$2"; shift 2 ;;
    --field) field="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$field" = 'effort-key' ]; then
  if [ "$host" = 'zcode' ]; then printf 'thoughtLevel\n'; else printf 'effort\n'; fi
  exit 0
fi
[ "$format" = 'frontmatter' ] || exit 0
if [ "$host" = 'zcode' ]; then
  printf 'model: modelo-de-prueba-zcode-%s\nthoughtLevel: nuevo-del-router\n' "$role"
else
  printf 'model: modelo-de-prueba-%s-%s\neffort: low\n' "$host" "$role"
fi
STUB
dest_listo; nuevo_zcode_cfg
out_tl="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
          SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
          SAIKIT_ZCODE_AGENTS_SOURCE="$src_thoughtlevel" \
          SAIKIT_MODEL_ROUTING_TOOL="$router_stub_tl" \
          bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc_tl=$?
[ "$rc_tl" -eq 0 ] || malo "esperaba exit 0, dio $rc_tl: $out_tl"
n_tl="$(grep -c '^thoughtLevel:' "$zcode_agents/reviewer.md")"
[ "$n_tl" = "1" ] \
  || malo "esperaba 1 sola linea thoughtLevel: (la del router, sin duplicar la de la fuente), hay $n_tl"
grep -q '^thoughtLevel: nuevo-del-router$' "$zcode_agents/reviewer.md" \
  || malo "el thoughtLevel: instalado no es el del router (debia reemplazar el de la fuente)"
if grep -q '^effort:' "$zcode_agents/reviewer.md"; then
  malo "zcode no debe llevar effort: -- la clave real que lee el parser es thoughtLevel: (Task 12.1)"
fi

caso "12.5 zcode: una fila de host vacia no inyecta ninguna clave (router real, zcode sin medir: docs/task-12.1-medicion.md)"
dest_listo; nuevo_zcode_cfg
host_zcode >/dev/null 2>&1   # router REAL, no el stub
if grep -q '^model:' "$zcode_agents/reviewer.md"; then
  malo "un host sin fila medida no debe llevar model:"
fi

caso "12.5 zcode: instalar dos veces seguidas NO reescribe (el defecto de comparar contra la cruda)"
dest_listo; nuevo_zcode_cfg
host_zcode_stub >/dev/null 2>&1
antes="$(find "$zcode_agents" -type f -print0 | sort -z | xargs -0 cksum)"
host_zcode_stub >/dev/null 2>&1
despues="$(find "$zcode_agents" -type f -print0 | sort -z | xargs -0 cksum)"
[ "$antes" = "$despues" ] || malo "la segunda corrida reescribio los perfiles"
[ -d "$zcode_agents/saikit-backups" ] && malo "la segunda corrida dejo un backup: esta reescribiendo"

caso "12.5 grok: sigue omitiendo skills: (traduccion de la 7.5, no se pierde) y SI lleva model: del router"
nuevo_home_grok
out_gk="$(SAIKIT_MODEL_ROUTING_TOOL="$router_stub" host_grok 2>&1)"; rc_gk=$?
[ "$rc_gk" -eq 0 ] || malo "esperaba exit 0, dio $rc_gk: $out_gk"
sed -n '/^---/,/^---/p' "$gk_agents/reviewer.md" | grep -q '^skills:' \
  && malo "grok no debe llevar skills: en el frontmatter"
grep -q '^model: modelo-de-prueba-grok-reviewer$' "$gk_agents/reviewer.md" \
  || malo "el perfil de grok no lleva el modelo ruteado"

# ============================================================================
# Task 12.6 — posesion en claude: manifiesto de vendor + --host claude
# ============================================================================
# El problema que resuelve: ~/.claude/agents/ lo escribe el CLI del kit y esos
# perfiles NO llevan saikit_owned, asi que la maquina de tres estados los deja
# DESCONOCIDO para siempre. La via de adopcion es el CUARTO estado
# VENDOR_CONOCIDO por hash en agents/vendor-manifest.sha256 (fixtures
# congelados en tests/fixtures/vendor-agents/, generados desde el perfil vivo
# del kit -- SOLO LECTURA, nunca se edita a mano ni se re-lee en el test).
claude_agents=''
n_ca=0
nuevo_claude_agents() {   # dir de agentes limpio por caso
  n_ca=$((n_ca + 1))
  claude_agents="$tmp/cagents-$n_ca"
  rm -rf "$claude_agents"; mkdir -p "$claude_agents"
}
host_claude() {
  SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" \
  SAIKIT_MODEL_ROUTING_TOOL="$router_stub" \
    bash "$tool" --host claude --dest "$dest" "$@"
}
# Variante con el router REAL, solo para el caso de cableado de punta a punta.
host_claude_real() {
  SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" bash "$tool" --host claude --dest "$dest" "$@"
}
# Copia un perfil del vendor congelado en fixtures al dir del caso.
poner_vendor() { cp "$repo/tests/fixtures/vendor-agents/$1.md" "$claude_agents/$1.md"; }

caso "claude: AUSENTE => instala con el modelo ruteado y la marca"
dest_listo; nuevo_claude_agents
out="$(host_claude 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, obtuve $rc: $out"
[ -f "$claude_agents/reviewer.md" ] || malo "no instalo reviewer.md"
grep -q '^model: modelo-de-prueba-claude-reviewer$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva el modelo que emitio el router"
grep -q '^effort: low$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva el effort que emitio el router"
grep -q '^saikit_owned: summonaikit-claude$' "$claude_agents/reviewer.md" \
  || malo "el perfil instalado no lleva la marca"

caso "claude: cableado de punta a punta con el router REAL"
# El valor esperado se le PREGUNTA al router, no se hardcodea: la regla global
# del plan es que los IDs de modelo viven solo en tools/model-routing.sh, y un
# test que los copie obliga a editar dos archivos cada vez que cambia la tabla.
dest_listo; nuevo_claude_agents
host_claude_real >/dev/null 2>&1
esperado_model="$(bash "$repo/tools/model-routing.sh" --host claude --role reviewer --field model)"
esperado_effort="$(bash "$repo/tools/model-routing.sh" --host claude --role reviewer --field effort)"
[ -n "$esperado_model" ] || malo "la fila claude del router no deberia estar vacia"
grep -q "^model: ${esperado_model}\$" "$claude_agents/reviewer.md" \
  || malo "el perfil no lleva el modelo que el router real emite ($esperado_model)"
grep -q "^effort: ${esperado_effort}\$" "$claude_agents/reviewer.md" \
  || malo "el perfil no lleva el effort que el router real emite ($esperado_effort)"

caso "claude: adversary instalado con la marca y el model:/effort: del router REAL (13.8)"
# adversary rutea al tier review (13.7): los valores esperados se le
# PREGUNTAN al router, igual que en el caso de reviewer de arriba -- los IDs
# de modelo viven solo en tools/model-routing.sh.
dest_listo; nuevo_claude_agents
out="$(host_claude_real 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, obtuve $rc: $out"
[ -f "$claude_agents/adversary.md" ] || malo "no instalo adversary.md"
grep -q '^saikit_owned: summonaikit-claude$' "$claude_agents/adversary.md" \
  || malo "adversary.md instalado no lleva la marca"
esp_model="$(bash "$router" --host claude --role adversary --field model)"
esp_effort="$(bash "$router" --host claude --role adversary --field effort)"
[ -n "$esp_model" ] || malo "la fila claude/adversary del router no deberia estar vacia"
grep -q "^model: ${esp_model}\$" "$claude_agents/adversary.md" \
  || malo "adversary.md no lleva el model: que el router real emite ($esp_model)"
grep -q "^effort: ${esp_effort}\$" "$claude_agents/adversary.md" \
  || malo "adversary.md no lleva el effort: que el router real emite ($esp_effort)"

caso "claude: adversary DESCONOCIDO no se toca, se reporta, y el resto se instala (13.8)"
# adversary es kit-owned y NO tiene entrada en agents/vendor-manifest.sha256:
# un adversary.md sin marca ni hash de vendor es DESCONOCIDO, no adoptable.
dest_listo; nuevo_claude_agents
printf -- '---\nname: adversary\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/adversary.md"
antes="$(cksum < "$claude_agents/adversary.md")"
out="$(host_claude 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "adversary DESCONOCIDO no debe abortar la corrida, dio $rc: $out"
[ "$antes" = "$(cksum < "$claude_agents/adversary.md")" ] \
  || malo "un adversary.md ajeno no se debe tocar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "no reporto el adversary DESCONOCIDO"
grep -q '^saikit_owned:' "$claude_agents/reviewer.md" \
  || malo "reviewer.md tenia que instalarse (solo adversary era ajeno)"

caso "claude: instalar dos veces NO reescribe"
# Desviacion declarada del plan: se agrega una primera instalacion propia con
# el MISMO router (host_claude / stub) antes de capturar "antes". El caso tal
# como esta en el plan reutiliza el $claude_agents del caso anterior, que
# quedo poblado con el router REAL (host_claude_real) -- comparar esa salida
# contra una segunda corrida con el router STUB siempre difiere (modelo/effort
# distintos) y el caso fallaria por una inconsistencia de fixture, no por un
# defecto de idempotencia. Mismo patron que "12.5 zcode: instalar dos veces
# seguidas NO reescribe": primero una instalacion propia y consistente, recien
# ahi se mide que la segunda no reescribe.
dest_listo; nuevo_claude_agents
host_claude >/dev/null 2>&1
antes="$(find "$claude_agents" -type f -print0 | sort -z | xargs -0 cksum)"
host_claude >/dev/null 2>&1
[ "$antes" = "$(find "$claude_agents" -type f -print0 | sort -z | xargs -0 cksum)" ] \
  || malo "la segunda corrida reescribio"

# Los TRES roles del manifiesto, uno por uno: el hash de cada linea de
# agents/vendor-manifest.sha256 tiene que ser adoptable, no solo el de
# reviewer -- un typo al generar (o un fixture re-guardado tras el
# sha256sum) en la linea de implementer o verifier dejaria ese rol
# DESCONOCIDO para siempre, en silencio, y ningun caso lo hubiera atrapado
# (hallazgo del review de PR #58).
for rol in implementer verifier reviewer; do
  caso "claude: VENDOR_CONOCIDO => archiva y reemplaza ($rol)"
  dest_listo; nuevo_claude_agents; poner_vendor "$rol"
  out="$(host_claude 2>&1)"
  grep -q '^saikit_owned:' "$claude_agents/$rol.md" || malo "no adopto el perfil del vendor ($rol)"
  ls "$claude_agents/saikit-backups/""$rol".md.vendor.*.bak >/dev/null 2>&1 \
    || malo "no archivo el perfil del vendor antes de pisarlo ($rol)"
  printf '%s' "$out" | grep -q 'ADOPTADO' || malo "no reporto la adopcion ($rol)"
done

caso "claude: DESCONOCIDO => no se toca, y se reporta"
dest_listo; nuevo_claude_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/reviewer.md"
antes="$(cksum < "$claude_agents/reviewer.md")"
out="$(host_claude 2>&1)"
[ "$antes" = "$(cksum < "$claude_agents/reviewer.md")" ] || malo "un perfil ajeno no se debe tocar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "no reporto el estado DESCONOCIDO"

caso "claude: closer y retro NO se tocan (la fuente cubre cuatro roles, ellos no son de los nuestros)"
dest_listo; nuevo_claude_agents; poner_vendor closer; poner_vendor retro
antes_closer="$(cksum < "$claude_agents/closer.md")"
antes_retro="$(cksum < "$claude_agents/retro.md")"
host_claude >/dev/null 2>&1
[ "$antes_closer" = "$(cksum < "$claude_agents/closer.md")" ] || malo "closer.md se toco"
[ "$antes_retro" = "$(cksum < "$claude_agents/retro.md")" ] || malo "retro.md se toco"

# Mismo blindaje que arriba, para el rechazo: los TRES roles tienen que
# quedar DESCONOCIDO (no solo reviewer) cuando su hash no figura en el
# manifiesto.
for rol in implementer verifier reviewer; do
  caso "claude: un hash que no esta en el manifiesto NO se adopta ($rol)"
  dest_listo; nuevo_claude_agents; poner_vendor "$rol"
  printf '\n' >> "$claude_agents/$rol.md"   # un byte de mas => otro hash
  antes="$(cksum < "$claude_agents/$rol.md")"
  out="$(host_claude 2>&1)"
  [ "$antes" = "$(cksum < "$claude_agents/$rol.md")" ] || malo "un vendor no listado no se debe pisar ($rol)"
  printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "un vendor no listado tiene que reportarse DESCONOCIDO ($rol)"
done

caso "claude: --host claude NO toca DEST"
dest_listo; nuevo_claude_agents
dest_ck="$(cksum < "$dest")"
host_claude >/dev/null 2>&1
[ "$dest_ck" = "$(cksum < "$dest")" ] || malo "--host claude no debe tocar DEST"

# --refrescar-manifiesto (Step 4b): reporta el hash + diff de un DESCONOCIDO,
# NUNCA adopta. El caso de test es que el manifiesto queda byte a byte igual.
caso "claude: --refrescar-manifiesto reporta el hash de un DESCONOCIDO y NO adopta (manifiesto intacto)"
dest_listo; nuevo_claude_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/reviewer.md"
manifiesto_antes="$(cksum < "$repo/agents/vendor-manifest.sha256")"
out="$(SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" \
       bash "$tool" --host claude --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--refrescar-manifiesto no deberia fallar solo por reportar: rc=$rc: $out"
manifiesto_hash="$(sha256sum "$claude_agents/reviewer.md" | cut -d' ' -f1)"
printf '%s' "$out" | grep -q "$manifiesto_hash" \
  || malo "--refrescar-manifiesto no imprimio el hash del perfil DESCONOCIDO"
[ "$manifiesto_antes" = "$(cksum < "$repo/agents/vendor-manifest.sha256")" ] \
  || malo "--refrescar-manifiesto NO debe escribir el manifiesto (solo reporta)"

caso "claude: --refrescar-manifiesto marca a adversary como kit-owned (su hash NO va al manifiesto) (grok r1 #3)"
# adversary es kit-owned y no tiene ni debe tener entrada de vendor: el
# reporte con hash+diff en el MISMO formato que los candidatos legitimos
# invitaba al operador a pegar un hash que, adoptado, dejaria al kit pisar
# un adversary.md ajeno como VENDOR_CONOCIDO. El reporte lleva la
# advertencia explicita.
dest_listo; nuevo_claude_agents
printf -- '---\nname: adversary\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/adversary.md"
manifiesto_antes="$(cksum < "$repo/agents/vendor-manifest.sha256")"
out="$(SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" \
       bash "$tool" --host claude --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--refrescar-manifiesto no deberia fallar por reportar adversary: rc=$rc: $out"
printf '%s' "$out" | grep -qi 'kit-owned' \
  || malo "el reporte del adversary DESCONOCIDO debe advertir que es kit-owned"
printf '%s' "$out" | grep -qi 'NO va al manifiesto' \
  || malo "el reporte del adversary debe decir que su hash NO va al manifiesto"
[ "$manifiesto_antes" = "$(cksum < "$repo/agents/vendor-manifest.sha256")" ] \
  || malo "--refrescar-manifiesto NO debe escribir el manifiesto (adversary)"

# ============================================================================
# Task 12.7 — posesion en kimi: --host kimi, alcance reducido por la 12.3
# ============================================================================
# El problema que resuelve: igual que ~/.claude/agents (12.6), kimi-code
# escribe ~/.agents/agents/ sin marca propia, y los tres perfiles quedarian
# DESCONOCIDO para siempre. Misma via de adopcion (CUARTO estado,
# VENDOR_CONOCIDO por hash), MISMO manifiesto (agents/vendor-manifest.sha256
# no es por-host: mapea hash -> rol). La 12.3 midio que kimi-code NO acepta
# `model:` ni `effort:` por agente (conjunto cerrado de claves), asi que esta
# tarea NO instala ruteo -- solo posesion + higiene (saca el model: sonnet
# inerte del vendor).
kimi_agents=''
n_ka=0
nuevo_kimi_agents() {
  n_ka=$((n_ka + 1))
  kimi_agents="$tmp/kagents-$n_ka"
  rm -rf "$kimi_agents"; mkdir -p "$kimi_agents"
}
host_kimi() {
  SAIKIT_KIMI_AGENTS_DIR="$kimi_agents" bash "$tool" --host kimi --dest "$dest" "$@"
}

caso "kimi: AUSENTE => instala con la marca, sin model:/effort: (fila vacia)"
dest_listo; nuevo_kimi_agents
out="$(host_kimi 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, obtuve $rc: $out"
[ -f "$kimi_agents/reviewer.md" ] || malo "no instalo reviewer.md"
grep -q '^saikit_owned: summonaikit-claude$' "$kimi_agents/reviewer.md" \
  || malo "el perfil instalado no lleva la marca"

caso "kimi: adversary instalado con la marca y SIN model:/effort: (13.8)"
# La fila kimi del router es vacia DEFINITIVA (12.3: el host no acepta ruteo
# por agente): el PERFIL de adversary si se instala, el ruteo no.
dest_listo; nuevo_kimi_agents
out="$(host_kimi 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, obtuve $rc: $out"
[ -f "$kimi_agents/adversary.md" ] || malo "no instalo adversary.md"
grep -q '^saikit_owned: summonaikit-claude$' "$kimi_agents/adversary.md" \
  || malo "adversary.md instalado no lleva la marca"
grep -q '^model:'  "$kimi_agents/adversary.md" && malo "kimi: adversary.md no debe llevar model:"
grep -q '^effort:' "$kimi_agents/adversary.md" && malo "kimi: adversary.md no debe llevar effort:"

caso "kimi: instalar dos veces NO reescribe"
dest_listo; nuevo_kimi_agents
host_kimi >/dev/null 2>&1
antes="$(find "$kimi_agents" -type f -print0 | sort -z | xargs -0 cksum)"
host_kimi >/dev/null 2>&1
[ "$antes" = "$(find "$kimi_agents" -type f -print0 | sort -z | xargs -0 cksum)" ] \
  || malo "la segunda corrida reescribio"

for rol in implementer verifier reviewer; do
  caso "kimi: VENDOR_CONOCIDO => archiva y reemplaza ($rol)"
  dest_listo; nuevo_kimi_agents
  cp "$repo/tests/fixtures/vendor-agents/$rol.md" "$kimi_agents/$rol.md"
  out="$(host_kimi 2>&1)"
  grep -q '^saikit_owned:' "$kimi_agents/$rol.md" || malo "no adopto el perfil del vendor ($rol)"
  ls "$kimi_agents/saikit-backups/""$rol".md.vendor.*.bak >/dev/null 2>&1 \
    || malo "no archivo el perfil del vendor antes de pisarlo ($rol)"
  printf '%s' "$out" | grep -q 'ADOPTADO' || malo "no reporto la adopcion ($rol)"
done

caso "kimi: DESCONOCIDO => no se toca, y se reporta"
dest_listo; nuevo_kimi_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$kimi_agents/reviewer.md"
antes="$(cksum < "$kimi_agents/reviewer.md")"
out="$(host_kimi 2>&1)"
[ "$antes" = "$(cksum < "$kimi_agents/reviewer.md")" ] || malo "un perfil ajeno no se debe tocar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "no reporto el estado DESCONOCIDO"

caso "kimi: adversary DESCONOCIDO no se toca y se reporta (13.8)"
dest_listo; nuevo_kimi_agents
printf -- '---\nname: adversary\ndescription: mio\n---\ncambio ajeno\n' > "$kimi_agents/adversary.md"
antes="$(cksum < "$kimi_agents/adversary.md")"
out="$(host_kimi 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "adversary DESCONOCIDO no debe abortar la corrida, dio $rc: $out"
[ "$antes" = "$(cksum < "$kimi_agents/adversary.md")" ] \
  || malo "un adversary.md ajeno no se debe tocar"
printf '%s' "$out" | grep -q 'DESCONOCIDO' || malo "no reporto el adversary DESCONOCIDO"
grep -q '^saikit_owned:' "$kimi_agents/reviewer.md" \
  || malo "reviewer.md tenia que instalarse (solo adversary era ajeno)"

caso "kimi: --host kimi NO toca DEST"
dest_listo; nuevo_kimi_agents
dest_ck="$(cksum < "$dest")"
host_kimi >/dev/null 2>&1
[ "$dest_ck" = "$(cksum < "$dest")" ] || malo "--host kimi no debe tocar DEST"

caso "kimi: al adoptar se saca el model: sonnet del vendor (higiene)"
# NO es la correccion de un defecto activo: la 12.3 midio que kimi ignora la
# clave `model` por completo, asi que ese valor es INERTE. Se saca porque el
# archivo afirma algo falso, no porque cambie el comportamiento.
dest_listo; nuevo_kimi_agents
cp "$repo/tests/fixtures/vendor-agents/reviewer.md" "$kimi_agents/reviewer.md"
grep -q '^model: sonnet$' "$kimi_agents/reviewer.md" \
  || malo "el fixture del vendor deberia traer model: sonnet (es lo que hay hoy en disco)"
host_kimi >/dev/null 2>&1
grep -q '^model: sonnet$' "$kimi_agents/reviewer.md" \
  && malo "sigue el model: sonnet del vendor despues de adoptar"

caso "kimi: el perfil instalado NO lleva model: ni effort:"
# La fila kimi del router esta vacia a proposito (12.3): el host no acepta esas
# claves. Escribirlas seria poner en el archivo algo que el runtime ignora --
# exactamente la mentira que el resto del spec persigue.
grep -q '^model:'  "$kimi_agents/reviewer.md" && malo "kimi no debe llevar model:"
grep -q '^effort:' "$kimi_agents/reviewer.md" && malo "kimi no debe llevar effort:"

caso "kimi: el frontmatter instalado SIGUE PARSEANDO (el tipo no puede desaparecer)"
# El modo de falla medido en la 12.3: un valor invalido en una clave conocida no
# da error -- el agente se cae del registro en silencio. Un test que solo mire
# que el archivo existe no lo atrapa. Se verifica contra el contrato del parser:
# claves permitidas y, si aparece model_preference, su valor.
#
# Gap del review de PR #59: este grep/sed no ejerce el parser REAL de kimi, y
# `saikit_owned:` (la UNICA clave que esta instalacion agrega al perfil) no
# esta en el conjunto cerrado que la 12.3 midio (name, description, whenToUse,
# override, tools, disallowedTools, subagents, model_preference). La 12.3 SI
# midio que una clave DESCONOCIDA (probo con model:/effort:) se ignora en
# silencio y el agente carga normal -- distinto de un VALOR INVALIDO en una
# clave CONOCIDA, que es lo que rompe el registro. saikit_owned cae en el
# primer caso (clave desconocida), pero nunca se habia probado esa clave en
# concreto. Medicion directa 2026-08-24 (adaptada de la 12.3, mismo binario
# kimi-code 0.34.0): se planto `~/.agents/agents/saikit-probe-127.md` con
# `name/description/tools` (subconjunto del set cerrado) MAS `saikit_owned:
# summonaikit-claude` -- un subconjunto representativo de la forma instalada
# (name/description/tools + saikit_owned; skills: queda cubierto por la
# observacion de la 12.3 sobre el vendor file, no por esta sonda) --
# y `kimi -p 'Delega al subagente saikit-probe-127...'` RESOLVIO el tipo y
# devolvio la respuesta esperada:
#   • Respuesta literal del subagente:
#     ```
#     PROBE-127-OK
#     ```
# Huella de ~/.agents y ~/.kimi-code (podada de contabilidad de runtime, misma
# lista de la 12.3) identica antes/despues; la sonda se borro al cerrar. Log
# completo y huella en el body del PR #59.
dest_listo; nuevo_kimi_agents
host_kimi >/dev/null 2>&1
for rol in implementer verifier reviewer adversary; do
  fm="$(sed -n '/^---/,/^---/p' "$kimi_agents/$rol.md" | sed '1d;$d')"
  printf '%s' "$fm" | grep -q "^name: ${rol}\$"   || malo "$rol: falta name: correcto"
  printf '%s' "$fm" | grep -q '^description:'     || malo "$rol: falta description (el parser la exige)"
  mp="$(printf '%s' "$fm" | sed -n 's/^model_preference: //p')"
  case "${mp:-primary}" in
    primary|secondary) ;;
    *) malo "$rol: model_preference invalido ($mp) — el agente desaparece del registro" ;;
  esac
done

caso "kimi: no se toca nada fuera de los cuatro roles"
dest_listo; nuevo_kimi_agents
printf 'ajeno\n' > "$kimi_agents/otro-agente.md"
mkdir -p "$kimi_agents/../skills" && printf 'ajeno\n' > "$kimi_agents/../skills/x.md"
antes_a="$(cksum < "$kimi_agents/otro-agente.md")"
antes_s="$(cksum < "$kimi_agents/../skills/x.md")"
host_kimi >/dev/null 2>&1
[ "$antes_a" = "$(cksum < "$kimi_agents/otro-agente.md")" ] || malo "un agente ajeno se toco"
[ "$antes_s" = "$(cksum < "$kimi_agents/../skills/x.md")" ] || malo "se toco algo fuera de agents/"

# ============================================================================
# Task 18.14 — agente_traducido bajo el awk BSD de macOS: DOS incompatibilidades
# ============================================================================
# Medido el 2026-09-02 en macOS (awk version 20200816, el unico del sistema):
#
#   (a) `local omitir='a^'` es un idiom de GNU awk. El awk BSD lo rechaza en la
#       compilacion del programa, ANTES de leer ninguna entrada:
#       "awk: syntax error in regular expression a^". Mata toda llamada, pero se
#       ve primero en la forma con inyectar VACIO (kimi, zcode).
#   (b) `awk -v inyectar=<valor de DOS lineas>`: el awk BSD rechaza el newline
#       literal del valor ANTES de compilar el programa:
#       "awk: newline in string ... at source line 1". Mata la forma con
#       inyectar MULTILINEA (claude, grok: model: + effort: del router).
#
# El DoD las discrimina por separado a proposito: un fix que arregle SOLO la
# regex (a) deja rota la forma multilinea (b) y pasa igual un gate que solo
# mire la forma kimi. Acreditacion declarada: estos casos acreditan en macOS
# (el awk BSD es el que rompe); en el CI Linux test_install_hook se saltea
# (tests/run.sh con SAIKIT_CI_LINUX=1), y el gawk de Linux aceptaba las dos
# formas viejas, asi que ahi estos casos no distinguen.
#
# Forma kimi: inyectar vacio con el router REAL (la fila de kimi es vacia,
# 12.3: el host no acepta ruteo por agente).
caso "18.14 (a) kimi: inyectar VACIO atraviesa el awk del sistema (sin 'syntax error in regular expression')"
dest_listo; nuevo_kimi_agents
out="$(host_kimi 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "kimi con inyectar vacio deberia instalar, dio $rc: $out"
printf '%s' "$out" | grep -q 'syntax error in regular expression' \
  && malo "el awk del sistema rechazo la regex nunca-match del omitir: $out"
[ -f "$kimi_agents/reviewer.md" ] || malo "no instalo reviewer.md"
grep -q '^saikit_owned: summonaikit-claude$' "$kimi_agents/reviewer.md" \
  || malo "el perfil kimi instalado no lleva la marca"

# Forma claude/grok: inyectar de DOS lineas (model: + effort:) via el stub de
# la 12.5, que emite exactamente esa forma para todos los hosts.
caso "18.14 (b) claude: inyectar MULTILINEA (model: + effort:) atraviesa el awk del sistema (sin 'newline in string')"
dest_listo; nuevo_claude_agents
out="$(host_claude 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "claude con inyectar multilinea deberia instalar, dio $rc: $out"
printf '%s' "$out" | grep -q 'newline in string' \
  && malo "el awk del sistema rechazo el valor multilinea del inyectar: $out"
linea_model_1814="$(grep -n '^model: modelo-de-prueba-claude-reviewer$' "$claude_agents/reviewer.md" | cut -d: -f1)"
linea_effort_1814="$(grep -n '^effort: low$' "$claude_agents/reviewer.md" | cut -d: -f1)"
[ -n "$linea_model_1814" ] || malo "falta el model: del router en el perfil claude instalado"
[ -n "$linea_effort_1814" ] || malo "falta el effort: del router en el perfil claude instalado"
if [ -n "$linea_model_1814" ] && [ -n "$linea_effort_1814" ]; then
  linea_cierre_1814="$(grep -n '^---' "$claude_agents/reviewer.md" | sed -n 2p | cut -d: -f1)"
  [ "$linea_model_1814" -lt "$linea_cierre_1814" ] || malo "el model: inyectado cayo fuera del frontmatter"
  [ "$linea_effort_1814" -lt "$linea_cierre_1814" ] || malo "el effort: inyectado cayo fuera del frontmatter"
fi

# FIXTURE que discrimina el fix ingenuo: cambiar `a^` por `^$` (otra regex que
# "no matchea nada" en GNU awk) matchea las lineas VACIAS y se las comeria del
# frontmatter, porque el omitir solo aplica con n == 1 (dentro del primer
# bloque). Los perfiles reales del repo (agents/*.md) no tienen lineas vacias
# ahi, asi que este fixture es lo unico que distingue el fix correcto del
# ingenuo. Corre por la via zcode porque es la unica con costura de fuente
# (SAIKIT_ZCODE_AGENTS_SOURCE); el bash.exe de Windows se resuelve con el
# override de medicion (SAIKIT_ZCODE_BASH_WIN), y el router stub emite cero
# lineas de frontmatter: la forma con inyectar VACIO, igual que la de kimi.
src_linea_vacia="$tmp/agents-linea-vacia"
mkdir -p "$src_linea_vacia"
for rol in implementer verifier reviewer adversary; do
  {
    printf -- '---\n'
    printf 'name: %s\n' "$rol"
    printf 'description: fixtura 18.14 con linea vacia\n'
    printf '\n'
    printf 'saikit_owned: summonaikit-claude\n'
    printf -- '---\n'
    printf 'cuerpo del %s\n' "$rol"
  } > "$src_linea_vacia/$rol.md"
done
router_stub_vacio="$tmp/router-stub-vacio.sh"
cat > "$router_stub_vacio" <<'STUB'
#!/usr/bin/env bash
set -u
format='json'; field=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --format) format="$2"; shift 2 ;;
    --field) field="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$field" = 'effort-key' ]; then printf 'effort\n'; exit 0; fi
[ "$format" = 'frontmatter' ] || exit 0
# Cero lineas: la forma de inyectar vacio (kimi/zcode).
exit 0
STUB
bash_win_1814="$tmp/18.14-fake-bash.exe"
: > "$bash_win_1814"

caso "18.14 fixture: una linea vacia DENTRO del frontmatter sobrevive a la traduccion (descarta el fix ingenuo a^ -> ^$)"
dest_listo; nuevo_zcode_cfg
out="$(SAIKIT_ZCODE_USER_CONFIG="$zcode_cfg" \
       SAIKIT_ZCODE_AGENTS_DIR="$zcode_agents" \
       SAIKIT_ZCODE_AGENTS_SOURCE="$src_linea_vacia" \
       SAIKIT_ZCODE_BASH_WIN="$bash_win_1814" \
       SAIKIT_MODEL_ROUTING_TOOL="$router_stub_vacio" \
       bash "$tool" --host zcode --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "zcode con el fixture de linea vacia deberia instalar, dio $rc: $out"
# Con inyectar vacio y nada que omitir/desechar, la traduccion es la identidad:
# el instalado debe ser byte-a-byte la fuente, linea vacia incluida.
cmp -s "$src_linea_vacia/reviewer.md" "$zcode_agents/reviewer.md" \
  || malo "la linea vacia dentro del frontmatter no sobrevivio (el instalado difiere de la fuente)"

# ============================================================================
# Task 12.9 — correcciones del cross-review externo (codex + grok, 1 ronda)
# ============================================================================
# Los 7 hallazgos con caso propio: instalacion a medias (#1), NO_OBSERVABLE
# confundido con DESCONOCIDO en el manifiesto de agentes (#2), lookup
# multi-hash roto (#3), --dry-run ignorado en claude/kimi (#4), rc de
# agente_traducido ignorado en grok (#5), --refrescar-manifiesto sin via para
# kimi (#6) y el --help incompleto (#7). #8 y #9 son declaraciones (README y
# Plans.md), sin caso de test.

caso "12.9 #1 (codex): NO_OBSERVABLE en el ULTIMO rol no deja los tres primeros publicados (instalacion a medias)"
dest_listo; nuevo_claude_agents
# grok r1 #2 (cross-review del PR #66): el NO_OBSERVABLE va plantado en el
# ULTIMO rol de CLAUDE_AGENT_ROLES (adversary desde la 13.8), no en el
# tercero — con el fallo en el rol 3, adversary iba DESPUES del punto de
# fallo y ni el bucle mixto viejo lo habria escrito: la asercion no
# discriminaba nada. Con el fallo en el ULTIMO rol, los tres anteriores
# estan AUSENTES y publicarian si el bucle clasificara-y-publicara en el
# mismo paso.
mkdir -p "$claude_agents/adversary.md"
out="$(host_claude 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "esperaba exit 5 (NO_OBSERVABLE), dio $rc: $out"
[ -e "$claude_agents/implementer.md" ] && malo "implementer.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (instalacion a medias)"
[ -e "$claude_agents/verifier.md" ] && malo "verifier.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (instalacion a medias)"
[ -e "$claude_agents/reviewer.md" ] && malo "reviewer.md quedo instalado pese al NO_OBSERVABLE del ultimo rol (instalacion a medias)"

caso "12.9 #2 (codex+grok): sha256 no calculable en el manifiesto de agentes => NO_OBSERVABLE (exit 5), NUNCA DESCONOCIDO silencioso"
# sha256sum FALSO que siempre falla: command -v lo encuentra (existe y es
# ejecutable), pero no puede calcular el hash. Reusa sha_de()/hash_en_manifiesto()
# como pide el hallazgo: "no se pudo mirar" no es lo mismo que "se miro y no
# esta" (Core Rule 2, ya vale para el manifiesto del HOOK y tiene que valer
# igual para el de agentes).
fake_sha_dir="$tmp/fake-sha-no-observable"
mkdir -p "$fake_sha_dir"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fake_sha_dir/sha256sum"
chmod +x "$fake_sha_dir/sha256sum"
dest_listo; nuevo_claude_agents; poner_vendor reviewer
out="$(PATH="$fake_sha_dir:$PATH" host_claude 2>&1)"; rc=$?
[ "$rc" -eq 5 ] || malo "un sha256 no calculable deberia dar NO_OBSERVABLE (exit 5), dio $rc: $out"
printf '%s' "$out" | grep -qi 'desconocid' && malo "no observable no debe reportarse como DESCONOCIDO (Core Rule 2)"
[ -e "$claude_agents/implementer.md" ] && malo "instalo implementer.md pese a que el manifiesto de agentes no se pudo consultar para reviewer"

caso "12.9 #3 (codex): manifiesto con DOS hashes para el MISMO rol adopta el que coincide (lookup multi-hash)"
dest_listo; nuevo_claude_agents; poner_vendor reviewer
printf '\n' >> "$claude_agents/reviewer.md"   # variante del vendor: un hash DISTINTO al que ya esta en el manifiesto
segundo_hash="$(sha256sum "$claude_agents/reviewer.md" | cut -d' ' -f1)"
manifest_path="$repo/agents/vendor-manifest.sha256"
MANIFEST_AGENTES_BACKUP="$tmp/vendor-manifest-backup.sha256"
cp "$manifest_path" "$MANIFEST_AGENTES_BACKUP"
printf '%s  reviewer.md\n' "$segundo_hash" >> "$manifest_path"
out="$(host_claude 2>&1)"; rc=$?
restaurar_manifiesto_agentes
MANIFEST_AGENTES_BACKUP=''
printf '%s' "$out" | grep -q 'ADOPTADO' \
  || malo "un manifiesto con DOS hashes de reviewer no adopto el segundo (lookup multi-hash roto): $out"
grep -q '^saikit_owned:' "$claude_agents/reviewer.md" \
  || malo "no adopto el perfil pese al segundo hash presente en el manifiesto"

caso "12.9 #4 (grok): --dry-run en --host claude no escribe nada y reporta por rol"
dest_listo; nuevo_claude_agents
out="$(host_claude --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run (claude) no deberia fallar: $out"
for rol in implementer verifier reviewer adversary; do
  [ -e "$claude_agents/$rol.md" ] && malo "dry-run (claude) escribio $rol.md"
done
printf '%s' "$out" | grep -qi 'dry-run' || malo "dry-run (claude) no reporto lo que haria"

caso "12.9 #4 (grok): --dry-run en --host kimi no escribe nada"
dest_listo; nuevo_kimi_agents
out="$(host_kimi --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run (kimi) no deberia fallar: $out"
[ -e "$kimi_agents/implementer.md" ] && malo "dry-run (kimi) escribio implementer.md"
[ -e "$kimi_agents/adversary.md" ] && malo "dry-run (kimi) escribio adversary.md"
printf '%s' "$out" | grep -qi 'dry-run' || malo "dry-run (kimi) no reporto lo que haria"

caso "13.9 (adversary r1 vivo): --dry-run en --host zcode NO escribe nada — ni agentes ni registro ni backup"
# Rojo medido EN VIVO: durante el deploy de 13.9, una corrida `--host zcode
# --dry-run` de verificacion dejo un backup real del user-config
# (config.json.zcode.20260825-102205.bak) — el dispatch de zcode nunca miro
# DRY_RUN (el 12.9 #4 solo cubrio claude/kimi). Un dry-run que escribe es
# la mentira exacta que el README prohibe.
dest_listo; nuevo_zcode_cfg
cfg_antes="$(cksum < "$zcode_cfg")"
out="$(host_zcode --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run (zcode) esperaba exit 0, dio $rc: $out"
[ "$cfg_antes" = "$(cksum < "$zcode_cfg")" ] || malo "dry-run (zcode) ESCRIBIO el user-config"
[ -e "$zcode_agents/adversary.md" ] && malo "dry-run (zcode) escribio adversary.md"
[ -e "$zcode_agents/implementer.md" ] && malo "dry-run (zcode) escribio implementer.md"
[ -n "$(find "$(dirname "$zcode_cfg")/saikit-backups" -type f 2>/dev/null)" ] \
  && malo "dry-run (zcode) dejo backup del config"
printf '%s' "$out" | grep -qi 'dry-run' || malo "dry-run (zcode) no reporto lo que haria"

caso "12.9 #5 (grok): agente_traducido fallando (router roto) NO pisa el perfil grok existente"
router_break="$tmp/router-break.sh"
cat > "$router_break" <<'STUB'
#!/usr/bin/env bash
set -u
format='json'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --format) format="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$format" = 'frontmatter' ]; then
  printf 'router kaboom\n' >&2
  exit 1
fi
exit 0
STUB
nuevo_home_grok
mkdir -p "$gk_agents"
printf -- '---\nname: reviewer\ndescription: mio\nsaikit_owned: summonaikit-claude\n---\nperfil existente\n' > "$gk_agents/reviewer.md"
antes="$(cksum < "$gk_agents/reviewer.md")"
out="$(SAIKIT_MODEL_ROUTING_TOOL="$router_break" host_grok 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "el router roto deberia hacer fallar la instalacion (rc de agente_traducido ignorado), dio 0"
[ "$antes" = "$(cksum < "$gk_agents/reviewer.md")" ] \
  || malo "el perfil grok existente se piso con el router roto (rc de agente_traducido ignorado)"

caso "12.9 #6 (grok): --refrescar-manifiesto acepta --host kimi (mismo modo reporta-jamas-adopta)"
dest_listo; nuevo_kimi_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$kimi_agents/reviewer.md"
manifiesto_antes="$(cksum < "$repo/agents/vendor-manifest.sha256")"
out="$(SAIKIT_KIMI_AGENTS_DIR="$kimi_agents" bash "$tool" --host kimi --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--refrescar-manifiesto (kimi) no deberia fallar solo por reportar: rc=$rc: $out"
manifiesto_hash="$(sha256sum "$kimi_agents/reviewer.md" | cut -d' ' -f1)"
printf '%s' "$out" | grep -q "$manifiesto_hash" \
  || malo "--refrescar-manifiesto (kimi) no imprimio el hash del perfil DESCONOCIDO"
[ "$manifiesto_antes" = "$(cksum < "$repo/agents/vendor-manifest.sha256")" ] \
  || malo "--refrescar-manifiesto (kimi) NO debe escribir el manifiesto (solo reporta)"

caso "12.9 #6-b (greptile, inline en el PR #62): --refrescar-manifiesto con sha256sum roto reporta unknown por rol, NUNCA salta mudo con exit 0 silencioso"
# Mismo defecto que el fix #2 (arriba) pero en el path de REFRESCO:
# refrescar_manifiesto_vendor() calculaba el hash con un `sha256sum "$dest"`
# suelto, sin pasar por sha_de()/sha_bin -- en un sistema con `shasum` y sin
# `sha256sum` (o con AMBOS rotos, como este fake_sha_dir simula), el `[ -n
# "$hash" ] || continue` original saltaba el rol EN SILENCIO y el
# procedimiento entero salia 0 sin haber reportado nada, pese a que el
# proposito del flag es justo que un humano VEA el hash de cada DESCONOCIDO.
dest_listo; nuevo_claude_agents
printf -- '---\nname: reviewer\ndescription: mio\n---\ncambio ajeno\n' > "$claude_agents/reviewer.md"
out="$(PATH="$fake_sha_dir:$PATH" SAIKIT_CLAUDE_AGENTS_DIR="$claude_agents" \
       bash "$tool" --host claude --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--refrescar-manifiesto no deberia fallar solo porque un hash no se pueda calcular: rc=$rc: $out"
printf '%s' "$out" | grep -qi 'unknown' \
  || malo "un sha256 no calculable en el refresco debe reportarse (unknown), no saltarse mudo"
printf '%s' "$out" | grep -q 'reviewer' \
  || malo "el reporte de unknown en el refresco no menciona el rol afectado (reviewer)"

caso "12.9 #7 (grok): --help lista --host claude y --refrescar-manifiesto"
out="$(bash "$tool" --help 2>&1)"
printf '%s' "$out" | grep -q -- '--host claude' || malo "el --help no lista --host claude"
printf '%s' "$out" | grep -q -- '--refrescar-manifiesto' || malo "el --help no lista --refrescar-manifiesto"

# ----------------------------------------------------------------------------
# Followups de la revision interna del PR #62 (no bloqueantes, mismo push)
# ----------------------------------------------------------------------------

caso "12.9 followup (revision interna): --refrescar-manifiesto sin --host valido (claude/kimi) => exit 2"
out="$(bash "$tool" --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--refrescar-manifiesto sin --host deberia dar exit 2, dio $rc: $out"
out="$(bash "$tool" --host zcode --refrescar-manifiesto --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--refrescar-manifiesto --host zcode (host valido pero sin via de refresco) deberia dar exit 2, dio $rc: $out"

caso "12.9 followup (revision interna): --dry-run sobre dest_dir INEXISTENTE (claude) no lo crea"
dest_listo
inexistente="$tmp/cagents-dry-inexistente"
rm -rf "$inexistente"
out="$(SAIKIT_CLAUDE_AGENTS_DIR="$inexistente" SAIKIT_MODEL_ROUTING_TOOL="$router_stub" \
       bash "$tool" --host claude --dry-run --dest "$dest" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run sobre dest_dir inexistente no deberia fallar: rc=$rc: $out"
[ -e "$inexistente" ] && malo "dry-run creo el dest_dir que no existia (mkdir -p bajo --dry-run)"

caso "12.9 followup (revision interna): --dry-run sobre VENDOR_CONOCIDO no escribe ni archiva"
dest_listo; nuevo_claude_agents; poner_vendor reviewer
antes="$(cksum < "$claude_agents/reviewer.md")"
out="$(host_claude --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run sobre VENDOR_CONOCIDO no deberia fallar: rc=$rc: $out"
[ "$antes" = "$(cksum < "$claude_agents/reviewer.md")" ] || malo "dry-run sobre VENDOR_CONOCIDO modifico el archivo"
[ -d "$claude_agents/saikit-backups" ] && malo "dry-run sobre VENDOR_CONOCIDO creo un backup"
printf '%s' "$out" | grep -qi 'VENDOR CONOCIDO' || malo "dry-run sobre VENDOR_CONOCIDO no reporto el estado"

caso "12.9 followup (revision interna): --dry-run sobre NUESTRO_DISTINTO no escribe ni archiva"
dest_listo; nuevo_claude_agents
host_claude >/dev/null 2>&1
printf '\nlinea distinta\n' >> "$claude_agents/reviewer.md"
antes="$(cksum < "$claude_agents/reviewer.md")"
out="$(host_claude --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dry-run sobre NUESTRO_DISTINTO no deberia fallar: rc=$rc: $out"
[ "$antes" = "$(cksum < "$claude_agents/reviewer.md")" ] || malo "dry-run sobre NUESTRO_DISTINTO modifico el archivo"
[ -d "$claude_agents/saikit-backups" ] && malo "dry-run sobre NUESTRO_DISTINTO creo un backup"
printf '%s' "$out" | grep -qi 'NUESTRO distinto' || malo "dry-run sobre NUESTRO_DISTINTO no reporto el estado"

# ===================================================== Phase 15 — --host dsh
# dsh publica CUATRO cosas (D5): hook + plugin + patch del profile + personas.
# El home dsh de test se aísla con SAIKIT_DSH_HOME (como SAIKIT_GROK_HOOKS_DIR),
# y el bash.exe con SAIKIT_DSH_BASH_WIN (un archivo vacio existente basta para
# pasar la validacion del override; el command del patch debe ser ese).
bash_dsh="$tmp/fake-bash.exe"
: > "$bash_dsh"
n_dsh=0
nuevo_home_dsh() {
  n_dsh=$((n_dsh + 1))
  # home_dh ES el .dsh del test (raiz que SAIKIT_DSH_HOME apunta).
  home_dh="$tmp/dsh-home-$n_dsh/.dsh"
  mkdir -p "$home_dh"
  dest="$home_dh/hooks/summonaikit-harness.sh"
  # El plugin vive en el flat module fallback (dsh resuelve los plugins custom
  # por nombre ahi), no en <dsh-home>/plugins/ (PR #91: el turno vivo).
  dsh_plugin="$home_dh/profiles/node_modules/@summonaikit/dsh-gate"
  dsh_patch="$home_dh/cordis.patch.yml"
}
host_dsh() {
  SAIKIT_DSH_HOME="$home_dh" SAIKIT_DSH_BASH_WIN="$bash_dsh" \
    bash "$tool" --host dsh --source "$fuente" --manifest "$manifiesto" --no-registration-check "$@"
}
# El instalador dsh escribe name:/hook: en forma WINDOWS (C:/...) porque dsh
# (Node) los lee. El test usa rutas POSIX ($dest/$dsh_plugin sobre $tmp); para
# comparar contra el patch hay que convertirlas (PR #91: el turno vivo revelo
# que sin esto el instalador escribia /c/ y los greps de la suite no coincidian).
dsh_win() {  # $1=ruta POSIX/Windows -> forma Windows con barra adelante
  if command -v cygpath >/dev/null 2>&1; then
    case "$1" in
      [A-Za-z]:/*) printf '%s' "$1" ;;
      [A-Za-z]:\\*) printf '%s' "$1" | sed 's|\\|/|g' ;;
      *) printf '%s' "$(cygpath -m "$1" 2>/dev/null || printf '%s' "$1")" ;;
    esac
  else
    printf '%s' "$1"
  fi
}

caso "dsh: instala hook + plugin + patch entre marcas + 4 personas (limpio)"
nuevo_home_dsh
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh install deberia salir 0, dio $rc: $out"
[ -f "$dest" ] || malo "dsh no instalo el hook en $dest"
printf '%s' "$out" | grep -qi 'INSTALADO' || malo "dsh install no reporta INSTALADO"
[ -f "$dsh_plugin/package.json" ] || malo "dsh no instalo el package.json del plugin"
[ -f "$dsh_plugin/index.js" ] || malo "dsh no instalo index.js del plugin"
[ -f "$dsh_plugin/translate.js" ] || malo "dsh no instalo translate.js del plugin"
[ -f "$dsh_plugin/spawn-hook.js" ] || malo "dsh no instalo spawn-hook.js del plugin"
[ -f "$dsh_patch" ] || malo "dsh no instalo el patch del profile"
for rol in implementer verifier reviewer adversary; do
  grep -q "toolName: subagent_$rol" "$dsh_patch" || malo "al patch dsh le falta la persona subagent_$rol"
done
grep -q "hook: '$(dsh_win "$dest")'" "$dsh_patch" || malo "la entrada del patch no apunta al hook"
printf '%s' "$out" | grep -qi 'PATCH DSH INSTALADO' || malo "dsh install no reporta PATCH DSH INSTALADO"

caso "dsh: --dry-run no escribe nada (ni hook ni plugin ni patch ni backups)"
nuevo_home_dsh
out="$(host_dsh --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh --dry-run deberia salir 0, dio $rc: $out"
[ ! -e "$dest" ] || malo "dsh --dry-run escribio el hook"
[ ! -e "$dsh_patch" ] || malo "dsh --dry-run escribio el patch del profile"
[ -d "$dsh_plugin" ] && malo "dsh --dry-run creo el dir del plugin"
printf '%s' "$out" | grep -qi 'dry-run' || malo "dsh --dry-run no reporta dry-run"

caso "dsh: patch con contenido ajeno fuera de marcas se respeta byte a byte"
nuevo_home_dsh
host_dsh >/dev/null 2>&1
# Un array ficticio con contenido del operador ANTES y DESPUES de nuestras marcas.
pre="$tmp/dsh-pre-$n_dsh.txt"; post="$tmp/dsh-post-$n_dsh.txt"
printf -- '- insert:\n    - id: otromodulo\n      name: '\''algo-del-operator'\''\n' > "$pre"
printf -- '- insert:\n    - id: otromodulo2\n      name: '\''algo2'\''\n' > "$post"
cat "$pre" "$dsh_patch" "$post" > "$dsh_patch.tmp" && mv "$dsh_patch.tmp" "$dsh_patch"
# Reinstalar: el splice debe conservar AMBOS bloques ajenos intactos y refrescar
# el nuestro, sin pegar lineas en las fronteras (HIGH r1 PR #88).
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "reinstall dsh con contenido ajeno deberia salir 0, dio $rc: $out"
grep -q "id: otromodulo" "$dsh_patch" || malo "el reinstall dsh perdio el contenido ajeno ANTERIOR"
grep -q "id: otromodulo2" "$dsh_patch" || malo "el reinstall dsh perdio el contenido ajeno POSTERIOR"
grep -q "id: summonaikit-gate" "$dsh_patch" || malo "el reinstall dsh no refresco nuestro bloque"
# Byte a byte: ninguna marca pegada a una linea ajena (el YAML se corrompe ahi).
# Frontera START: la ultima linea ajena pegada a la marca START.
grep -q 'algo-del-operator# >>>' "$dsh_patch" && malo "splice pego la linea ajena ANTERIOR a la marca START"
# Frontera END (la VULNERABLE): la marca END pegada a la PRIMERA linea ajena
# posterior (que es '- insert:' del bloque post). 'algo2' esta DOS lineas mas
# abajo, asi que buscarla no detecta el pegamento (§qwen r1 PR #88).
grep -q 'summonaikit-gate END- insert' "$dsh_patch" && malo "splice pego la marca END a la primera linea ajena posterior"
rm -f "$pre" "$post"

caso "dsh: --dry-run sobre hook AU AL DIA (NUESTRO_IDENTICO) NO toca plugin/patch"
nuevo_home_dsh
host_dsh >/dev/null 2>&1
out="$(host_dsh --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh --dry-run con hook al dia deberia salir 0, dio $rc: $out"
# El plugin y el patch ya existen del install previo; el dry-run no debe tocarlos.
[ -f "$dsh_plugin/package.json" ] || malo "el dry-run no debe borrar el plugin"
[ "$(cksum < "$dsh_plugin/index.js")" = "$(cksum < "$repo/hosts/dsh/index.js")" ] || malo "dry-run modifico index.js"

caso "dsh: --dry-run --quitar-dsh NO borra nada"
nuevo_home_dsh
host_dsh >/dev/null 2>&1
out="$(host_dsh --dry-run --quitar-dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh --dry-run --quitar-dsh deberia salir 0, dio $rc: $out"
[ -f "$dest" ] || malo "--dry-run --quitar-dsh borro el hook"
[ -d "$dsh_plugin" ] || malo "--dry-run --quitar-dsh borro el plugin"
[ -f "$dsh_patch" ] || malo "--dry-run --quitar-dsh borro el patch"
printf '%s' "$out" | grep -qi 'dry-run' || malo "dry-run --quitar-dsh no reporta dry-run"

caso "dsh: un dir de plugin ajeno (sin saikit_owned) NO se toca entero"
nuevo_home_dsh
# El dir del plugin existe con un package.json ajeno (sin marcador) y archivos distintos.
mkdir -p "$dsh_plugin"
printf -- '{"name":"otro-plugin","version":"1.0"}\n' > "$dsh_plugin/package.json"
printf 'ajeno\n' > "$dsh_plugin/index.js"
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "dir de plugin ajeno deberia hacer fallar (DESCONOCIDO), dio 0: $out"
[ "$(cat "$dsh_plugin/package.json")" = '{"name":"otro-plugin","version":"1.0"}' ] || malo "se toco el package.json ajeno"
[ "$(cat "$dsh_plugin/index.js")" = 'ajeno' ] || malo "se toco el index.js ajeno"
# HIGH grok/qwen r1 PR #88: el fallo del plugin NO debe publicar el patch (que
# quedaria apuntando al plugin ajeno/inexistente) ni dejar el hook instalado.
[ ! -e "$dsh_patch" ] || malo "el fallo del plugin dsh publico el patch (cableado a un plugin ajeno)"
[ ! -e "$dest" ] || malo "el fallo del plugin dsh dejo el hook instalado (sin rollback)"

caso "dsh: dir de plugin existente SIN package.json (ajeno) NO se pisa"
nuevo_home_dsh
# Un dir con archivos pero sin package.json: no lleva marcador, es de otro o
# quedo a medio instalar; NO se debe escribir dentro (M4/qwen r1 PR #88).
mkdir -p "$dsh_plugin"
printf 'ajeno-index\n' > "$dsh_plugin/index.js"
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "dir sin package.json deberia hacer fallar (DESCONOCIDO), dio 0: $out"
[ "$(cat "$dsh_plugin/index.js")" = 'ajeno-index' ] || malo "se sobrescribio el index.js ajeno de un dir sin package.json"

caso "dsh: fallo del plugin en install FRESCO NO publica el patch ni deja el hook (HIGH grok/qwen r1 PR #88)"
nuevo_home_dsh
# El dir del plugin es ajeno: el plugin falla; el hook esta AUSENTE (fresh).
mkdir -p "$dsh_plugin"
printf -- '{"name":"otro-plugin","version":"1.0"}\n' > "$dsh_plugin/package.json"
printf 'ajeno\n' > "$dsh_plugin/index.js"
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "install con plugin ajeno deberia fallar, dio 0: $out"
# HIGH grok/qwen: el fallo del plugin NO debe publicar el patch (quedaria
# apuntando al plugin ajeno/inexistente) ni dejar el hook instalado a medias.
[ ! -e "$dsh_patch" ] || malo "el fallo del plugin publico el patch (cableado a plugin ajeno/inexistente)"
[ ! -e "$dest" ] || malo "el fallo del plugin dejo el hook instalado sin rollback"
[ "$(cat "$dsh_plugin/package.json")" = '{"name":"otro-plugin","version":"1.0"}' ] || malo "el rollback toco el package.json ajeno"

caso "dsh: repara hook y plugin viejos con backup"
nuevo_home_dsh
host_dsh >/dev/null 2>&1
# Envejecer el hook y un archivo del plugin (marcador presente => NUESTRO_DISTINTO).
printf '\n# envejecido\n' >> "$dest"
printf 'x' >> "$dsh_plugin/index.js"
out="$(host_dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh reinstall no deberia fallar sobre NUESTRO_DISTINTO, dio $rc: $out"
[ -d "$(dirname "$dest")/saikit-backups" ] || malo "dsh no dejo backup del hook reparado"
[ "$(cksum < "$dsh_plugin/index.js")" = "$(cksum < "$repo/hosts/dsh/index.js")" ] || malo "dsh no reparo index.js del plugin"

caso "dsh: --quitar-dsh deja el patch sin nuestra entrada y el hook+plugin retirados"
nuevo_home_dsh
host_dsh >/dev/null 2>&1
out="$(host_dsh --quitar-dsh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "dsh --quitar-dsh deberia salir 0, dio $rc: $out"
[ ! -f "$dest" ] || malo "--quitar-dsh no retiro el hook"
[ ! -d "$dsh_plugin" ] || malo "--quitar-dsh no retiro el plugin"
if [ -f "$dsh_patch" ]; then
  grep -q "summonaikit-gate START" "$dsh_patch" && malo "--quitar-dsh dejo la entrada entre marcas"
fi
[ -d "$(dirname "$dest")/saikit-backups" ] || malo "--quitar-dsh no dejo backup del hook"

caso "dsh: --quitar-dsh sin --host dsh => exit 2"
out="$(bash "$tool" --quitar-dsh 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "--quitar-dsh sin --host dsh deberia salir 2, dio $rc: $out"

caso "dsh: sin bash.exe => exit 2 y nada escrito"
nuevo_home_dsh
out="$(SAIKIT_DSH_HOME="$home_dh" SAIKIT_DSH_BASH_WIN= \
       bash "$tool" --host dsh --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || malo "dsh sin bash.exe deberia salir 2, dio $rc: $out"
[ ! -e "$dsh_patch" ] || malo "dsh sin bash.exe no debe tocar el patch"

caso "dsh: patch usa name:=paquete y hook: en forma WINDOWS (C:/), no POSIX (/c/) (turno vivo, PR #91)"
# El turno vivo revelo que: (a) el name: por ruta (C:/...) no lo importa dsh
# (ERR_UNSUPPORTED_ESM_URL_SCHEME / DIR_IMPORT) — debe ser el nombre del paquete
# linkeado en el fallback; (b) el hook: (ruta que el plugin lee) debe ser Windows,
# no /c/. En MSYS $tmp es POSIX; con cygpath el instalador convierte hook: a C:/.
nuevo_home_dsh
if command -v cygpath >/dev/null 2>&1; then
  host_dsh >/dev/null 2>&1
  grep -qF "name: '@summonaikit/dsh-gate'" "$dsh_patch" || malo "el patch no usa name: de paquete (@summonaikit/dsh-gate): $(grep -E 'name:' "$dsh_patch" | head -2)"
  grep -qE "hook: '[A-Za-z]:/" "$dsh_patch" || malo "el patch no usa hook: en forma Windows (PR #91): $(grep -E 'hook:' "$dsh_patch" | head -2)"
  grep -q "/c/" "$dsh_patch" && malo "el patch dejo una ruta POSIX /c/ (dsh Node no la resuelve)"
  # El plugin vive como dir REAL en el fallback (no symlink; MSYS ln -s no crea
  # symlinks reales). Debe tener los 4 archivos y resolverse por nombre.
  [ -f "$dsh_plugin/index.js" ] && [ -f "$dsh_plugin/package.json" ] || malo "no se publico el plugin en el fallback de dsh ($dsh_plugin)"
fi

# ============================================================================
# Task 16.5 — el instalador planta el recetario y /sencillo (host claude)
# ============================================================================
# El recetario vive en <hookdir>/recetas y la skill en $HOME/.claude/skills/
# sencillo/SKILL.md. Cada caso estrena su propio HOME (los casos del flujo por
# defecto ya comparten $tmp/.claude/skills) para que "limpio" y "dos corridas"
# midan el estado real del skill y no lo que dejo otro caso. Core Rule 4: nada
# toca el `~/.claude` real.
n_rc=0
casa_recetas=''
nuevo_casa_recetas() {
  n_rc=$((n_rc + 1))
  # La raiz del HOME sandbox (sin .claude: el tool lo agrega como $HOME/.claude).
  # NO se pre-crea .claude/skills a proposito: el caso "limpio" es un PERFIL
  # FRESCO, y el instalador tiene que crear el padre de la skill (16.5). Si el
  # util no lo creara, ese caso fallaria — atado, no asumido.
  casa_recetas="$tmp/casa-recetas-$n_rc"
}
host_claude_recetas() {
  HOME="$casa_recetas" USERPROFILE="$casa_recetas" \
  SAIKIT_CLAUDE_AGENTS_DIR="$casa_recetas/agents" \
    bash "$tool" --host claude --dest "$dest" --source "$fuente" --manifest "$manifiesto" "$@"
}

caso "recetario: limpio => recetas/ + 7 recetas + skill byte a byte iguales"
nuevo_destino; nuevo_casa_recetas
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install limpio de recetas deberia salir 0, dio $rc: $out"
[ -f "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "no planto el manifiesto de recetas"
cmp -s "$(dirname "$dest")/recetas/MANIFEST.sha256" "$repo/recetas/MANIFEST.sha256" \
  || malo "el manifiesto instalado difiere del fuente"
for f in "$repo"/recetas/*.md; do
  b="$(basename "$f")"
  [ -f "$(dirname "$dest")/recetas/$b" ] || malo "no planto $b"
  cmp -s "$(dirname "$dest")/recetas/$b" "$f" || malo "$b instalado difiere del fuente"
done
[ -f "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "no planto skills/sencillo/SKILL.md"
cmp -s "$casa_recetas/.claude/skills/sencillo/SKILL.md" "$repo/skills/sencillo/SKILL.md" \
  || malo "la skill instalada difiere del fuente"

caso "recetario: dos corridas seguidas NO reescriben (mtime intacto, sin backup nuevo)"
nuevo_destino; nuevo_casa_recetas
host_claude_recetas >/dev/null 2>&1
# 16.5 (cross-review, hilo test-vacio): antes `stat -c '%y' ... 2>/dev/null` daba
# cadena VACIA ante cualquier fallo y el caso comparaba "" contra "" (verde sin
# haber medido nada, incluso si el archivo nunca se instalo); y `find` sobre un
# dir inexistente daba 0, y 0=0 pasaba igual. Se exige que los valores medidos NO
# esten vacios y que el directorio y los archivos existan ANTES de comparar.
[ -d "$(dirname "$dest")/recetas" ] || malo "recetas/ no existe: no se puede medir el mtime ni contar backups"
[ -f "$(dirname "$dest")/recetas/bug.md" ] || malo "bug.md no se instalo: no se puede medir el mtime"
[ -f "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "la skill no se instalo: no se puede medir el mtime"
rc_m="$(mtime_de "$(dirname "$dest")/recetas/bug.md")"
sk_m="$(mtime_de "$casa_recetas/.claude/skills/sencillo/SKILL.md")"
n_bak="$(find "$(dirname "$dest")/recetas" -name '*.bak' 2>/dev/null | wc -l)"
[ -n "$rc_m" ] || malo "mtime de bug.md vacio (stat fallo o archivo ausente)"
[ -n "$sk_m" ] || malo "mtime de la skill vacio (stat fallo o archivo ausente)"
sleep 1
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "segunda corrida deberia salir 0, dio $rc: $out"
[ "$(mtime_de "$(dirname "$dest")/recetas/bug.md")" = "$rc_m" ] \
  || malo "la segunda corrida reescribio bug.md"
[ "$(mtime_de "$casa_recetas/.claude/skills/sencillo/SKILL.md")" = "$sk_m" ] \
  || malo "la segunda corrida reescribio la skill"
[ "$(find "$(dirname "$dest")/recetas" -name '*.bak' 2>/dev/null | wc -l)" = "$n_bak" ] \
  || malo "la segunda corrida creo un backup"

# ============================================================================
# Task 17.6 — el instalador planta la skill `saikit-verificar-app`
# ============================================================================
# La skill de 17.1 vive en $HOME/.claude/skills/saikit-verificar-app/ y son DOS
# archivos (SKILL.md + verificar.sh), no uno como /sencillo. La medicion viva de
# 17.5 la copio A MANO a los labs porque el instalador no la plantaba: sin eso,
# el comando que `agents/verifier.md` enseña no existe en el repo del usuario.
caso "17.6: limpio => planta saikit-verificar-app (SKILL.md + verificar.sh) byte a byte"
nuevo_destino; nuevo_casa_recetas
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "install limpio deberia salir 0, dio $rc: $out"
for b in SKILL.md verificar.sh; do
  [ -f "$casa_recetas/.claude/skills/saikit-verificar-app/$b" ] \
    || malo "no planto saikit-verificar-app/$b"
  cmp -s "$casa_recetas/.claude/skills/saikit-verificar-app/$b" \
    "$repo/skills/saikit-verificar-app/$b" \
    || malo "saikit-verificar-app/$b instalado difiere del fuente"
done

caso "17.6: un verificar.sh NUESTRO con deriva se REPARA (un .sh sin marca quedaba DESCONOCIDO)"
# El generador es un .sh, no un .md: su propiedad se mide con la MISMA marca
# `saikit_owned` del resto del kit, en un bloque no-op al inicio que ES el
# frontmatter que lee el instalador. Sin esa marca, el archivo que el kit MISMO
# planto se clasificaba DESCONOCIDO y no se actualizaba nunca — un generador
# viejo escribiendo `verify/` para siempre, y en silencio.
nuevo_destino; nuevo_casa_recetas
host_claude_recetas >/dev/null 2>&1
sk_v="$casa_recetas/.claude/skills/saikit-verificar-app/verificar.sh"
[ -f "$sk_v" ] || malo "precondicion: verificar.sh no se instalo; el caso no mide nada"
printf '\n# deriva local\n' >> "$sk_v"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "la reparacion deberia salir 0, dio $rc: $out"
cmp -s "$sk_v" "$repo/skills/saikit-verificar-app/verificar.sh" \
  || malo "verificar.sh NO se reparo: quedo la deriva local (se clasifico DESCONOCIDO)"

caso "17.6: un verificar.sh AJENO (sin marca) no se toca y se reporta"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$casa_recetas/.claude/skills/saikit-verificar-app"
aj_v="$casa_recetas/.claude/skills/saikit-verificar-app/verificar.sh"
printf '#!/usr/bin/env bash\n# generador de otra persona\n' > "$aj_v"
prev_aj="$(cat "$aj_v")"
out="$(host_claude_recetas 2>&1)"
[ "$(cat "$aj_v")" = "$prev_aj" ] || malo "piso un verificar.sh ajeno (sin marca)"
printf '%s' "$out" | grep -q 'DESCONOCIDO' \
  || malo "no reporto el verificar.sh ajeno como DESCONOCIDO: $out"

caso "17.6: --dry-run no crea la skill saikit-verificar-app"
nuevo_destino; nuevo_casa_recetas
host_claude_recetas --dry-run >/dev/null 2>&1
[ ! -e "$casa_recetas/.claude/skills/saikit-verificar-app" ] \
  || malo "--dry-run creo saikit-verificar-app"

caso "17.6: --quitar-recetas borra los dos archivos propios de saikit-verificar-app"
nuevo_destino; nuevo_casa_recetas
host_claude_recetas >/dev/null 2>&1
# La precondicion cubre los DOS archivos (CodeRabbit, PR #136): con solo
# SKILL.md, un install que no publicara verificar.sh dejaba la asercion de
# ausencia de abajo pasando EN VACIO — el caso diria "quitado" sin que nada se
# hubiera instalado.
for b in SKILL.md verificar.sh; do
  [ -f "$casa_recetas/.claude/skills/saikit-verificar-app/$b" ] \
    || malo "precondicion: $b no se instalo; el quitar no mide nada"
done
host_claude_recetas --quitar-recetas >/dev/null 2>&1
[ ! -f "$casa_recetas/.claude/skills/saikit-verificar-app/SKILL.md" ] \
  || malo "--quitar-recetas no quito saikit-verificar-app/SKILL.md"
[ ! -f "$casa_recetas/.claude/skills/saikit-verificar-app/verificar.sh" ] \
  || malo "--quitar-recetas no quito saikit-verificar-app/verificar.sh"

# 16.5 (cross-review, hilo manifiesto ajeno): el manifiesto se reemplaza SIEMPRE
# al instalar (no lleva marca; si gana un manifiesto viejo/ajeno, nuestras recetas
# recien plantadas no aparecerian en el menu) y el anterior queda respaldado — es
# la asimetria DELIBERADA que recetas_clasificar declara frente a la regla de
# propiedad que si aplica quitar_recetas_claude. El caso ata esa conducta.
caso "recetario: un manifiesto distinto se reemplaza al instalar y el previo queda respaldado"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas"
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\treceta\tbug\tfull\tViejo manifiesto ajeno\n' > "$(dirname "$dest")/recetas/MANIFEST.sha256"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un manifiesto distinto no debe abortar la instalacion, dio $rc: $out"
cmp -s "$(dirname "$dest")/recetas/MANIFEST.sha256" "$repo/recetas/MANIFEST.sha256" \
  || malo "el manifiesto distinto NO se reemplazo por el nuestro (nuestras recetas no aparecerian en el menu)"
[ -n "$(find "$(dirname "$dest")/recetas/saikit-backups" -name 'MANIFEST.sha256*.nuestro.*.bak' 2>/dev/null)" ] \
  || malo "el manifiesto previo no quedo respaldado en saikit-backups/"

caso "recetario: archivo ajeno (sin marca) en recetas/ queda intacto y se reporta; las nuestras se instalan"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas"
printf -- '---\nname: ajena\ndescription: de otro\n---\ncambio ajeno\n' > "$(dirname "$dest")/recetas/ajena.md"
antes="$(cksum < "$(dirname "$dest")/recetas/ajena.md")"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "un archivo ajeno no debe abortar la instalacion, dio $rc: $out"
[ "$antes" = "$(cksum < "$(dirname "$dest")/recetas/ajena.md")" ] || malo "se toco la receta ajena ajena.md"
printf '%s' "$out" | grep -q 'ajeno' || malo "no reporto la receta ajena: $out"
cmp -s "$(dirname "$dest")/recetas/bug.md" "$repo/recetas/bug.md" || malo "las recetas propias no se instalaron"

# cross-review grok r4 #2: el bucle de "ajenos" decidia SOLO por "no existe en el
# repo", sin mirar la marca — y eso no mide propiedad. Una receta NUESTRA
# retirada en una version posterior del kit lleva `saikit_owned`, y
# `--quitar-recetas` SI la borra porque ese lado si mira la marca: anunciarla
# como "ajena, intacta" contradecia al desinstalador y afirmaba una propiedad
# que nadie observo. El caso planta las DOS a la vez para que el mensaje tenga
# que distinguirlas.
caso "recetario: una receta NUESTRA retirada del kit no se anuncia como ajena"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas"
# retirada del kit: lleva la marca, pero ya no existe en el repo
printf -- '---\nsaikit_owned: summonaikit-claude\nnombre: vieja\ntitulo: Receta retirada\ncarril: full\n---\ncuerpo\n' \
  > "$(dirname "$dest")/recetas/vieja.md"
# ajena de verdad: sin marca y sin correlato en el repo
printf -- '---\nname: ajena\ndescription: de otro\n---\ncambio ajeno\n' \
  > "$(dirname "$dest")/recetas/ajena.md"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "no debe abortar la instalacion, dio $rc: $out"
[ -e "$(dirname "$dest")/recetas/vieja.md" ] || malo "la receta retirada se borro; el instalador solo reporta"
printf '%s' "$out" | grep -q 'retirada del kit' \
  || malo "una receta con la marca debe reportarse como retirada del kit, no como ajena: $out"
printf '%s' "$out" | grep -q 'archivo ajeno reportado, intacto: .*vieja.md' \
  && malo "una receta CON marca no puede anunciarse como ajena (contradice a --quitar-recetas): $out"
printf '%s' "$out" | grep -q 'archivo ajeno reportado, intacto: .*ajena.md' \
  || malo "la receta sin marca si debe reportarse como ajena: $out"

caso "recetario: --dry-run no crea recetas/ ni la skill, reporta por archivo"
nuevo_destino; nuevo_casa_recetas
out="$(host_claude_recetas --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--dry-run deberia salir 0, dio $rc: $out"
[ ! -e "$(dirname "$dest")/recetas" ] || malo "--dry-run creo recetas/"
[ ! -e "$casa_recetas/.claude/skills/sencillo" ] || malo "--dry-run creo /sencillo"
printf '%s' "$out" | grep -q 'recetario' || malo "--dry-run no reporta el recetario: $out"

caso "recetario: destino receta NO_OBSERVABLE => exit != 0 y NADA publicado (todo-o-nada, 12.9)"
# Precedente 12.9: se clasifica TODO antes de publicar. Un destino de receta
# convertido en DIRECTORIO no es un archivo legible: agente_estado_con_vendor lo
# clasifica NO_OBSERVABLE y recetas_publicar_dir aborta ANTES de publicar nada.
# (chmod 000 no vuelve ilegible a un archivo en MSYS: el ACL sigue otorgando
# lectura, medido; el directorio es el disparador confiable de NO_OBSERVABLE.)
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas/bug.md"
out="$(host_claude_recetas 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un destino NO_OBSERVABLE deberia salir != 0, dio 0: $out"
[ ! -e "$(dirname "$dest")/recetas/00-lider.md" ] || malo "se publico una receta pese al NO_OBSERVABLE"
[ -d "$(dirname "$dest")/recetas/bug.md" ] || malo "se toco el destino NO_OBSERVABLE (bug.md)"

caso "recetario: --quitar-recetas borra SOLO lo nuestro (marca) + el manifiesto; lo ajeno queda"
nuevo_destino; nuevo_casa_recetas
host_claude_recetas >/dev/null 2>&1
printf -- '---\nname: ajena\ndescription: de otro\n---\ncambio ajeno\n' > "$(dirname "$dest")/recetas/ajena.md"
antes="$(cksum < "$(dirname "$dest")/recetas/ajena.md")"
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas deberia salir 0, dio $rc: $out"
[ ! -e "$(dirname "$dest")/recetas/bug.md" ] || malo "--quitar-recetas no quito bug.md (nuestra)"
[ ! -e "$(dirname "$dest")/recetas/00-lider.md" ] || malo "--quitar-recetas no quito 00-lider.md (nuestra)"
[ "$antes" = "$(cksum < "$(dirname "$dest")/recetas/ajena.md")" ] || malo "--quitar-recetas toco ajena.md"
[ -e "$(dirname "$dest")/recetas/ajena.md" ] || malo "--quitar-recetas borro ajena.md (ajena)"
[ ! -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "--quitar-recetas no quito el manifiesto (todos los nombrados eran nuestros)"
[ ! -e "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "--quitar-recetas no quito skills/sencillo/SKILL.md"
printf '%s' "$out" | grep -q 'ajeno, intacto' || malo "--quitar-recetas no reporto ajena.md como ajeno intacto: $out"

# Revision (reviewer, MEDIUM): el dispatch de --quitar-recetas tenia que estar
# tambien en el flujo POR DEFECTO (sin --host, el del hook claude). Antes el
# flag, sin --host, caia al camino de instalacion y REINSTALABA el recetario.
caso "recetario: --quitar-recetas por el flujo por defecto (sin --host) quita y NO reinstala"
nuevo_destino; nuevo_casa_recetas
out="$(HOME="$casa_recetas" USERPROFILE="$casa_recetas" bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" --no-registration-check 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "instalar por el flujo por defecto deberia salir 0, dio $rc: $out"
[ -e "$(dirname "$dest")/recetas/bug.md" ] || malo "el flujo por defecto no instalo recetas/"
out="$(HOME="$casa_recetas" USERPROFILE="$casa_recetas" bash "$tool" --dest "$dest" --source "$fuente" --manifest "$manifiesto" --no-registration-check --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas (flujo por defecto) deberia salir 0, dio $rc: $out"
[ ! -e "$(dirname "$dest")/recetas/bug.md" ] || malo "--quitar-recetas (flujo por defecto) no quito bug.md"
[ ! -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "--quitar-recetas (flujo por defecto) no quito el manifiesto"
[ ! -e "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "--quitar-recetas (flujo por defecto) no quito la skill"

# 16.5 (cross-review codex, P2): --dry-run --quitar-recetas NO borra y NO debe
# decir "quitado" (un dry-run que miente entrena a confiar); debe decir
# "se quitara (dry-run)" y dejar los archivos.
caso "recetario: --dry-run --quitar-recetas NO borra y NO dice 'quitado'"
nuevo_destino; nuevo_casa_recetas
host_claude_recetas >/dev/null 2>&1   # instala
out="$(host_claude_recetas --quitar-recetas --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas --dry-run deberia salir 0, dio $rc: $out"
[ -e "$(dirname "$dest")/recetas/bug.md" ] || malo "--dry-run --quitar-recetas borro bug.md"
[ -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "--dry-run --quitar-recetas borro el manifiesto"
[ -e "$casa_recetas/.claude/skills/sencillo/SKILL.md" ] || malo "--dry-run --quitar-recetas borro la skill"
printf '%s' "$out" | grep -q 'quitado' && malo "--quitar-recetas --dry-run NO debe decir 'quitado': $out"
printf '%s' "$out" | grep -q 'se quitara' || malo "--quitar-recetas --dry-run debe decir 'se quitara (dry-run)': $out"

# 16.5 (cross-review codex-16.5-r2, hallazgo 3): un manifiesto vacio (o que no
# nombre ninguna receta nuestra PRESENTE) no es atribuible al kit y NO se borra
# con --quitar-recetas. Antes el bucle de propiedad lo saltaba todo, "nuestro"
# quedaba 1 y se borraba de forma vacua.
caso "recetario: un manifiesto no-atribuible (vacio) NO se borra al quitar"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas"
: > "$(dirname "$dest")/recetas/MANIFEST.sha256"   # manifiesto vacio
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas con manifiesto vacio deberia salir 0, dio $rc: $out"
[ -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "un manifiesto vacio NO se borra (no es atribuible al kit)"
printf '%s' "$out" | grep -qi 'no es atribuible\|intacto' || malo "debe reportar el manifiesto como no atribuible: $out"

# 16.5 (cross-review grok, hallazgo 1): la misma regla de nombre seguro del hook
# y del checker vale al QUITAR. Un `nombre` con traversal (../blanco) no debe
# usarse como ruta ni sesgar la propiedad del manifiesto. Sin el guard, un
# hooks/blanco.md CON marca (que el nombre ../blanco resolveria) haria "nuestro"
# al manifiesto y lo borraria.
caso "recetario: un nombre inseguro del manifiesto NO sesga la propiedad al quitar"
nuevo_destino; nuevo_casa_recetas
mkdir -p "$(dirname "$dest")/recetas"
escribir_nuestro_viejo "$(dirname "$dest")/blanco.md"   # fuera de recetas/, con marca
printf 'deadbeef\treceta\t../blanco\tfull\tTitulo ajeno\n' > "$(dirname "$dest")/recetas/MANIFEST.sha256"
out="$(host_claude_recetas --quitar-recetas 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "--quitar-recetas con nombre inseguro deberia salir 0, dio $rc: $out"
[ -e "$(dirname "$dest")/recetas/MANIFEST.sha256" ] || malo "el nombre inseguro NO debe volver 'nuestro' al manifiesto (se borro)"
printf '%s' "$out" | grep -qi 'no es atribuible\|intacto' || malo "debe reportar el manifiesto como no atribuible: $out"

if [ "$fail" -ne 0 ]; then
  echo "test_install_hook: FAIL" >&2
  exit 1
fi
echo "test_install_hook: OK"
