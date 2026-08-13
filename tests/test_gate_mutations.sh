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
G1|host_sin_llave|el estado se vuelve a llavear sin HOST (A y B colapsan al mismo path)
G2|runner_sin_pytest|pytest sale de la lista de runners de verificacion
G2|sin_guardia_de_falla|un runner que fallo tambien acredita verificacion
G2|falla_assertion_quitada|AssertionError deja de matchear y un runner que revento por asercion vuelve a acreditarse
G2|falla_failed_quitada|la vía A de failure_signal (digito no-cero antes de failed/failing/failures/errors) se neutraliza
G2|falla_tsc_quitada|el patron error TS[0-9] deja de detectar fracasos de tsc
G2|falla_phpunit_quitada|la vía B (failures/errors: N) deja de matchear
G2|falla_cs_quitada|el grep case-sensitive de fallas se desactiva y cargo/go vuelven a acreditarse
G2|falla_go_quitada|la rama FAIL[^a-zA-Z] del CS se neutraliza y go vuelve a acreditarse (cargo sigue detectado por test result: FAILED)
G2|falla_frontera_aflojada|la frontera [1-9] se afloja a [0-9] y 0 failed se toma como fracaso
G2|falla_excepciones_sin_dospuntos|se quita el `:` despues de las excepciones y un runner exitoso con TypeError/etc. en el comando vuelve a falsamente NO acreditar
G2|estado_sin_turno_armado|un evento de herramienta crea estado sin turno armado
G2|runner_sin_frontera|las fronteras de palabra del runner se quitan
G2|runner_frontera_sin_punto_de_frase|un runner al final de una frase deja de contar
G2|redaccion_quitada|la redaccion de credenciales se desactiva y el secreto vuelve al log
G2|skip_sin_espanol|un skip en espanol (no corri) deja de contar y el vivo zcode vuelve a bloquear
G3|reviewer_siempre_visto|el gate del reviewer nunca se reporta como faltante
G3|orden_no_se_exige|la secuencia deja de exigir el orden entre los tres roles
G3|secuencia_tambien_en_cursor|la secuencia se exige en cualquier host, no solo claude
G3|subagent_type_greedy|el rol se vuelve a leer con el lector greedy del payload crudo
G3|tool_input_no_se_acota|el escaner deja de exigir que la clave sea de tool_input
G3|agent_type_no_se_lee|el rol de los eventos internos (agent_type) deja de leerse
G3|target_sin_claudecode|el fallback CLAUDECODE=1 se anula y TARGET queda vacio en produccion
G4|retro_no_se_exige|la etiqueta Retro deja de pedirse
G4|etiqueta_sin_frontera|la etiqueta se acepta con cualquier caracter delante
G4|pausa_no_se_reconoce|la pausa declarada deja de reconocerse
G4|canal_payload_crudo|el canal payload vuelve al lector greedy del vendor sin decodificar
G4|canal_transcript_vacio|el canal transcript se ignora y no devuelve texto del asistente
G4|texto_incluye_tool_result|el walker deja de exigir role:assistant y acepta mensajes user
G4|texto_incluye_tool_use|el walker deja de exigir type:text y acepta thinking/tool_use
G4|transcript_sin_containment|la contencion de transcript_path se anula y se vuelve a leer cualquier ruta
G4|containment_sin_resolver|la contencion compara la ruta cruda en vez de resolverla con cd+pwd
G5|presupuesto_infinito|el presupuesto pasa de 2 ciclos a 99
G5|presupuesto_no_limpia|el presupuesto agotado deja de limpiar el estado
G6|cursor_no_se_distingue|cursor deja de tener contrato de salida propio
G3|zcode_sin_target|el fallback ZCODE_* se anula y TARGET queda vacio en zcode (la secuencia no se exige)
G4|phase_sin_camel|la lectura de hookEventName se anula y un Stop camel-only cae a "tool" (stop_gate no corre)
G5|budget_zcode_sigue_0|el exit 2 del budget en zcode vuelve a exit 0 (continue:false es ignorado)
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
# Task 5.3 (A4-cross-host): anula el segmento HOST de PROJECT_DIR, devolviendolo
# a STATE_ROOT/PROJECT_KEY. Sin HOST, dos hosts sobre el mismo $0 y la misma
# sesion colapsan al mismo harness-state.env (A y B se pisan). Atrapada por
# caso_g1_dos_hosts_mismo_repo_no_comparten_estado. Sin escapar los `$` (BRE:
# literal a mitad de patron) y con `#` de delimitador para no chocar con las
# barras del path.
mut_host_sin_llave()            { sed 's#PROJECT_DIR="\$STATE_ROOT/\$HOST/\$PROJECT_KEY"#PROJECT_DIR="$STATE_ROOT/$PROJECT_KEY"#'; }

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
# Quita el tramo ES de VERIFY_SKIP_RE. El catch es caso_g2_excusa_espanol_no_reclama
# (el recibo del vivo zcode). skipped/not run siguen, el resto de G2 no se rompe.
mut_skip_sin_espanol() { sed 's/|no corri.*sin tests//'; }
# Las mutaciones del arreglo de A11 (Task 3.8). El hook ahora tiene DOS regex
# (FAILURE_SIGNAL_RE_CI case-insensitive y FAILURE_SIGNAL_RE_CS case-sensitive);
# cada mutacion nueva aisla UNA rama de esos regex y se acredita a SU caso en
# CASOS_G2 (regla "una mutacion por caso propio"). mut_sin_guardia_de_falla
# (la original) sigue apuntando a `command not found`: rama viva, DoD exige
# conservarla, acreditada a caso_g2_runner_no_encontrado_no_marca. Su comentario
# viejo deca "no se muta exitCode porque es codigo muerto"; tras la 3.8 exitCode
# ya ni esta en el hook (se retiro), pero la mutacion sigue siendo valida.
mut_sin_guardia_de_falla()   { sed 's/command not found/command not found NUNCA/'; }
# falla_assertion_quitada: neutraliza AssertionError:|AssertionFailedError: del CI.
# Atrapa caso_g2_runner_fallido_forma_real (el invertido): su stderr es
# `AssertionError: expected true to equal false`; al quitar esa rama, ninguna
# otra del CI/CS matchea -> verified vuelve a 1 -> el caso (que espera 0) da rojo.
# OJO: tras el fix H2 (exigir `:`) los literales en el hook llevan `:`.
mut_falla_assertion_quitada() { sed 's/AssertionError:|AssertionFailedError:/ZZZ_NUNCA_Z/'; }
# falla_failed_quitada: afloja la frontera del digito de vía A `[1-9]` a `[A-Z]`
# (exige una mayuscula antes del digito, imposible en `1 failed`). Atrapa
# caso_g2_runner_fallido_pytest_summary_no_marca. OJO: sed sin `g` cambia SOLO la
# primera ocurrencia de `[1-9]` (vía A); vía B (al final del CI) queda intacta,
# por lo que caso_g2_runner_fallido_phpunit_no_marca no se ve afectado.
mut_falla_failed_quitada()    { sed 's/\[1-9\]/[A-Z]/'; }
# falla_tsc_quitada: cambia `error TS[0-9]` por `error TS_NUNCA`. Atrapa
# caso_g2_runner_fallido_tsc_no_marca.
mut_falla_tsc_quitada()       { sed 's/error TS\[0-9\]/error TS_NUNCA/'; }
# falla_phpunit_quitada: cambia el separador `[=:]` de vía B por `[Z]` (imposible
# en `Failures: 1`, que usa `:`). Atrapa caso_g2_runner_fallido_phpunit_no_marca.
# NO toca vía A (caso_g2_runner_fallido_pytest_summary_no_marca sigue matcheando).
mut_falla_phpunit_quitada()   { sed 's/(failures?|errors?)\[=:\]/(ZZ_NUNCA_ZZ)[Z]/'; }
# falla_cs_quitada: neutraliza el segundo grep (CS entero) cambiando el nombre
# de la constante referenciada. Atrapa caso_g2_runner_fallido_cargo_no_marca
# (tambien haria rojo al go, pero el driver corta en el primero; cargo va antes
# en CASOS_G2). H3 (cross-review codex): por eso se agrego mut_falla_go_quitada
# abajo, que aísla la rama FAIL[^a-zA-Z] del CS para que go tenga SU mutacion.
mut_falla_cs_quitada()        { sed 's/"\$FAILURE_SIGNAL_RE_CS"/"CS_NUNCA_ZZZ"/'; }
# falla_go_quitada: neutraliza SOLO la rama FAIL[^a-zA-Z] del CS (la que go usa),
# sin tocar test result: FAILED (la que cargo usa). Atrapa caso_g2_runner_fallido_go_no_marca.
# Asi cada caso CS (cargo / go) tiene su mutacion propia, y mut_falla_cs_quitada
# queda acreditada SOLO a cargo (no compartida con go).
mut_falla_go_quitada()        { sed 's/FAIL\[\^a-zA-Z\]/FAIL_NUNCA_Z/'; }
# falla_frontera_aflojada: cambia `[1-9]` a `[0-9]` GLOBALMENTE (con `g`). Así vía A
# matchea `0 failed` (antes no) y vía B matchea `Failures: 0`. Atrapa
# caso_g2_runner_pasa_0_failed_sigue_acreditado (el negativo): su stderr
# `5 passed, 0 failed` pasa a marcar fracaso -> verified=0 -> el caso (que espera
# 1) da rojo. Los casos que ya matchean con `[1-9]` siguen matcheando; el
# invertido (AssertionError, sin digitos junto a "failed") no se ve afectado.
mut_falla_frontera_aflojada() { sed 's/\[1-9\]/[0-9]/g'; }
# falla_excepciones_sin_dospuntos (H2, cross-review codex): quita el `:` despues
# de las 6 excepciones (AssertionError:/SyntaxError:/TypeError:/etc.) cambiando
# `rror:` por `rror`. Atrapa caso_g2_runner_pasa_typeerror_en_comando_sigue_acreditado:
# sin el `:`, el regex CI vuelve a matchear `typeerror` dentro del nombre del
# archivo en el comando (`test_typeerror.py`), y el runner exitoso pasa a
# verified=0 -> el caso (que espera 1) da rojo. NO afecta al invertido
# (`AssertionError: expected...` sigue matcheando `AssertionError` sin `:`,
# porque el substring sigue presente). `s/rror:/rror/g` es seguro: las unicas
# ocurrencias de `rror:` en el hook son las 6 excepciones; `error TS[0-9]` lleva
# espacio despues de `error` y `Traceback (...)` no tiene `rror:`.
mut_falla_excepciones_sin_dospuntos() { sed 's/rror:/rror/g'; }
mut_estado_sin_turno_armado(){ sed 's/if \[ ! -f "\$STATE_PATH" \]; then emit_allow; fi/if false; then emit_allow; fi/'; }

