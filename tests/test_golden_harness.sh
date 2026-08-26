#!/usr/bin/env bash
# Task 1.2 — el ARNES de salida dorada cumple lo que promete.
#
# Este test NO mira el hook vivo: prueba la herramienta contra un hook FALSO y
# escenarios FALSOS, todo adentro del sandbox. La comparacion contra el archivo
# vivo es el otro test (`test_golden_baseline.sh`); separarlos es lo que permite
# que este corra igual en una maquina donde el hook vivo no existe.
#
# Lo que se mide aca es exactamente lo que hace confiable a una linea base:
#   - que sea REPRODUCIBLE (dos corridas dan lo mismo);
#   - que DETECTE un cambio de comportamiento (si no, siempre diria "identico"
#     y no probaria nada — es el mutation-test que pide el DoD);
#   - que distinga "divergente" de "no se pudo mirar" (Core Rule 2);
#   - que no pueda salir verde con cobertura CERO;
#   - que jamas escriba al lado del hook que ejercita, ni en `~/.claude`.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
arnes="$repo/tools/golden-harness.sh"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# --------------------------------------------------------------- utilleria
# Copia el hook falso y sus escenarios al sandbox. Se copian (no se usan en su
# lugar) para que el caso de aislamiento pueda mirar el ORIGINAL y comprobar
# que el arnes no le dejo nada al lado.
armar_falso() {
  destino="$1"
  mkdir -p "$destino"
  cp -r "$repo/tests/fixtures/arnes-falso/." "$destino/"
}

falso="$SANDBOX/falso"
armar_falso "$falso"
hook_falso="$falso/hook-falso.sh"
esc_falsos="$falso/escenarios"
base="$SANDBOX/baseline.txt"

correr() {
  # correr <archivo-salida> <args...> ; deja el exit code en $rc
  salida="$1"; shift
  bash "$arnes" "$@" > "$salida" 2>&1
  rc=$?
}

# ------------------------------------------------------- 1) reproducibilidad
caso "dos corridas contra el mismo hook dan un registro byte-identico"
correr "$SANDBOX/p1.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -eq 0 ] || malo "--print debio salir 0, dio $rc: $(cat "$SANDBOX/p1.txt")"
correr "$SANDBOX/p2.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
if ! cmp -s "$SANDBOX/p1.txt" "$SANDBOX/p2.txt"; then
  malo "el registro NO es reproducible entre corridas"
  diff -u "$SANDBOX/p1.txt" "$SANDBOX/p2.txt" | head -20 >&2
fi

# --------------------------------------------- 2) el registro tiene contenido
caso "el registro nombra cada escenario y trae exit code y stdout de cada paso"
for e in 01-verde 02-bloqueo; do
  grep -q "$e" "$SANDBOX/p1.txt" || malo "el registro no nombra el escenario $e"
done
grep -q '^exit ' "$SANDBOX/p1.txt" || malo "el registro no trae el exit code de los pasos"
grep -q 'stdout' "$SANDBOX/p1.txt" || malo "el registro no trae el stdout de los pasos"
grep -qi 'sha256' "$SANDBOX/p1.txt" || malo "el registro no declara la identidad del hook (sha256)"

# ------------------------------------------------------ 3) record + check ok
caso "--record y despues --check contra el MISMO hook => 0"
correr "$SANDBOX/rec.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base" --record
[ "$rc" -eq 0 ] || malo "--record debio salir 0, dio $rc: $(cat "$SANDBOX/rec.txt")"
[ -s "$base" ] || malo "--record no escribio la linea base"
correr "$SANDBOX/chk.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 0 ] || malo "--check contra el mismo hook debio salir 0, dio $rc: $(cat "$SANDBOX/chk.txt")"

# --------------------- 3b) la identidad grabada no arrastra el escape de GNU
# `sha256sum RUTA` antepone `\` a la linea cuando la ruta trae un backslash: ahi
# coreutils devuelve el nombre ESCAPADO y avisa con ese marcador. El marcador se
# colaba al `# hook_sha256:` de la linea base, y la identidad terminaba
# describiendo un archivo que no existe -- mismo hook, huella distinta segun
# COMO se lo nombre. Eso deja mudo el aviso de cambio de identidad: pasa a
# gritar deriva en cada corrida, con lo cual deja de significar nada.
# La forma inmune es leer por stdin (`sha256sum < RUTA`), sin ruta en la salida:
# es la que `sha_de()` de tools/install-hook.sh ya usa desde la Task 12.9.
caso "el sha grabado no arrastra el marcador de escape de GNU (ruta con backslash)"
hook_bs=''
if cp "$hook_falso" "$SANDBOX/hook\\raro.sh" 2>/dev/null; then
  hook_bs="$SANDBOX/hook\\raro.sh"
