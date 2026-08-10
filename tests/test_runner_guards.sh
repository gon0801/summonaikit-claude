#!/usr/bin/env bash
# Task 1.1 — el runner cumple lo que promete, medido y no declarado.
#
# Cada caso corre `tests/run.sh` contra un repo SINTETICO dentro del sandbox:
# el runner acepta la raiz por argumento justamente para esto. Ningun caso
# corre contra este repo ni contra el perfil vivo.
#
# El caso de contencion de HOME se invoca con un HOME señuelo propio: si la
# contencion estuviera rota, la escritura cae en el señuelo (que esta adentro
# del sandbox) y se reporta — nunca sobre `~/.claude/hooks/`, que es el archivo
# que gatea cada turno.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_sh="$here/run.sh"
. "$here/lib/sandbox.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# ------------------------------------------------- 1) repo vacio de logica
caso "repo sin hook y sin tests => exit 0"
mkdir -p "$SANDBOX/vacio/tests"
out="$(bash "$run_sh" "$SANDBOX/vacio" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"

# ------------------------------------------------------ 2) gate de sintaxis
caso "hooks/summonaikit-harness.sh que no parsea => rompe la corrida"
mkdir -p "$SANDBOX/hookroto/hooks"
printf 'if then fi (\n' > "$SANDBOX/hookroto/hooks/summonaikit-harness.sh"
out="$(bash "$run_sh" "$SANDBOX/hookroto" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un hook que no parsea debe romper la corrida (dio $rc)"
printf '%s' "$out" | grep -q 'summonaikit-harness.sh' || malo "no nombra el archivo culpable: $out"

# --------------------------------------------------------- 3) camino verde
caso "repo sano con un test verde => exit 0 y lo reporta PASS"
mkdir -p "$SANDBOX/verde/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/verde/tests/test_verde.sh"
out="$(bash "$run_sh" "$SANDBOX/verde" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
printf '%s' "$out" | grep -q 'PASS: test_verde' || malo "no reporta el PASS: $out"

# ------------------------------------------------------------ 4) test rojo
# --------------------------------------------------------------- Task 1.5
# Un test que no pudo verificar nada salia 0 y se publicaba como PASS, asi que
# una maquina sin el archivo bajo prueba quedaba ENTERA en verde sin haber
# probado una sola linea de semantica (revision cruzada de la Phase 1).
caso "un test que sale 3 se reporta UNKNOWN, no PASS"
mkdir -p "$SANDBOX/unk/tests"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/unk/tests/test_no_observado.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/unk/tests/test_verde.sh"
out="$(bash "$run_sh" "$SANDBOX/unk" 2>&1)"; rc=$?
printf '%s' "$out" | grep -q 'UNKNOWN: test_no_observado' || malo "no lo reporta como UNKNOWN: $out"
printf '%s' "$out" | grep -q 'PASS: test_no_observado'    && malo "un unknown NO puede publicarse como PASS: $out"
printf '%s' "$out" | grep -q 'PASS: test_verde'           || malo "el test que si verifico sigue siendo PASS: $out"
[ "$rc" -eq 0 ] || malo "con al menos un test verificando, la corrida cierra 0: dio $rc"
printf '%s' "$out" | grep -q '1 de 2 en unknown' || malo "el resumen no dice cuantos quedaron sin verificar: $out"

caso "si TODOS los tests son unknown, la corrida NO cierra OK"
# Es la afirmacion mas falsa que este runner puede emitir: verde entero sin
# haber probado nada.
mkdir -p "$SANDBOX/todo-unk/tests"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/todo-unk/tests/test_a.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/todo-unk/tests/test_b.sh"
out="$(bash "$run_sh" "$SANDBOX/todo-unk" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "cerro OK sin haber verificado nada: $out"
printf '%s' "$out" | grep -qi 'unknown' || malo "no declara que no se pudo mirar: $out"
printf '%s' "$out" | grep -q 'run.sh: OK' && malo "no puede decir OK: $out"

caso "un unknown NO tapa un fallo real"
mkdir -p "$SANDBOX/unk-y-rojo/tests"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/unk-y-rojo/tests/test_no_observado.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/unk-y-rojo/tests/test_rojo.sh"
out="$(bash "$run_sh" "$SANDBOX/unk-y-rojo" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "un fallo real manda sobre el unknown: esperaba 1, dio $rc"
printf '%s' "$out" | grep -q 'FAIL: test_rojo' || malo "no nombra el test que fallo: $out"