mut_reviewer_siempre_visto()      { sed 's/\*",reviewer,"\*) ;;/*) ;;/'; }
mut_orden_no_se_exige()           { sed "s/'implementer\.\*verifier\.\*reviewer'/'implementer|verifier|reviewer'/"; }
mut_secuencia_tambien_en_cursor() { sed 's/if \[ "\$TARGET" = "claude" \]; then/if true; then/'; }
# Las dos mitades del arreglo de A1 (Task 3.1), una mutacion cada una: volver al
# lector greedy sobre el payload crudo, y dejar que el escaner tome la clave en
# cualquier objeto en vez de solo en `tool_input` de primer nivel.
mut_subagent_type_greedy()   { sed 's/json_tool_input_string subagent_type/json_string_field subagent_type/'; }
mut_tool_input_no_se_acota() { sed 's/depth == 2 \&\& clave1 == "tool_input" \&\& clave == want/clave == want/'; }
# Las dos mitades del arreglo de A9+A10 (Task 3.7), una mutacion cada una y cada
# una acreditada a su caso. La primera neutraliza el fallback a agent_type
# top-level: los eventos internos (que llegan al gate) dejan de registrar el
# rol -- lo atrapa caso_g3_agent_type_cuenta (el invertido), que va antes en
# CASOS_G3. Deja `subagent="$(true)"`, que bash -n acepta y devuelve vacio.
# La segunda anula el fallback CLAUDECODE=1 cambiando el valor comparado: asi
# CLAUDECODE=1 deja de matchear, TARGET vuelve a quedar vacio en produccion y la
# secuencia no se exige -- lo atrapa caso_g3_target_por_claudecode_fallback. NO
# se muta a `[ false ]`: `test` con un unico argumento no vacio da VERDADERO, o
# sea que volveria el fallback incondicional y ningun caso reaccionaria
# (CORRECCION 4 del plan). Cambiar el valor no toca la estructura de corchetes
# ni mete backslashes (la trampa de MSYS2 de :128-131).
mut_agent_type_no_se_lee()   { sed 's/json_top_level_string agent_type/true/'; }
mut_target_sin_claudecode()  { sed 's/"$CLAUDECODE" = "1"/"$CLAUDECODE" = "0"/'; }

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
# Las dos mitades del arreglo de A6 (Task 3.6), una mutacion cada una y cada una
# acreditada a su caso. La primera neutraliza la contencion (el hook vuelve a leer
# cualquier transcript_path); la segunda la deja pero comparando el string crudo
# en vez de resolverlo con cd+pwd -- que es lo que apaga el canal transcript en
# toda la produccion Windows (C:\\Users\\ nunca empieza con /c/Users/) y lo que
# deja pasar un traversal con .. . Ambas dejan el if con cuerpo y bash -n pasa.
# Sin escapar el `$` (BRE: literal a mitad de patron) ni meter mas backslashes de
# la cuenta: MSYS2 corrompe los backslashes en literales de sed (documentado en
# :128-131); la forma del plan con \&\& y \| se probo a mano y muta de verdad.
mut_transcript_sin_containment() { sed 's/transcript_en_perfil "$transcript_path"/true/'; }
mut_containment_sin_resolver()   { sed 's|_tp_dir="$(cd "$(dirname "$1")" 2>/dev/null \&\& pwd)" \|\| _tp_dir=""|_tp_dir="$(dirname "$1")"|'; }