elif command -v cygpath >/dev/null 2>&1; then
  hook_bs="$(cygpath -w "$hook_falso" 2>/dev/null)"
fi
base_bs="$SANDBOX/baseline-bs.txt"
if [ -z "$hook_bs" ] || [ ! -r "$hook_bs" ]; then
  # Core Rule 2: no haber podido montar el caso no es haberlo visto pasar.
  printf '    unknown: esta maquina no deja nombrar el hook con un backslash; el caso no se pudo medir\n'
else
  correr "$SANDBOX/rec_bs.txt" --hook "$hook_bs" --scenarios "$esc_falsos" --baseline "$base_bs" --record
  if [ ! -s "$base_bs" ]; then
    printf '    unknown: --record no acepto la ruta con backslash; el caso no se pudo medir\n'
  else
    sha_grabado="$(grep -m1 '^# hook_sha256: ' "$base_bs" | sed 's/^# hook_sha256: //')"
    sha_esperado="$(sha256sum < "$hook_falso" | cut -d' ' -f1)"
    printf '%s\n' "$sha_grabado" | grep -qE '^[0-9a-f]{64}$' \
      || malo "el sha grabado no son 64 hex limpios: [$sha_grabado]"
    [ "$sha_grabado" = "$sha_esperado" ] \
      || malo "el sha grabado no es el del archivo: grabado [$sha_grabado] esperado [$sha_esperado]"
  fi
fi

# ------------------------------------- 4) mutation-test: detecta la diferencia
caso "hook MUTADO => --check falla (1) y nombra el escenario divergente"
mutado="$SANDBOX/hook-mutado.sh"
sed 's/{"ok":true}/{"ok":false}/' "$hook_falso" > "$mutado"
cmp -s "$hook_falso" "$mutado" && malo "la mutacion no cambio nada; el caso no probaria nada"
correr "$SANDBOX/mut.txt" --hook "$mutado" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 1 ] || malo "un hook mutado debe dar divergencia (exit 1), dio $rc"
grep -q '01-verde' "$SANDBOX/mut.txt" || malo "no nombra el escenario divergente: $(cat "$SANDBOX/mut.txt")"

caso "mutacion en el ESTADO (no en stdout) tambien se detecta"
mutado2="$SANDBOX/hook-mutado2.sh"
sed 's/^ESTADO_NOMBRE=.*/ESTADO_NOMBRE=otro.env/' "$hook_falso" > "$mutado2"
cmp -s "$hook_falso" "$mutado2" && malo "la mutacion de estado no cambio nada"
correr "$SANDBOX/mut2.txt" --hook "$mutado2" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 1 ] || malo "un cambio en el ESTADO que deja el hook debe detectarse, dio $rc"

# ------------------------------------------------- 5) unknown != divergencia
caso "hook inexistente => exit 2 y 'unknown', nunca 'identico' (Core Rule 2)"
correr "$SANDBOX/nohook.txt" --hook "$SANDBOX/no-existe.sh" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 2 ] || malo "sin hook que mirar el veredicto es unknown (exit 2), dio $rc"
grep -qi 'unknown' "$SANDBOX/nohook.txt" || malo "no dice unknown: $(cat "$SANDBOX/nohook.txt")"

caso "linea base inexistente => exit 2 y 'unknown', no un falso verde"
correr "$SANDBOX/nobase.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$SANDBOX/no-hay.txt" --check
[ "$rc" -eq 2 ] || malo "sin linea base el veredicto es unknown (exit 2), dio $rc"
grep -qi 'unknown' "$SANDBOX/nobase.txt" || malo "no dice unknown: $(cat "$SANDBOX/nobase.txt")"

# --------------------------------------------- 6) cobertura cero != verde
caso "directorio de escenarios vacio => falla, no pasa como verde"
mkdir -p "$SANDBOX/sin-escenarios"
correr "$SANDBOX/vacio.txt" --hook "$hook_falso" --scenarios "$SANDBOX/sin-escenarios" --print
[ "$rc" -ne 0 ] || malo "cero escenarios NO puede salir 0: seria 'todo verde' sin haber corrido nada"

caso "directorio de escenarios inexistente => falla"
correr "$SANDBOX/noesc.txt" --hook "$hook_falso" --scenarios "$SANDBOX/no-existe-dir" --print
[ "$rc" -ne 0 ] || malo "un directorio de escenarios inexistente NO puede salir 0"

