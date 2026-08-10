#!/usr/bin/env bash
# Task 1.3 — mutation-test: la prueba de que la suite de comportamiento ata algo.
#
# EL PROBLEMA QUE RESUELVE. Una suite de tests puede estar entera en verde y no
# probar nada: basta con que sus afirmaciones miren para otro lado. Contra un
# hook que ya funciona eso es invisible — todo pasa, que es justo lo que se
# esperaba. La unica forma de saberlo es ROMPER el hook a proposito y exigir que
# la suite se de cuenta.
#
# COMO. Por cada gate se toma una copia del hook vivo, se rompe LA CONDICION de
# ese gate con un `sed`, y se corren los casos de ese gate. Si ninguno se pone
# rojo, la suite no ata ese gate y esta bateria falla. Eso es la declaracion de
# mutation-test que pide la DoD de la Task 1.3: escrita como codigo que corre,
# no como una frase en un reporte que nadie vuelve a verificar.
#
# La mitad que falta la aporta `tests/test_gate_behavior.sh`, que corre los
# MISMOS casos contra el hook sin mutar y los exige todos verdes. Verde sin
# mutar + rojo con la condicion rota = el caso depende de esa condicion. Las dos
# baterias estan en `tests/run.sh`; ninguna de las dos sola alcanza.
#
# Tres cosas que se verifican de la mutacion en si, porque una mutacion que no
# muta convertiria esta bateria en teatro:
#   1. que exista la funcion que la aplica;
#   2. que el archivo cambie de verdad (si no, el `sed` quedo obsoleto porque el
#      hook cambio de forma);
#   3. que el resultado siga parseando (`bash -n`): un hook que no arranca hace
#      fallar cualquier caso y no probaria nada.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/hook_lab.sh"
. "$here/lib/gate_cases.sh"

. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_gate_mutations")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

# ---------------------------------------------------------------- catalogo
# gate|nombre|que rompe
MUTACIONES="
G1|sentinel_acepta_cualquier_prompt|el sentinel pasa a matchear cualquier texto
G1|sentinel_sin_guardia|se arma sin llegar a consultar el sentinel
G2|runner_sin_pytest|pytest sale de la lista de runners de verificacion
G2|sin_guardia_de_falla|un runner que fallo tambien acredita verificacion
G2|estado_sin_turno_armado|un evento de herramienta crea estado sin turno armado
G3|reviewer_siempre_visto|el gate del reviewer nunca se reporta como faltante
G3|orden_no_se_exige|la secuencia deja de exigir el orden entre los tres roles
G3|secuencia_tambien_en_cursor|la secuencia se exige en cualquier host, no solo claude
G4|retro_no_se_exige|la etiqueta Retro deja de pedirse
G4|etiqueta_sin_frontera|la etiqueta se acepta con cualquier caracter delante
G4|pausa_no_se_reconoce|la pausa declarada deja de reconocerse
G5|presupuesto_infinito|el presupuesto pasa de 2 ciclos a 99
G6|cursor_no_se_distingue|cursor deja de tener contrato de salida propio
"

# Cada mutacion es un filtro de stdin a stdout. Se rompe LA CONDICION del gate,
# no el texto del mensaje: un caso que solo mirara el texto pasaria por alto una
# condicion invertida, y esta bateria existe para detectar exactamente eso.

mut_sentinel_acepta_cualquier_prompt() { sed "s/^SAIKIT_SENTINEL_RE=.*/SAIKIT_SENTINEL_RE='.*'/"; }
mut_sentinel_sin_guardia()             { sed 's/^.*grep -Eq "\$SAIKIT_SENTINEL_RE".*$/  if false; then/'; }

mut_runner_sin_pytest()      { sed 's/|pytest|/|pytestNUNCA|/'; }
# Se rompe la clausula `command not found`, no la de `exitCode`: contra payloads
# reales esa segunda ya esta muerta (el tool_response de Bash no trae el campo,
# medido 59 de 59 en la Task 1.4). Mutar codigo muerto no prueba nada — la
# mutacion tiene que caer sobre la condicion que hoy DECIDE algo.
mut_sin_guardia_de_falla()   { sed 's/command not found/command not found NUNCA/'; }
mut_estado_sin_turno_armado(){ sed 's/if \[ ! -f "\$STATE_PATH" \]; then emit_allow; fi/if false; then emit_allow; fi/'; }