caso "un test que falla => rompe la corrida y lo nombra"
mkdir -p "$SANDBOX/rojo/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/rojo/tests/test_rojo.sh"
out="$(bash "$run_sh" "$SANDBOX/rojo" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "un test rojo debe romper la corrida"
printf '%s' "$out" | grep -q 'test_rojo' || malo "no nombra el test que fallo: $out"

# -------------------------------------------------- 5) fuga adentro del repo
caso "test que escribe DENTRO del repo => se detecta la fuga aunque pase"
mkdir -p "$SANDBOX/fuga/tests"
cat > "$SANDBOX/fuga/tests/test_fuga.sh" <<'SH'
#!/usr/bin/env bash
printf 'x' > "$(cd "$(dirname "$0")/.." && pwd)/FUGA.txt"
exit 0
SH
out="$(bash "$run_sh" "$SANDBOX/fuga" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "escribir adentro del repo debe romper la corrida"
printf '%s' "$out" | grep -q 'LEAK' || malo "no reporta la fuga: $out"
printf '%s' "$out" | grep -q 'PASS: test_fuga' || malo "el test paso; el runner deberia decirlo igual: $out"

# --------------------------- 5-bis) el churn del tooling del host NO es fuga
# Medido el 2026-08-09 durante la Task 2.1: `.claude/state/session.json`,
# `.claude/state/session-events.jsonl` y `out/progress-snapshot.html` los
# reescribe el tooling del host mientras la suite corre, y hacian fallar la
# corrida entera con las 11 baterias en PASS. Las delatadas eran siempre las dos
# mas lentas — las unicas con ventana lo bastante larga — o sea que el guard
# acusaba al test que mas tardaba, no al que escribia.
#
# El caso 5 de arriba es el control positivo: una fuga en ruta versionada TIENE
# que seguir rompiendo la corrida. Este solo afirma que lo ignorado no cuenta.
caso "escritura del tooling del host en .claude/ y out/ NO se reporta como fuga"
mkdir -p "$SANDBOX/churn/tests" "$SANDBOX/churn/.claude/state" "$SANDBOX/churn/out" \
         "$SANDBOX/churn/tests/fixtures/.claude"
printf 'antes\n' > "$SANDBOX/churn/.claude/state/session.json"
printf 'antes\n' > "$SANDBOX/churn/out/progress-snapshot.html"
printf 'antes\n' > "$SANDBOX/churn/tests/fixtures/.claude/anidado.json"
cat > "$SANDBOX/churn/tests/test_churn.sh" <<'SH'
#!/usr/bin/env bash
raiz="$(cd "$(dirname "$0")/.." && pwd)"
# Modificado, y tambien creado: el manifiesto detecta las dos cosas.
printf 'despues, con otro tamano\n' > "$raiz/.claude/state/session.json"
printf 'despues\n'                  > "$raiz/out/progress-snapshot.html"
printf 'despues\n'                  > "$raiz/tests/fixtures/.claude/anidado.json"
printf 'nuevo\n'                    > "$raiz/.claude/state/nuevo.json"
exit 0
SH
out="$(bash "$run_sh" "$SANDBOX/churn" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "el churn de .claude/ y out/ no deberia romper la corrida: $out"
printf '%s' "$out" | grep -q 'LEAK' && malo "reporto fuga por el tooling del host: $out"

# ------------------------------------- 6) contencion del HOME (Core Rule 4)
caso "test que escribe en \$HOME => queda contenido, no toca el HOME del invocador"
mkdir -p "$SANDBOX/homeleak/tests" "$SANDBOX/senuelo-home"
cat > "$SANDBOX/homeleak/tests/test_home.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/.claude/hooks"
printf 'echo plantado\n' > "$HOME/.claude/hooks/plantado.sh"
exit 0
SH
out="$(HOME="$SANDBOX/senuelo-home" bash "$run_sh" "$SANDBOX/homeleak" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "la escritura es legitima adentro del sandbox; esperaba exit 0: $out"
[ ! -e "$SANDBOX/senuelo-home/.claude/hooks/plantado.sh" ] \
  || malo "CONTENCION ROTA: el test escribio en el HOME del invocador"

# --------------------------------------------- 7) raiz inexistente != verde
# Un runner apuntado a una raiz que no existe no tiene NADA que correr. Salir 0
# ahi es reportar "todo verde" con cobertura cero, el mismo modo de falla que
# `check_syntax` cuida cuando `find` no puede recorrer el arbol.
caso "raiz inexistente => falla, no pasa como verde con cobertura cero"
out="$(bash "$run_sh" "$SANDBOX/no-existe" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "una raiz inexistente NO puede salir 0: $out"

if [ "$fail" -ne 0 ]; then
  echo "test_runner_guards: FAIL" >&2
  exit 1
fi
echo "test_runner_guards: OK"