# Hallazgo de la revision cruzada (2026-08-09, codex): un escenario SIN pasos
# ocupaba un bloque en la linea base sin ejecutar nada. Cobertura fantasma:
# `--check` lo comparaba contra si mismo y decia que todo bien.
caso "un escenario sin ningun paso => falla y lo nombra, no cuenta como cubierto"
mkdir -p "$esc_falsos/03-vacio"
correr "$SANDBOX/escvacio.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -ne 0 ] || malo "un escenario sin pasos NO puede pasar como cubierto"
grep -q '03-vacio' "$SANDBOX/escvacio.txt" || malo "no nombra el escenario vacio: $(cat "$SANDBOX/escvacio.txt")"
rmdir "$esc_falsos/03-vacio"

# Hallazgo de la revision cruzada (2026-08-09, codex): el nombre del escenario
# que trae la linea base se usaba como ruta sin mirarlo. Una linea base
# manipulada podia hacer que `--check` escribiera fuera de su tmpdir.
caso "nombre de escenario con ../ en la linea base => se rechaza, no se escribe fuera"
base_maliciosa="$SANDBOX/base-maliciosa.txt"
blanco="$SANDBOX/blanco-fuera.txt"
: > "$blanco"
{ printf '# hook_sha256: 0\n'; printf '=== escenario ../blanco-fuera.txt\n'; printf 'basura\n'; } > "$base_maliciosa"
correr "$SANDBOX/traversal.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base_maliciosa" --check
[ "$rc" -eq 2 ] || malo "un nombre con ruta es 'no se puede mirar' (exit 2), dio $rc"
grep -qi 'invalido' "$SANDBOX/traversal.txt" || malo "no dice que el nombre es invalido: $(cat "$SANDBOX/traversal.txt")"
[ ! -s "$blanco" ] || malo "TRAVERSAL: escribio en un archivo fuera del directorio de trabajo"

# ------------------------------------------- 6-bis) basura del entorno
# Medido: el tooling del entorno deja directorios `.claude` vacios adentro de
# cualquier arbol donde se trabaje. Uno de esos colandose como "escenario"
# mete un bloque vacio en la linea base — cobertura fantasma que nadie pidio.
caso "un directorio oculto en el arbol de escenarios NO cuenta como escenario"
mkdir -p "$esc_falsos/.claude"
correr "$SANDBOX/oculto.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc"
grep -q '^=== escenario \.' "$SANDBOX/oculto.txt" && malo "un directorio oculto se colo como escenario"
# Task 7.6: 05-grok sigue a 04-codex; el conteo sube a 5.
[ "$(grep -c '^=== escenario ' "$SANDBOX/oculto.txt")" = "5" ] \
  || malo "esperaba exactamente 5 escenarios, hubo $(grep -c '^=== escenario ' "$SANDBOX/oculto.txt")"
rmdir "$esc_falsos/.claude"

# --------------------------------------------------------- 7) aislamiento
caso "el arnes NO escribe al lado del hook que ejercita"
[ ! -e "$falso/state" ] || malo "AISLAMIENTO ROTO: dejo state/ junto al hook original"
[ -z "$(find "$falso" -newer "$arnes" -name '*.env' 2>/dev/null)" ] \
  || malo "AISLAMIENTO ROTO: escribio estado adentro del arbol del hook original"

caso "el arnes NO escribe en \$HOME/.claude"
sobras="$(find "$HOME/.claude" -type f 2>/dev/null | head -5)"
[ -z "$sobras" ] || malo "AISLAMIENTO ROTO: escribio en \$HOME/.claude: $sobras"

# ------------------------------------ 8) la identidad no decide el veredicto
# Phase 2.1 va a cambiar el hook a proposito (le agrega el marcador de
# propiedad): ahi el sha CAMBIA y el comportamiento debe seguir igual. Si el
# arnes comparara la identidad, ese caso legitimo daria rojo y el arnes no
# serviria justo para lo que existe.
caso "hook con bytes distintos pero MISMO comportamiento => --check sale 0 y avisa del cambio de identidad"
marcado="$SANDBOX/hook-marcado.sh"
{ head -n 1 "$hook_falso"; printf '# SAIKIT-CLAUDE-OWNED summonaikit-claude 0.0.0-test\n'; tail -n +2 "$hook_falso"; } > "$marcado"
cmp -s "$hook_falso" "$marcado" && malo "el fixture marcado quedo identico; el caso no probaria nada"
correr "$SANDBOX/marcado.txt" --hook "$marcado" --scenarios "$esc_falsos" --baseline "$base" --check
[ "$rc" -eq 0 ] || malo "mismo comportamiento con otros bytes debe salir 0, dio $rc: $(cat "$SANDBOX/marcado.txt")"
grep -qi 'identidad' "$SANDBOX/marcado.txt" || malo "deberia AVISAR que el hook cambio de identidad: $(cat "$SANDBOX/marcado.txt")"