mut_reviewer_siempre_visto()      { sed 's/\*",reviewer,"\*) ;;/*) ;;/'; }
mut_orden_no_se_exige()           { sed "s/'implementer\.\*verifier\.\*reviewer'/'implementer|verifier|reviewer'/"; }
mut_secuencia_tambien_en_cursor() { sed 's/if \[ "\$TARGET" = "claude" \]; then/if true; then/'; }

mut_retro_no_se_exige()    { sed 's/if ! has_receipt_label "Retro"/if false \&\& ! has_receipt_label "Retro"/'; }
mut_etiqueta_sin_frontera(){ sed 's/(^|\[^\[:alpha:\]\])/(^|.)/'; }
mut_pausa_no_se_reconoce() { sed "s/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED NUNCA'/"; }

mut_presupuesto_infinito() { sed 's/^MAX_CYCLES=2$/MAX_CYCLES=99/'; }

mut_cursor_no_se_distingue() { sed 's/if \[ "\$TARGET" = "cursor" \]; then/if false; then/'; }

# ------------------------------------------------------------ costura de testeo
# `tests/test_gate_mutations_guards.sh` inyecta un catalogo propio para
# comprobar que las guardias de mas abajo REALMENTE rompen la corrida. Sin esa
# comprobacion, "13 de 13 mutaciones atrapadas" no distingue una suite que ata
# los gates de un driver que no sabe ponerse en rojo. Solo se activa con la
# variable puesta; en una corrida normal no cambia nada.
if [ -n "${SAIKIT_MUTACIONES_LIB:-}" ] && [ -r "${SAIKIT_MUTACIONES_LIB:-}" ]; then
  . "$SAIKIT_MUTACIONES_LIB"
fi
if [ -n "${SAIKIT_MUTACIONES:-}" ]; then
  MUTACIONES="$SAIKIT_MUTACIONES"
fi

# ------------------------------------------------------------------ la corrida
tmp="$(mktemp -d "${TMPDIR:-/tmp}/saikit-mut-XXXXXX")" || exit 1
HOOK_BAJO_PRUEBA="$vivo"
if ! lab_init; then
  echo "test_gate_mutations: FAIL — no se pudo montar el banco de pruebas" >&2
  rm -rf "$tmp"
  exit 1
fi
trap 'lab_fin; rm -rf "$tmp"' EXIT

fail=0
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
declaracion=""

while IFS='|' read -r gate nombre descripcion; do
  [ -n "$gate" ] || continue

  if ! command -v "mut_$nombre" >/dev/null 2>&1; then
    malo "$nombre: no existe la funcion mut_$nombre"
    continue
  fi

  mutado="$tmp/hook-$nombre.sh"
  "mut_$nombre" < "$vivo" > "$mutado"

  if cmp -s "$vivo" "$mutado"; then
    malo "$nombre: la mutacion no cambio nada del hook — el sed quedo obsoleto"
    continue
  fi
  if ! bash -n "$mutado" 2>/dev/null; then
    malo "$nombre: el hook mutado no parsea; asi no prueba nada"
    continue
  fi

  lab_hook_swap "$mutado"

  atrapada=""
  for caso in $(casos_de_gate "$gate"); do
    if ! correr_caso "$caso" > "$tmp/salida-caso" 2>&1; then
      atrapada="$caso"
      break
    fi
  done

  if [ -n "$atrapada" ]; then
    printf '  %s  %s\n' "$gate" "$descripcion"
    printf '      lo atrapa: %s\n' "$atrapada"
    declaracion="$declaracion$gate|$descripcion|$atrapada
"
  else
    malo "$gate: ningun caso detecto que [$descripcion]"
    printf '          La suite de comportamiento no ata esa condicion: con el gate\n' >&2
    printf '          roto sigue toda en verde. Hay que agregar el caso que falta.\n' >&2
  fi
done <<EOF
$MUTACIONES
EOF

# La declaracion que pide la DoD, emitida por la corrida y no escrita a mano:
# que condicion se rompio y que caso se dio cuenta.
printf '\n  --- mutation-test declarado (gate | condicion rota | caso que la atrapa)\n'
printf '%s' "$declaracion" | sed 's/^/  /'

if [ "$fail" -ne 0 ]; then
  echo "test_gate_mutations: FAIL" >&2
  exit 1
fi
echo "test_gate_mutations: OK"
