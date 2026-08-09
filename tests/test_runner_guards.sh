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

if [ "$fail" -ne 0 ]; then
  echo "test_runner_guards: FAIL" >&2
  exit 1
fi
echo "test_runner_guards: OK"