# ------------------------------------------ 9) target zcode (Task 5.5)
# El token `zcode` del filename NO exporta SUMMONAIKIT_HOOK_TARGET: pone
# ZCODE_SESSION_ID / ZCODE_PROJECT_DIR (la senal de host de zcode, medida 5.1),
# igual que en produccion. El estado del falso lo registra, y el arnes emite
# `estado_host: zcode` leyendo el arbol sin normalizar. 01-verde/02-bloqueo
# (claude) no ganan ni zcode_session real ni la linea estado_host.
caso "target zcode: el estado trae ZCODE_SESSION_ID/PROJECT_DIR y NO exporta TARGET"
correr "$SANDBOX/zc.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
[ "$rc" -eq 0 ] || malo "--print debio salir 0, dio $rc: $(cat "$SANDBOX/zc.txt")"
# Task 6.6: 03-zcode ya NO es el ultimo (04-codex lo sigue): el bloque se acota
# al proximo `=== escenario` en vez de correr hasta EOF.
awk '/^=== escenario 03-zcode/{f=1; print; next} /^=== escenario /{f=0} f' "$SANDBOX/zc.txt" > "$SANDBOX/zc_blk.txt"
grep -q '^| zcode_session=sess_golden_zcode$' "$SANDBOX/zc_blk.txt" \
  || malo "el estado zcode no trae zcode_session=sess_golden_zcode"
grep -q '^| zcode_project=C:/dev/saikit-golden-zcode$' "$SANDBOX/zc_blk.txt" \
  || malo "el estado zcode no trae zcode_project=C:/dev/saikit-golden-zcode"

caso "target zcode: el estado NO trae target=zcode ni target=claude (TARGET no exportado)"
# Se mira SOLO lineas de estado (prefijo '| '); el header '--- paso ... target=zcode'
# del arnes es el token del filename, no la variable, y no se cuela aca.
grep -q '^| target=zcode$' "$SANDBOX/zc_blk.txt" \
  && malo "el estado zcode trae target=zcode: el arnes exporto TARGET=zcode (no debia)"
grep -q '^| target=claude$' "$SANDBOX/zc_blk.txt" \
  && malo "el estado zcode trae target=claude: TARGET se exporto cuando no debia"
grep -q '^| target=<sin-target>$' "$SANDBOX/zc_blk.txt" \
  || malo "el estado zcode debio traer target=<sin-target>"

caso "target claude: sigue SIN ZCODE_* (regresion unset 5.3) y SIN linea estado_host"
awk '/^=== escenario 01-verde/{f=1} /^=== escenario 02-bloqueo/{f=0} f' "$SANDBOX/zc.txt" > "$SANDBOX/cl_blk.txt"
grep -q '^| zcode_session=sess_golden_zcode$' "$SANDBOX/cl_blk.txt" \
  && malo "01-verde (claude) trae zcode_session real: el unset de ZCODE_* se rompio"
grep -q '^| zcode_session=<sin-zcode>$' "$SANDBOX/cl_blk.txt" \
  || malo "01-verde (claude) debio traer zcode_session=<sin-zcode>"
grep -q '^estado_host:' "$SANDBOX/cl_blk.txt" \
  && malo "01-verde (claude) NO debe tener linea estado_host (solo el target zcode)"

caso "target zcode: un paso que deja estado trae 'estado_host: zcode' (A4)"
grep -q '^estado_host: zcode$' "$SANDBOX/zc_blk.txt" \
  || malo "el paso zcode debio traer 'estado_host: zcode': $(cat "$SANDBOX/zc_blk.txt")"

# ------------------------------------------ 9-bis) target codex (Task 6.6)
# El token `codex` SI exporta SUMMONAIKIT_HOOK_TARGET=codex — la senal real
# del wrapper .ps1 de Codex (unico host donde el TARGET llega, 6.1) — la
# contraparte exacta de zcode, que va por ZCODE_* sin TARGET.
caso "target codex: el estado trae target=codex (TARGET exportado) y sin ZCODE_*"
# Task 7.6: 04-codex ya NO es el ultimo (05-grok lo sigue): el bloque se acota
# al proximo `=== escenario` en vez de correr hasta EOF.
awk '/^=== escenario 04-codex/{f=1; print; next} /^=== escenario /{f=0} f' "$SANDBOX/zc.txt" > "$SANDBOX/cx_blk.txt"
grep -q '^| target=codex$' "$SANDBOX/cx_blk.txt" \
  || malo "el estado codex debio traer target=codex (el arnes no exporto TARGET)"
