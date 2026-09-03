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

# Esta bateria puede correr DENTRO de un runner particionado (el job `suite` la
# invoca con SAIKIT_PARTICION=rapidos): heredarla vuelve la "corrida completa"
# de los casos de abajo indistinguible de una mitad — que es exactamente como el
# caso de la union salio verde en local y ROJO en CI. Los casos que necesitan
# una particion la ponen ellos, por comando. Misma leccion que ya aplica mas
# abajo con SAIKIT_TESTS_SIN_EJECUTOR.
unset SAIKIT_PARTICION

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

# ----------------- 8) skip sin ejecutor + unknown a la vez (18.16, ex codex r1)
# El skip ya no promete "lo corre Windows" (18.16): declara que NADIE lo corre,
# se lista y cuenta como unknown. La garantia del resumen (codex r1, hallazgo 3
# de la 10.5) se mantiene: imprime SIEMPRE que haya skips, en cualquier camino
# de salida (tambien el exit 3). env -u porque este test puede correr DENTRO de
# un runner que exporte la variable: heredarla volveria la mitad "sin variable"
# indistinguible de la primera (la misma leccion de determinismo del lab).
caso "unknown + SKIP sin ejecutor simultaneos => el resumen de skips igual imprime"
mkdir -p "$SANDBOX/unk-y-skip/tests"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SANDBOX/unk-y-skip/tests/test_no_observado.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/unk-y-skip/tests/test_huerfano.sh"
out="$(SAIKIT_TESTS_SIN_EJECUTOR='test_huerfano' bash "$run_sh" "$SANDBOX/unk-y-skip" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || malo "todo sin verificar (unknown + skip) => exit 3, dio $rc: $out"
printf '%s' "$out" | grep -q 'SKIP (sin ejecutor): test_huerfano' \
  || malo "el skip sin ejecutor no se lista: $out"
printf '%s' "$out" | grep -q 'SKIP (sin ejecutor) declarados' \
  || malo "el resumen de skips no imprime antes del exit 3 (codex r1, hallazgo 3): $out"
# Y el mismo repo SIN la variable: nada se salta, el huerfano corre y es PASS,
# y el unknown solo ya no hunde la corrida (1 de 2 verificado).
out="$(env -u SAIKIT_TESTS_SIN_EJECUTOR bash "$run_sh" "$SANDBOX/unk-y-skip" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "sin SAIKIT_TESTS_SIN_EJECUTOR el skip no aplica; con 1 PASS de 2 cierra 0, dio $rc: $out"
printf '%s' "$out" | grep -q 'PASS: test_huerfano' || malo "sin la variable el huerfano debe correr y pasar: $out"
printf '%s' "$out" | grep -q 'SKIP (sin ejecutor)' && malo "sin la variable no hay skips que listar: $out"

# ------------------- 18.16: el resumen distingue FAIL de unknown (f1/f2) -----
# La linea divisoria es si hubo OBSERVACION: un test que ARRANCA y muere en
# exit 1 es FAIL, jamas unknown; un test SIN ejecutor es unknown — corre en
# ningun entorno, no verifica nada. Confundirlos esconderia una regresion
# observada como falta de cobertura, o al reves.
caso "un test que CORRIO y salio exit 1 => el resumen dice FAIL y NO cierra OK"
mkdir -p "$SANDBOX/corrio-rojo/tests"
printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/corrio-rojo/tests/test_rojo.sh"
out="$(bash "$run_sh" "$SANDBOX/corrio-rojo" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || malo "corrio y fallo => exit 1, dio $rc: $out"
printf '%s' "$out" | grep -q 'FAIL: test_rojo' || malo "el resumen no dice FAIL del test que corrio y fallo: $out"
printf '%s' "$out" | grep -q 'run.sh: OK' && malo "no puede decir OK con un test en FAIL: $out"
printf '%s' "$out" | grep -q 'UNKNOWN: test_rojo' && malo "un exit 1 del test es FAIL, jamas unknown: $out"

caso "un test SIN ejecutor => el resumen lo dice y lo cuenta como unknown"
# Con un verde al lado: 1 corrido PASS + 1 skip-sin-ejecutor = unknown parcial.
mkdir -p "$SANDBOX/sin-exec/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/sin-exec/tests/test_verde.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/sin-exec/tests/test_nadie.sh"
out="$(SAIKIT_TESTS_SIN_EJECUTOR='test_nadie' bash "$run_sh" "$SANDBOX/sin-exec" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "1 PASS + 1 sin ejecutor cierra 0 (unknown parcial), dio $rc: $out"
printf '%s' "$out" | grep -q 'SKIP (sin ejecutor): test_nadie' || malo "el sin ejecutor no se lista: $out"
printf '%s' "$out" | grep -q '1 de 1 en unknown' || malo "el resumen no cuenta el sin ejecutor como unknown: $out"
printf '%s' "$out" | grep -q 'PASS: test_nadie' && malo "un skip sin ejecutor NO puede publicarse como PASS: $out"
# Y si NADIE corre nada: la corrida NO cierra OK (la misma disciplina del
# exit 3 — no se afirma lo que no se mido).
mkdir -p "$SANDBOX/solo-sin-exec/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/solo-sin-exec/tests/test_nadie.sh"
out="$(SAIKIT_TESTS_SIN_EJECUTOR='test_nadie' bash "$run_sh" "$SANDBOX/solo-sin-exec" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || malo "todo sin ejecutor => exit 3, dio $rc: $out"
printf '%s' "$out" | grep -q 'run.sh: OK' && malo "todo sin ejecutor no puede cerrar OK: $out"

