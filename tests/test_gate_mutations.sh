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

if [ ! -r "$here/lib/hook_bajo_prueba.sh" ]; then
  echo "test_gate_mutations: unknown — falta tests/lib/hook_bajo_prueba.sh; no se pudo resolver que archivo probar." >&2
  exit 3
fi
. "$here/lib/hook_bajo_prueba.sh"
vivo="$(resolver_hook_bajo_prueba "$here/.." "test_gate_mutations")" \
  || exit "$SAIKIT_EXIT_UNKNOWN"

# ---------------------------------------------------------------- catalogo
# gate|nombre|que rompe
MUTACIONES="
G1|sentinel_acepta_cualquier_prompt|el sentinel pasa a matchear cualquier texto
G1|sentinel_sin_guardia|se arma sin llegar a consultar el sentinel
G1|session_sin_llave|el estado se vuelve a llavear solo por proyecto (sin sesion)
G1|desarmar_quita_borrado|el desarme deja de borrar el estado en prompt sin sentinel
G1|session_id_greedy|session_id se vuelve a leer con el lector greedy del payload crudo
G2|runner_sin_pytest|pytest sale de la lista de runners de verificacion
G2|sin_guardia_de_falla|un runner que fallo tambien acredita verificacion
G2|estado_sin_turno_armado|un evento de herramienta crea estado sin turno armado
G2|runner_sin_frontera|las fronteras de palabra del runner se quitan
G2|runner_frontera_sin_punto_de_frase|un runner al final de una frase deja de contar
G2|redaccion_quitada|la redaccion de credenciales se desactiva y el secreto vuelve al log
G3|reviewer_siempre_visto|el gate del reviewer nunca se reporta como faltante
G3|orden_no_se_exige|la secuencia deja de exigir el orden entre los tres roles
G3|secuencia_tambien_en_cursor|la secuencia se exige en cualquier host, no solo claude
G3|subagent_type_greedy|el rol se vuelve a leer con el lector greedy del payload crudo
G3|tool_input_no_se_acota|el escaner deja de exigir que la clave sea de tool_input
G4|retro_no_se_exige|la etiqueta Retro deja de pedirse
G4|etiqueta_sin_frontera|la etiqueta se acepta con cualquier caracter delante
G4|pausa_no_se_reconoce|la pausa declarada deja de reconocerse
G4|canal_payload_crudo|el canal payload vuelve al lector greedy del vendor sin decodificar
G4|canal_transcript_vacio|el canal transcript se ignora y no devuelve texto del asistente
G4|texto_incluye_tool_result|el walker deja de exigir role:assistant y acepta mensajes user
G4|texto_incluye_tool_use|el walker deja de exigir type:text y acepta thinking/tool_use
G5|presupuesto_infinito|el presupuesto pasa de 2 ciclos a 99
G5|presupuesto_no_limpia|el presupuesto agotado deja de limpiar el estado
G6|cursor_no_se_distingue|cursor deja de tener contrato de salida propio
"

# Cada mutacion es un filtro de stdin a stdout. Se rompe LA CONDICION del gate,
# no el texto del mensaje: un caso que solo mirara el texto pasaria por alto una
# condicion invertida, y esta bateria existe para detectar exactamente eso.

mut_sentinel_acepta_cualquier_prompt() { sed "s/^SAIKIT_SENTINEL_RE=.*/SAIKIT_SENTINEL_RE='.*'/"; }
mut_sentinel_sin_guardia()             { sed 's/^.*grep -Eq "\$SAIKIT_SENTINEL_RE".*$/  if false; then/'; }

# Las dos mutaciones del arreglo de A4 (Task 3.4, clausulas 1 y 2). Cada una
# neutraliza una clausula y tiene que quedar acreditada a SU caso en la
# declaracion que emite la corrida.
#
# session_sin_llave ataca la asignacion UNICA de STATE_DIR por sesion (volver a
# PROJECT_DIR colapsa dos sesiones del mismo repo al mismo slot = A4). Si en
# cambio se cachea LAB_ESTADO_PATH desde el hook sano (como lab_hook_swap hacia
# antes del arreglo de la CORRECCION 4), la ruta descubierta queda apuntando al
# hoyo y el credito se lo roba caso_g1_arma_con_sentinel; por eso el lab
# re-descubre la ruta tras cada swap.
mut_session_sin_llave()        { sed 's#STATE_DIR="\$PROJECT_DIR/\$SESSION_KEY"#STATE_DIR="$PROJECT_DIR"#'; }
# desarmar_quita_borrado neutraliza la CONDICION unica de E2 (no borra el rm): el
# if interno de E2 tiene SOLO el rm como cuerpo, asi que borrarlo deja
# `if ...; then fi` vacio, que `bash -n` rechaza (guardia 3 de esta bateria).
# Cambiar la condicion a `false` deja el rm inerte y el if con cuerpo. La
# condicion de E2 es unica (PHASE=prompt && -f STATE_PATH); E4 no la comparte.
mut_desarmar_quita_borrado()   { sed 's/if \[ "\$PHASE" = "prompt" \] && \[ -f "\$STATE_PATH" \]; then/if false; then/'; }
# session_id_greedy es el gemelo de mut_subagent_type_greedy para session_id:
# volver al lector greedy del payload crudo tomaba la ULTIMA ocurrencia de la
# clave (un session_id anidado en session_crons) y re-llaveaba la ruta a mitad
# de turno. Hallazgo [media] de la cross-review codex sobre la 3.4.
mut_session_id_greedy()         { sed 's/json_top_level_string session_id/json_string_field session_id/'; }