grep -q '^| zcode_session=<sin-zcode>$' "$SANDBOX/cx_blk.txt" \
  || malo "el estado codex debio traer zcode_session=<sin-zcode> (regresion unset 5.3)"
# Task 7.6: la contracara grok del unset de arriba. En CI (sin GROK_* en el
# entorno) borrar el -u del arnes no cambia NINGUN veredicto y nadie se
# enteraria; este pinnado negativo al menos declara la intencion y atrapa el
# caso cuando la suite corre desde adentro de Grok.
grep -q '^| grok_event=<sin-grok>$' "$SANDBOX/cx_blk.txt" \
  || malo "el estado codex debio traer grok_event=<sin-grok> (regresion unset 7.6)"

caso "target codex: un paso que deja estado trae 'estado_host: codex' (D2, 6.4)"
grep -q '^estado_host: codex$' "$SANDBOX/cx_blk.txt" \
  || malo "el paso codex debio traer 'estado_host: codex': $(cat "$SANDBOX/cx_blk.txt")"

# ------------------------------------------ 9-ter) target grok (Task 7.6)
# El token `grok` exporta las TRES senales del runner de hooks de Grok
# (medidas 7.1): GROK_HOOK_EVENT (setness => HOST=grok), GROK_SESSION_ID y el
# env map SUMMONAIKIT_HOOK_TARGET=grok. El estado del falso lo registra todo.
caso "target grok: el estado trae target=grok, grok_event real y sin ZCODE_*"
# 05-grok acota al proximo `=== escenario` (misma forma que 04-codex arriba):
# el dia que exista 06-*, correr hasta EOF volveria a leer estado ajeno.
awk '/^=== escenario 05-grok/{f=1; print; next} /^=== escenario /{f=0} f' "$SANDBOX/zc.txt" > "$SANDBOX/gk_blk.txt"
grep -q '^| target=grok$' "$SANDBOX/gk_blk.txt" \
  || malo "el estado grok debio traer target=grok (env map exportado)"
grep -q '^| grok_event=user_prompt_submit$' "$SANDBOX/gk_blk.txt" \
  || malo "el estado grok debio traer grok_event=user_prompt_submit (mapeo fase->evento)"
grep -q '^| grok_session=sess_golden_grok$' "$SANDBOX/gk_blk.txt" \
  || malo "el estado grok debio traer grok_session=sess_golden_grok"
grep -q '^| zcode_session=<sin-zcode>$' "$SANDBOX/gk_blk.txt" \
  || malo "el estado grok debio traer zcode_session=<sin-zcode> (regresion unset 5.3)"

caso "target grok: un paso que deja estado trae 'estado_host: grok' (D2, 7.3)"
grep -q '^estado_host: grok$' "$SANDBOX/gk_blk.txt" \
  || malo "el paso grok debio traer 'estado_host: grok': $(cat "$SANDBOX/gk_blk.txt")"

caso "target zcode: dos --print seguidos son byte-identicos (constantes sin ruido)"
correr "$SANDBOX/zc2.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --print
if ! cmp -s "$SANDBOX/zc.txt" "$SANDBOX/zc2.txt"; then
  malo "dos --print con 03-zcode no son byte-identicos"
  diff -u "$SANDBOX/zc.txt" "$SANDBOX/zc2.txt" | head -20 >&2
fi

caso "target zcode/codex/grok: --record + --check del falso con 5 escenarios sigue en 0"
base3="$SANDBOX/base3.txt"
correr "$SANDBOX/rec3.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base3" --record
[ "$rc" -eq 0 ] || malo "--record (5 esc) debio salir 0, dio $rc: $(cat "$SANDBOX/rec3.txt")"
correr "$SANDBOX/chk3.txt" --hook "$hook_falso" --scenarios "$esc_falsos" --baseline "$base3" --check
[ "$rc" -eq 0 ] || malo "--check (5 esc) debio salir 0, dio $rc: $(cat "$SANDBOX/chk3.txt")"

if [ "$fail" -ne 0 ]; then
  echo "test_golden_harness: FAIL" >&2
  exit 1
fi
echo "test_golden_harness: OK"