mut_presupuesto_infinito() { sed 's/^MAX_CYCLES=2$/MAX_CYCLES=99/'; }
# Cuarta clausula de A4: el presupuesto agotado tiene que limpiar el estado. A
# diferencia de E2, a E4 si se le puede borrar el rm directo: su if tambien lleva
# `emit_budget_exhausted`, asi que borrar el rm no deja el if vacio (que bash -n
# rechazaria). Se ancla al comentario inline `# A4-c4 presupuesto` porque las tres
# lineas rm son casi identicas; sin el ancla el sed se llevaria la de E2 o la del
# cierre limpio de :959.
mut_presupuesto_no_limpia() { sed '/rm -f.*RN_ORDER_PATH.*# A4-c4 presupuesto/d'; }

mut_cursor_no_se_distingue() { sed 's/if \[ "\$TARGET" = "cursor" \]; then/if false; then/'; }

# Task 5.4 — tres mutaciones, cada una acreditada a su caso. El patron
# ${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-} aparece en 3 sitios (HOST, TARGET,
# budget); cada sed acota con contexto unico para no tocar los otros dos.
# zcode_sin_target: anula la CONDICION del bloque TARGET (lleva `[ -z "$TARGET" ] &&`
# delante, que HOST/budget no tienen). Caso: caso_g3_target_por_zcode_fallback.
mut_zcode_sin_target()      { sed 's/\[ -z "$TARGET" \] && \[ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" \]; then/[ -z "$TARGET" ] \&\& false; then/'; }
# phase_sin_camel: anula la lectura de hookEventName. Caso: caso_g4_stop_camel_solo_bloquea
# (un Stop camel-only debe llegar a stop_gate; sin camel cae a "tool" y no bloquea).
mut_phase_sin_camel()       { sed 's/event="$(json_top_level_string hookEventName)"/event=""/'; }
# budget_zcode_sigue_0: el exit 2 del budget en zcode vuelve a exit 0. Caso:
# caso_g5_presupuesto_zcode_exit2. {n;} edita la linea DESPUES del comentario 5.4
# del budget (donde vive el exit 2), sin tocar el exit 2 del gate_failure.
mut_budget_zcode_sigue_0()  { sed '/saikit-5.4-zcode-budget/s/exit 2/exit 0/'; }

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