mut_runner_sin_pytest()      { sed 's/|pytest|/|pytestNUNCA|/'; }
# Las dos mitades del arreglo de A3 (Task 3.3). La primera revierte el wrapper
# a la lista pelada en ambos greps; la segunda quita la alternativa de
# punto-de-frase, que es lo que separa `pytest.` (prosa) de `pytest.log` (archivo).
mut_runner_sin_frontera()    { sed 's/^TEST_RUNNER_WORD_RE=.*/TEST_RUNNER_WORD_RE="$TEST_RUNNER_RE"/'; }
mut_runner_frontera_sin_punto_de_frase() { awk '{gsub(/\\\.\(/, "XX("); print}'; }
# La redaccion de credenciales (Task 3.5 / A5): se revierte en el call site de
# mark_evidence, de modo que $detail vuelve a escribirse crudo. Sin escapar el
# `$` (BRE: literal a mitad de patron) ni meter backslashes (la trampa de
# MSYS2 documentada en :128-131). La mutacion ademas FIJA LA UBICACION del
# arreglo: movida al call site, el sed no matchea y salta la guardia 2 del
# driver ("la mutacion no cambio nada del hook").
mut_redaccion_quitada() { sed 's/"$(redact_secrets "$detail")"/"$detail"/'; }
# Se rompe la clausula `command not found`, no la de `exitCode`: contra payloads
# reales esa segunda ya esta muerta (el tool_response de Bash no trae el campo,
# medido 59 de 59 en la Task 1.4). Mutar codigo muerto no prueba nada — la
# mutacion tiene que caer sobre la condicion que hoy DECIDE algo.
mut_sin_guardia_de_falla()   { sed 's/command not found/command not found NUNCA/'; }
mut_estado_sin_turno_armado(){ sed 's/if \[ ! -f "\$STATE_PATH" \]; then emit_allow; fi/if false; then emit_allow; fi/'; }

mut_reviewer_siempre_visto()      { sed 's/\*",reviewer,"\*) ;;/*) ;;/'; }
mut_orden_no_se_exige()           { sed "s/'implementer\.\*verifier\.\*reviewer'/'implementer|verifier|reviewer'/"; }
mut_secuencia_tambien_en_cursor() { sed 's/if \[ "\$TARGET" = "claude" \]; then/if true; then/'; }
# Las dos mitades del arreglo de A1 (Task 3.1), una mutacion cada una: volver al
# lector greedy sobre el payload crudo, y dejar que el escaner tome la clave en
# cualquier objeto en vez de solo en `tool_input` de primer nivel.
mut_subagent_type_greedy()   { sed 's/json_tool_input_string subagent_type/json_string_field subagent_type/'; }
mut_tool_input_no_se_acota() { sed 's/depth == 2 \&\& clave1 == "tool_input" \&\& clave == want/clave == want/'; }

mut_retro_no_se_exige()    { sed 's/if ! has_receipt_label "Retro"/if false \&\& ! has_receipt_label "Retro"/'; }
mut_etiqueta_sin_frontera(){ sed 's/(^|\[^\[:alpha:\]\])/(^|.)/'; }
mut_pausa_no_se_reconoce() { sed "s/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED NUNCA'/"; }
# Las cuatro mitades del arreglo de A2+A8 (Task 3.2), una mutacion cada una.
# Las dos primeras mutan la LLAMADA en stop_gate (no el awk interno) porque
# MSYS2/Git Bash corrompe los backslashes en literales de sed — cambiar la
# funcion llamada es equivalente para lo que el caso prueba y no tiene ese
# problema. Las dos ultimas mutan la condicion del walker directamente.
mut_canal_payload_crudo()    { sed 's/$(assistant_text_payload)/$(json_string_field last_assistant_message)/'; }
mut_canal_transcript_vacio() { sed 's/| assistant_text_transcript/| true/'; }
mut_texto_incluye_tool_result() { sed 's/c2 == "role" \&\& ultima == "assistant"/c2 == "role"/'; }
mut_texto_incluye_tool_use()    { sed 's/c4 == "type" \&\& ultima == "text"/c4 == "type"/'; }

mut_presupuesto_infinito() { sed 's/^MAX_CYCLES=2$/MAX_CYCLES=99/'; }
# Cuarta clausula de A4: el presupuesto agotado tiene que limpiar el estado. A
# diferencia de E2, a E4 si se le puede borrar el rm directo: su if tambien lleva
# `emit_budget_exhausted`, asi que borrar el rm no deja el if vacio (que bash -n
# rechazaria). Se ancla al comentario inline `# A4-c4 presupuesto` porque las tres
# lineas rm son casi identicas; sin el ancla el sed se llevaria la de E2 o la del
# cierre limpio de :959.
mut_presupuesto_no_limpia() { sed '/rm -f.*RN_ORDER_PATH.*# A4-c4 presupuesto/d'; }

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