# ------------------------------- 7) particion de la bateria para CI (2026-08-28)
# El job `suite` tarda ~7 min y `test_gate_mutations` es 4.8 de esos minutos
# (medido en el run 33231405475). Partirla en dos jobs PARALELOS baja el reloj a
# ~2.5 min sin saltear un solo test.
#
# Lo que estos casos candan NO es la velocidad: es la propiedad que vuelve segura
# la particion — la union de las dos mitades es la bateria ENTERA. Una particion
# que pierde un archivo es un test que deja de correr sin que nadie se entere, la
# misma falla silenciosa que el conteo de `unknown` existe para evitar
# (not_observed != absent). Por eso la lista de lentos vive en `run.sh` y no en el
# workflow: aca se puede candear.
mkdir -p "$SANDBOX/part/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part/tests/test_gate_mutations.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part/tests/test_rapido_uno.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part/tests/test_rapido_dos.sh"
nombres() { printf '%s' "$1" | grep -oE '(PASS|FAIL|UNKNOWN): test_[a-z_]+' | sort -u; }

caso "particion 'lentos' corre SOLO los listados"
out="$(SAIKIT_PARTICION=lentos bash "$run_sh" "$SANDBOX/part" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
printf '%s' "$out" | grep -q 'PASS: test_gate_mutations' || malo "no corrio el lento: $out"
printf '%s' "$out" | grep -q 'PASS: test_rapido'         && malo "la mitad lenta corrio un rapido: $out"

caso "particion 'rapidos' corre todo MENOS los listados"
out="$(SAIKIT_PARTICION=rapidos bash "$run_sh" "$SANDBOX/part" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || malo "esperaba exit 0, dio $rc: $out"
printf '%s' "$out" | grep -q 'PASS: test_rapido_uno'     || malo "no corrio test_rapido_uno: $out"
printf '%s' "$out" | grep -q 'PASS: test_rapido_dos'     || malo "no corrio test_rapido_dos: $out"
printf '%s' "$out" | grep -q 'PASS: test_gate_mutations' && malo "la mitad rapida corrio el lento: $out"

caso "la union de las dos mitades == la bateria entera (ni un test se pierde)"
completa="$(nombres "$(bash "$run_sh" "$SANDBOX/part" 2>&1)")"
mitades="$(nombres "$( SAIKIT_PARTICION=lentos  bash "$run_sh" "$SANDBOX/part" 2>&1
                       SAIKIT_PARTICION=rapidos bash "$run_sh" "$SANDBOX/part" 2>&1 )")"
[ "$completa" = "$mitades" ] || malo "la union de las mitades no es la bateria entera: completa=[$completa] mitades=[$mitades]"

caso "un test NUEVO que nadie listo cae en 'rapidos' (default seguro), nunca en el limbo"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part/tests/test_recien_agregado.sh"
out="$(SAIKIT_PARTICION=rapidos bash "$run_sh" "$SANDBOX/part" 2>&1)"
printf '%s' "$out" | grep -q 'PASS: test_recien_agregado' || malo "un test sin listar debe correr en la mitad rapida: $out"
rm -f "$SANDBOX/part/tests/test_recien_agregado.sh"

caso "SAIKIT_PARTICION invalida => corta y NO corre nada"
out="$(SAIKIT_PARTICION=medios bash "$run_sh" "$SANDBOX/part" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "una particion invalida no puede cerrar en verde: $out"
printf '%s' "$out" | grep -q 'PASS: test_' && malo "corrio tests con una particion invalida: $out"

caso "una mitad que no corre NINGUN test falla (lista huerfana), no cierra en verde"
# El modo de falla que la particion podria introducir: renombrar un test lento
# deja la lista huerfana y ese job quedaria verde sin haber corrido nada.
mkdir -p "$SANDBOX/part-huerfana/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part-huerfana/tests/test_rapido_uno.sh"
out="$(SAIKIT_PARTICION=lentos bash "$run_sh" "$SANDBOX/part-huerfana" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "una mitad vacia no puede reportar verde: $out"
printf '%s' "$out" | grep -qi 'ningun test' || malo "no dice que la mitad no corrio nada: $out"

caso "una mitad cuyos tests se saltan TODOS (sin ejecutor) tampoco cierra en verde"
# Greptile (PR #101): con el contador de skips en la guardia y `corridos == 0`
# no disparaba — el job cerraba `OK (0 tests)`, verde sin haber probado nada.
# Desde 18.16 los skips son "sin ejecutor" (nadie los corre), y la guardia
# sigue mirando SOLO `corridos`.
mkdir -p "$SANDBOX/part-solo-skip/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part-solo-skip/tests/test_nadie.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SANDBOX/part-solo-skip/tests/test_gate_mutations.sh"
out="$(SAIKIT_TESTS_SIN_EJECUTOR='test_nadie' SAIKIT_PARTICION=rapidos bash "$run_sh" "$SANDBOX/part-solo-skip" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || malo "una mitad con todo salteado cerro en verde: $out"
printf '%s' "$out" | grep -qi 'ningun test' || malo "no dice que no corrio nada: $out"
printf '%s' "$out" | grep -q 'SKIP (sin ejecutor): test_nadie' || malo "el skip se sigue listando: $out"

if [ "$fail" -ne 0 ]; then
  echo "test_runner_guards: FAIL" >&2
  exit 1
fi
echo "test_runner_guards: OK"
