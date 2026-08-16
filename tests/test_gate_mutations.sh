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
G1|prompt_greedy|el prompt vuelve al lector greedy sin decodificar (comillas o \n antes de -saikit no arman / desarman)
G1|fast_no_se_detecta|el lane fast deja de detectarse y todo arma full
G1|session_sin_reglas|la fase session vuelve a salir muda y las reglas permanentes no se inyectan
G1|session_pisa_gate|la emision de reglas deja de acotarse a session y tambien dispara en prompt sin sentinel
G1|fallback_sin_acotar|el fallback al payload crudo deja de acotarse a session y un -saikit en cualquier campo vuelve a armar
G1|frontera_izquierda_floja|la frontera izquierda del sentinel vuelve a aceptar / y -, y una ruta o un flag citado arman
G1|estado_inmortal|la poda del dir de sesion se neutraliza y cada limpieza vuelve a dejar un directorio vacio para siempre
G1|barrido_sin_ttl|el barrido pierde el filtro de edad y se lleva tambien el estado de una sesion hermana VIVA (A4)
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
G2|command_desacotado|command se vuelve a leer del payload entero y un eco en tool_response acredita verificacion
G2|runner_bash_quitada|las ramas del runner bash propio (tests/run.sh) se neutralizan y bash tests/run.sh vuelve a NO acreditar
G2|falla_dotnet_quitada|`failed` sale de la via B del CI y el banner de dotnet (Failed: 1) vuelve a acreditar
G2|falla_gradle_quitada|los literales de gradle salen del CS y BUILD FAILED / FAILURE: Build failed vuelven a acreditar
G2|credito_por_mencion|la guarda de echo/printf se neutraliza y `echo pytest` vuelve a acreditar verificacion
G2|credito_por_tool_name|el credito vuelve a evaluar tool_name y una tool llamada como un runner acredita sin correr nada
G2|cmdpos_no_se_aplica|las llamadas a TEST_RUNNER_CMD_RE se neutralizan y la posicion de comando estricta deja de aplicarse (r1)
G3|reviewer_siempre_visto|el gate del reviewer nunca se reporta como faltante
G3|orden_no_se_exige|la secuencia deja de exigir el orden entre los tres roles
G3|secuencia_tambien_en_cursor|la secuencia se exige en cualquier host, no solo claude
G3|subagent_type_greedy|el rol se vuelve a leer con el lector greedy del payload crudo
G3|tool_input_no_se_acota|el escaner deja de exigir que la clave sea de tool_input
G3|agent_type_no_se_lee|el rol de los eventos internos (agent_type) deja de leerse
G3|target_sin_claudecode|el fallback CLAUDECODE=1 se anula y TARGET queda vacio en produccion
G4|retro_no_se_exige|la etiqueta Retro deja de pedirse
G4|etiqueta_sin_frontera|la etiqueta se acepta con cualquier caracter delante
G4|etiqueta_sin_bold|la alternativa markdown bold se quita y un recibo **Label**: vuelve a bloquear
G4|pausa_no_se_reconoce|la pausa declarada deja de reconocerse
G4|delegado_no_se_reconoce|la escotilla de subagente delegado deja de reconocerse (arreglo 1)
G4|delegado_ignora_recibo|la escotilla DELEGATED deja de exigir que el recibo este ausente (fix cross-review ciclo 1)
G4|escotillas_leen_tail_viejo|las escotillas PAUSED/DELEGATED vuelven a leer el tail entero (texto de turnos anteriores decide)
G4|walker_sin_resets|el walker deja de resetear en_text/en_assistant al cerrar llaves y un valor top-level se cuela como texto del asistente
G4|canal_payload_crudo|el canal payload vuelve al lector greedy del vendor sin decodificar
G4|canal_transcript_vacio|el canal transcript se ignora y no devuelve texto del asistente
G4|texto_incluye_tool_result|el walker deja de exigir role:assistant y acepta mensajes user
G4|texto_incluye_tool_use|el walker deja de exigir type:text y acepta thinking/tool_use
G4|transcript_sin_containment|la contencion de transcript_path se anula y se vuelve a leer cualquier ruta
G4|containment_sin_resolver|la contencion compara la ruta cruda en vez de resolverla con cd+pwd
G5|tool_name_desacotado|tool_name vuelve al lector greedy y un eco en tool_response se lee como la herramienta del evento (marca una edicion que no ocurrio)
G5|presupuesto_infinito|el presupuesto pasa de 2 ciclos a 99
G5|presupuesto_no_limpia|el presupuesto agotado deja de limpiar el estado
G6|cursor_no_se_distingue|cursor deja de tener contrato de salida propio
G3|zcode_sin_target|el fallback ZCODE_* se anula y TARGET queda vacio en zcode (la secuencia no se exige)
G4|phase_sin_camel|la lectura de hookEventName se anula y un Stop camel-only cae a "tool" (stop_gate no corre)
G5|budget_zcode_sigue_0|el exit 2 del budget en zcode vuelve a exit 0 (continue:false es ignorado)
G3|role_fallback_quitada|se saca la escotilla ROLE FALLBACK del gate (D4) y un recibo con la declaracion vuelve a bloquear
G3|fast_no_exime_ceremonia|lane=fast deja de eximir la secuencia (el carril no sirve)
G1|host_codex_sin_rama|la senal explicita TARGET=codex deja de mapear HOST=codex y un turno codex heredando CLAUDECODE=1 vuelve a creerse claude
G3|ceremonia_sin_codex|la rama de ceremonia vuelve a claude-only y el gate queda inerte en codex (D3)
G6|bloqueo_codex_exit2|el bloqueo en target codex vuelve a exit 2, que Codex descarta (el gate vuelve a ser decorativo ahi)
G4|frontera_acepta_comillas|la frontera izquierda vuelve a aceptar comillas y citar el feedback del gate satisface etiquetas
G5|aviso_se_borra_en_fallo|el borrado del aviso RN pendiente vuelve al elif de todo Stop y un Stop que bloquea se lleva el aviso ajeno
G1|host_grok_sin_rama|la senal GROK_HOOK_EVENT deja de mapear HOST=grok y un turno grok heredando CLAUDECODE=1 vuelve a creerse claude (D2)
G1|phase_sin_user_prompt_submit|el literal user_prompt_submit sale del case de PHASE y un envelope real de Grok cae a "tool": nunca arma (D4)
G2|toolresult_veto_quitado|el veto de toolResult.exit_code != 0 se neutraliza y un runner rojo grok vuelve a acreditar verificacion (D5)
G2|toolresult_variantes_quitada|la deteccion de FileNotFound/NoMatchesFound en toolResult se neutraliza (D5, variante)
G2|alias_padre_camel_quitado|el fallback camel del padre (toolInput) se quita y command vuelve a leerse solo de tool_input snake (D4)
G1|stop_sin_filtro_end_turn|el filtro de Stop grok distinto de end_turn se neutraliza y el Stop de cierre vuelve a contar ciclo/tocar estado (D6)
G1|grok_setness_por_valor|la deteccion de GROK_HOOK_EVENT vuelve a exigir valor no-vacio y una senal exportada vacia clasifica por las senales heredadas (r1, Greptile P2)
G3|ceremonia_sin_grok|la rama de ceremonia vuelve a claude|codex y el gate queda inerte en grok (D3, 7.4)
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
# Task 8.1 (C1+C2): devuelve el prompt al lector greedy sin decodificar. Los
# catches son caso_g1_arma_con_comillas_antes_del_sentinel (C1) y
# caso_g1_arma_con_sentinel_en_linea_nueva (C2) — con el greedy, la comilla
# escapada trunca el valor y el \n crudo rompe la frontera del sentinel.
mut_prompt_greedy()             { sed 's/json_top_level_decoded prompt/json_string_field prompt/'; }
# Task 10.1 — las dos mitades del carril fast, una mutacion cada una y cada una
# acreditada a su caso. fast_no_se_detecta neutraliza la DETECCION (todo arma
# full) — lo atrapa caso_g1_fast_arma_con_lane (ningun otro caso de CASOS_G1
# escribe :fast en su prompt, asi que ningun otro reacciona). fast_no_exime_
# ceremonia rompe solo la comparacion del wrap de stop_gate (el armado y el
# campo lane siguen sanos) — lo atrapa caso_g3_fast_cierra_sin_subagentes
# (exit 0 -> 2: la ceremonia vuelve a exigirse con lane=fast).
mut_fast_no_se_detecta()        { sed 's/then lane="fast"; fi/then lane="full"; fi/'; }
mut_fast_no_exime_ceremonia()   { sed 's/!= "fast" ]/!= "fast NUNCA" ]/'; }
# Task 10.6 — las dos mitades de las reglas permanentes, una mutacion cada una.
# session_sin_reglas mata la EMISION (la fase session vuelve a salir muda) — lo
# atrapa caso_g1_session_inyecta_reglas. session_pisa_gate saca el acotamiento a
# session, asi que la emision tambien corre en prompt sin sentinel — lo atrapa
# caso_g1_no_arma_sin_sentinel, que exige stdout VACIO ahi. Esa segunda mitad es
# la razon por la que 10.6 no agrega un caso propio de "prompt sigue mudo": el
# caso que ya existe es la regresion, y la mutacion lo demuestra.
mut_session_sin_reglas()        { sed 's/^      emit_standing_rules$/      :/'; }
mut_session_pisa_gate()         { sed 's/\[ "$PHASE" = "session" \] && \[ "$TARGET" = "claude" \]/[ "$TARGET" = "claude" ]/'; }
# Task 9.4 (C9): revierte el acotamiento del fallback al payload crudo. Sin el,
# un payload sin campo `prompt` busca el sentinel en el PAYLOAD ENTERO y un
# -saikit en un campo de resumen arma la ceremonia — lo atrapa
# caso_g1_prompt_sin_campo_no_arma.
mut_fallback_sin_acotar()       { sed 's/if \[ -z "$prompt_text" \] && \[ "$PHASE" = "session" \]; then/if [ -z "$prompt_text" ]; then/'; }
# Task 9.5 (C10): devuelve la frontera izquierda floja (sin / ni -). Se reemplaza
# la LINEA entera para no tocar de paso el regex del carril :fast, que comparte
# la misma clase de caracteres — si los mutara a los dos, no se sabria cual caso
# reacciona a que. Lo atrapa caso_g1_sentinel_con_frontera.
mut_frontera_izquierda_floja()  { sed "s@^SAIKIT_SENTINEL_RE=.*@SAIKIT_SENTINEL_RE='(^|[^A-Za-z0-9_])-saikit([^A-Za-z0-9_-]|\$)'@"; }
# Task 9.7 (C13) — una mutacion por MITAD. Las dos caen sobre el mismo caso
# (caso_g1_estado_no_se_acumula) porque el arreglo solo sirve completo: podar sin
# barrer deja las sesiones que nunca cerraron, y barrer sin podar deja la del
# turno actual. Cada mutacion pone roja SU mitad del caso.
#   estado_inmortal  -> neutraliza el rmdir: vuelve el dir vacio inmortal.
#   barrido_sin_ttl  -> le saca el filtro de edad al barrido, asi que se lleva
#                       tambien la hermana FRESCA. Esa es la direccion peligrosa
#                       (es A4: borrarle el estado a una sesion viva), y por eso
#                       la mutacion la ataca en vez de solo apagar el barrido.
mut_estado_inmortal()           { sed 's@rmdir "$STATE_DIR"@true "$STATE_DIR"@'; }
mut_barrido_sin_ttl()           { sed 's@ -mmin "+$SAIKIT_STATE_TTL_MIN"@@'; }
# Task 9.6 (C12): saca los dos resets del walker. Con eso en_text/en_assistant
# quedan en 1 para siempre y un valor top-level posterior a `message` vuelve a
# contarse como texto del asistente — lo atrapa caso_g4_fuga_top_level_no_cierra.
mut_walker_sin_resets()         { sed 's@if (depth < 4) en_text = 0@if (0) en_text = 0@; s@if (depth < 2) en_assistant = 0@if (0) en_assistant = 0@'; }

# Nota (actualizada al aterrizar 9.4): el fallback SI tiene mutacion ahora
# (mut_fallback_sin_acotar, arriba), pero cubre el acotamiento a `session`, no lo
# que pasa DENTRO de session. Ese resto — un `summary` de sesion reanudada que
# cite un -saikit viejo hace que la sesion arme y las reglas permanentes no
# salgan — sigue SIN mutacion a proposito: 9.4 conserva el fallback en session
# porque ahi cursor arma de verdad. Queda atado por
# caso_g1_session_con_sentinel_en_summary_arma_y_no_da_reglas, que fija el
# comportamiento de HOY y se pondra rojo el dia que alguien lo cambie.

# Task 9.1 (C6) — una mutacion por via, cada una acreditada a su caso.
#   falla_dotnet_quitada -> saca `failed` de la via B del CI; lo atrapa
#     caso_g2_runner_fallido_dotnet_no_marca.
#   falla_gradle_quitada -> saca los dos literales de gradle del CS; lo atrapa
#     caso_g2_runner_fallido_gradle_no_marca.
mut_falla_dotnet_quitada()   { sed 's@(failures?|errors?|failed)\[=:\]@(failures?|errors?)[=:]@'; }
mut_falla_gradle_quitada()   { sed 's@|FAILURE: Build failed|BUILD FAILED@@'; }

# Task 9.2 (C8): neutraliza la guarda del primer token. Con eso `echo pytest`
# vuelve a acreditar verificacion sin correr nada — lo atrapa
# caso_g2_runner_en_echo_no_marca.
mut_credito_por_mencion()    { sed "s@^ECHO_LEAD_RE=.*@ECHO_LEAD_RE='NUNCA_MATCHEA_ESTO'@"; }

# CodeRabbit PR #22: reemplaza a la retirada `tool_name_desacotado` por una que
# SI es observable. Devuelve `tool_name` a la condicion de credito; con eso una
# tool llamada como un runner acredita verificacion con un comando que no corre
# nada. La atrapa caso_g2_tool_name_runner_con_comando_ajeno_no_marca, que para
# esto necesita un fixture con el tool_name REAL (no un eco en tool_response).
# El ancla NO puede llevar `printf '%s'`: sus comillas simples cortan el sed y
# el `|` siguiente se vuelve una tuberia de shell (medido: `failed: command not
# found`). Se ancla en la parte sin comillas simples.
mut_credito_por_tool_name() { sed 's@"$command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE"@"$tool_name $command_text" | grep -Eiq "$TEST_RUNNER_WORD_RE"@'; }

# Task 10.10: REPUESTA. Se habia retirado al sacar `tool_name` del credito de
# verificacion (9.2), porque ahi dejo de tener detector. Vuelve apuntando a
# donde la propiedad SI es observable: la deteccion de edicion del aviso RN.
# La atrapa caso_g5_tool_name_eco_no_marca_edicion.
mut_tool_name_desacotado()   { sed 's/json_top_level_string tool_name/json_string_field tool_name/'; }

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
# Task 8.1 (C3, clase A1 para la evidencia): devuelven command/tool_name al
# lector greedy del payload entero. Catches: caso_g2_comando_entrecomillado_
# marca_verificado y caso_g2_eco_de_command_en_tool_response_no_marca (command);
# caso_g2_eco_de_tool_name_en_tool_response_no_marca (tool_name).
mut_command_desacotado()   { sed 's/json_tool_input_string command/json_string_field command/'; }
mut_tool_name_desacotado()   { sed 's/json_top_level_string tool_name/json_string_field tool_name/'; }
# RETIRADA (PR #22): `mut_tool_name_desacotado` cambiaba el lector de tool_name
# por el greedy. Dejo de tener detector cuando el credito de verificacion dejo
# de mirar `tool_name` — que fue el arreglo de un agujero REAL (una tool MCP
# llamada como un runner acreditaba sin correr nada). Con el credito fuera, un
# tool_name greedy ya no cambia nada observable ahi: `combined` incluye $INPUT
# entero, asi que la deteccion de fallas tampoco se mueve.
#
# DONDE SI SIGUE IMPORTANDO que el lector este acotado: la deteccion de
# edicion del aviso RN (`^(edit|write|...)$` sobre tool_name). Cubrir ESO con
# un caso vive en la zona de la Task 9.8, que esta tomada por otra sesion — se
# deja anotado ahi en vez de invadirla. Se retira la mutacion en vez de
# dejarla de adorno: una que ningun caso puede atrapar convierte la bateria en
# teatro, que es justo lo que este archivo existe para evitar.
# Task 9.10: neutraliza las DOS ramas nuevas (verbo shell + invocacion directa)
# rompiendo el sufijo tests?/run\.sh que comparten — el resto de TEST_RUNNER_RE
# queda intacto. Lo atrapa caso_g2_runner_bash_run_sh_marca (verde->rojo:
# `bash tests/run.sh` vuelve a verified=0). BRE sin cuantificadores que
# escapar: `?` tras `s` y `\\`+`.` para el `\.` literal del target.
mut_runner_bash_quitada()  { sed 's#tests?/run\\.sh#testsNUNCA/runX.sh#g'; }
# 9.10 r2 (codex r1): neutraliza la APLICACION de la constante en los DOS call
# sites (credito del evento y fallback de prosa) prefijando el patron con un
# literal imposible — "NUNCA_" pegado delante del ancla ^ no puede matchear
# jamas, a diferencia de vaciar la variable (un patron vacio matchea TODO y el
# catch seria el caso equivocado). El RE queda intacto: es el cableado lo que
# se rompe. Lo atrapa caso_g2_runner_bash_run_sh_marca (sin CMD_RE aplicada,
# la forma bash ya no esta en WORD_RE y verified queda en 0).
mut_cmdpos_no_se_aplica()  { sed 's/grep -Eiq "\$TEST_RUNNER_CMD_RE"/grep -Eiq "NUNCA_\$TEST_RUNNER_CMD_RE"/g'; }
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
# NOTA (9.1): el patron incluye `|failed` porque la via B lo gano al agregar
# dotnet. Sin actualizarlo, este sed dejaba de aplicar y la mutacion se volvia
# teatro — lo detecto la suite completa, no el archivo suelto.
mut_falla_phpunit_quitada()   { sed 's/(failures?|errors?|failed)\[=:\]/(ZZ_NUNCA_ZZ)[Z]/'; }
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
# Task 6.4 movio la condicion de la ceremonia de `if [ "$TARGET" = "claude" ]`
# a `case "$TARGET" in claude|codex)`: el sed de esta mutacion se actualiza al
# literal nuevo (el patron `*)` matchea cualquier target, mismo efecto que el
# `if true` de antes). Si el sed viejo quedara, la guardia 2 del driver ("la
# mutacion no cambio nada") reventaria la bateria entera.
mut_secuencia_tambien_en_cursor() { sed 's/case "\$TARGET" in claude|codex)/case "$TARGET" in *)/'; }
# Las dos mitades del arreglo de A1 (Task 3.1), una mutacion cada una: volver al
# lector greedy sobre el payload crudo, y dejar que el escaner tome la clave en
# cualquier objeto en vez de solo en `tool_input` de primer nivel.
mut_subagent_type_greedy()   { sed 's/json_tool_input_string subagent_type/json_string_field subagent_type/'; }
mut_tool_input_no_se_acota() { sed 's/depth == 2 \&\& clave1 == padre \&\& clave == want/clave == want/'; }
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
# Task 6.4 (D2): apaga la rama explicita de codex en la deteccion de HOST. Con
# CLAUDECODE=1 heredado (el escenario real: Codex lanzado desde adentro de
# Claude), el lado codex vuelve a HOST=claude y los dos hosts comparten estado
# — lo atrapa caso_g1_dos_hosts_codex_y_claude_no_comparten_estado. El patron
# matchea SOLO la linea de deteccion (SUMMONAIKIT_HOOK_TARGET con su `:-`), no
# el chequeo de salida de emit_gate_failure (que compara $TARGET pelado).
mut_host_codex_sin_rama()    { sed 's/SUMMONAIKIT_HOOK_TARGET:-}" = "codex" \]/SUMMONAIKIT_HOOK_TARGET:-}" = "codexNUNCA" ]/'; }
# Task 6.4 (D3): revierte la ceremonia a claude-only — el gate vuelve a ser
# inerte en codex. Lo atrapa caso_g3_ceremonia_se_exige_en_codex (el bloqueo
# que reclama al implementer desaparece y el turno cierra limpio).
mut_ceremonia_sin_codex()    { sed 's/case "\$TARGET" in claude|codex)/case "$TARGET" in claude)/'; }
# Task 6.4 (medido 6.2): devuelve el exit 2 al bloqueo de codex. Codex descarta
# el stdout con exit != 0, o sea gate decorativo — lo atrapa
# caso_g6_bloqueo_codex_exit_cero (su _igual de exit pasa de 0 a 2). Mismo
# patron de ancla por comentario que mut_budget_zcode_sigue_0.
mut_bloqueo_codex_exit2()    { sed '/saikit-6.4-codex-block/s/exit 0/exit 2/'; }
# Task 7.3 (D2): apaga la rama grok de la deteccion de HOST, espejo exacto de
# mut_host_codex_sin_rama. El escenario real que previene: Grok lanzado desde
# adentro de Claude hereda CLAUDECODE=1 Y recibe GROK_HOOK_EVENT del runner —
# sin la rama (y sin su prioridad), el lado grok resuelve HOST=claude y los dos
# hosts comparten estado. Lo atrapa caso_g1_dos_hosts_grok_y_claude_no_comparten_estado.
mut_host_grok_sin_rama()     { sed 's/if \[ "\${GROK_HOOK_EVENT+x}" = "x" \]; then/if false; then/'; }
# Task 7.4 (D3): revierte la ceremonia a claude|codex — el gate vuelve a ser
# inerte en grok. Lo atrapa caso_g3_grok_ceremonia_incompleta_bloquea (el turno
# incompleto pasa a cerrar limpio y el decision:block desaparece).
mut_ceremonia_sin_grok()  { sed 's/case "$TARGET" in claude|codex|grok)/case "$TARGET" in claude|codex)/'; }
# Task 7.3 (D4): saca user_prompt_submit del case de PHASE. Un envelope real
# de Grok cae a PHASE=tool (record_tool_evidence ignora el prompt) y NUNCA
# arma — es el defecto central que esta task cierra. Lo atrapa
# caso_g1_grok_envelope_arma.
mut_phase_sin_user_prompt_submit() { sed 's/UserPromptSubmit|beforeSubmitPrompt|user_prompt_submit)/UserPromptSubmit|beforeSubmitPrompt)/'; }
# Task 7.3 (D5): neutraliza el veto de exit_code (la mitad principal). Con el
# sed, el patron ya no matchea ninguna clave y un runner rojo grok vuelve a
# acreditar verificacion por ausencia de senal. Lo atrapa
# caso_g2_grok_runner_fallido_no_marca.
mut_toolresult_veto_quitado() { sed 's/"exit_code"\[\[:space:\]\]\*:\[\[:space:\]\]\*\[1-9\]/"exit_codeMUT"/'; }
# Task 7.3 (D5, variante): neutraliza la deteccion de las variantes de error
# del toolResult. Lo atrapa caso_g2_grok_nomatchesfound_no_marca.
mut_toolresult_variantes_quitada() { sed 's/FileNotFound|NoMatchesFound/FileNotFoundMUT|NoMatchesFoundMUT/'; }
# Task 7.3 (D4): quita el fallback camel del padre — command vuelve a leerse
# solo de tool_input snake y el credito camel de Grok muere. Lo atrapa
# caso_g2_grok_runner_marca_verificado (el verified desaparece del log).
mut_alias_padre_camel_quitado() { sed 's/^  \[ -n "$command_text" \] || command_text=.*$/  :/'; }
# Task 7.3 (D6): neutraliza la condicion de salida temprana del Stop de cierre
# grok (shutdown). El Stop de cierre vuelve al camino del gate: cuenta ciclo y
# toca estado de un proceso que se va. Lo atrapa
# caso_g1_grok_stop_shutdown_no_toca_estado.
mut_stop_sin_filtro_end_turn() { sed 's/\[ "$stop_reason" != "end_turn" \]/[ "$stop_reason" != "end_turn" ] \&\& false/'; }
# r1 (Greptile P2 / CR PR #27): devuelve la deteccion a -n (valor no-vacio).
# Una senal exportada VACIA deja de contar y el estado del turno grok cae al
# arbol del host heredado. Lo atrapa caso_g1_grok_senal_exportada_vacia_cuenta.
mut_grok_setness_por_valor() { sed 's/if \[ "\${GROK_HOOK_EVENT+x}" = "x" \]/if [ -n "\${GROK_HOOK_EVENT:-}" ]/'; }

mut_retro_no_se_exige()    { sed 's/if ! has_receipt_label "Retro"/if false \&\& ! has_receipt_label "Retro"/'; }
# Task 9.3 movio la frontera de has_receipt_label a (^|[^[:alpha:]'"]): el sed
# de esta mutacion se actualiza al literal nuevo (mismo efecto de siempre:
# cualquier caracter delante cuenta). Sin actualizarlo, la guardia 2 de la
# bateria ("la mutacion no cambio nada") reventaba.
mut_etiqueta_sin_frontera(){ sed "s/(^|\[^\[:alpha:\]'\\\\\"\])/(^|.)/"; }
# Task 9.3 (C11): revierte SOLO la mitad de las comillas (vuelve a la frontera
# pre-9.3). Citar el feedback con 'Understand:' etc. vuelve a satisfacer las
# seis etiquetas — lo atrapa caso_g4_cita_del_feedback_no_satisface (ningun
# otro caso de CASOS_G4 escribe etiquetas entre comillas).
mut_frontera_acepta_comillas(){ sed "s/(^|\[^\[:alpha:\]'\\\\\"\])/(^|[^[:alpha:]])/"; }
# Task 9.8 (C14): devuelve el rm del aviso pendiente al elif de todo Stop —
# la anotacion del flag se reemplaza por el rm directo, asi un Stop que
# bloquea vuelve a llevarse el aviso ajeno. Lo atrapa
# caso_g5_stop_fallido_no_borra_aviso_ajeno (su primera mitad). El patron es
# unico: la comparacion del camino limpio lleva espacios y comillas
# ("$rn_pendiente_borrable" = "1") y no matchea.
mut_aviso_se_borra_en_fallo(){ sed 's#rn_pendiente_borrable=1#rm -f "$RN_PENDING_PATH" 2>/dev/null || true#'; }
# Task 8.3 (C7): quita la alternativa markdown bold entre etiqueta y `:`.
# Catch: caso_g4_recibo_bold_pasa (el recibo **Label**: vuelve a bloquear).
mut_etiqueta_sin_bold()    { sed 's/(\\\*\\\*|__)?\[\[:space:\]\]\*:/[[:space:]]*:/'; }
mut_pausa_no_se_reconoce() { sed "s/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED NUNCA'/"; }
# Arreglo 1 (escotilla hermana "delegado y en vuelo"): neutraliza la CONDICION
# apuntando al ancla unica `grep -Eiq 'SUMMONAIKIT HARNESS DELEGATED` -- ese
# prefijo con la comilla y el "grep -Eiq" solo aparece en la condicion del
# Stop gate, nunca en el texto del contrato inyectado (ahi es prosa suelta,
# sin "grep -Eiq '" delante), asi que la mutacion no le pega al mensaje. Con
# "_NUNCA" pegado, "SUMMONAIKIT HARNESS DELEGATED - awaiting verifier" deja de
# matchear -> la escotilla desaparece -> un recibo que la usa vuelve a
# bloquear. Lo atrapa caso_g4_delegado_permite (ningun otro caso de CASOS_G4
# escribe "SUMMONAIKIT HARNESS DELEGATED" en su fixture, asi que ningun otro
# reacciona). Misma forma que mut_pausa_no_se_reconoce / mut_role_fallback_quitada.
mut_delegado_no_se_reconoce() { sed "s/grep -Eiq 'SUMMONAIKIT HARNESS DELEGATED/grep -Eiq 'SUMMONAIKIT HARNESS DELEGATED_NUNCA/"; }
# Fix de cross-review (ciclo 1): la escotilla DELEGATED tiene que exigir
# ADEMAS que no haya recibo, o un recibo (roto o completo) que solo la
# mencione de pasada la deja disparar igual -- ver RECEIPT_MARKER_RE y el
# comentario largo que lo explica en el hook. Se declaro como constante
# propia (no inline) exactamente para que esta mutacion pueda apuntar SOLO a
# su definicion, sin tocar de paso el chequeo separado y no relacionado de
# "Missing SUMMONAIKIT HARNESS RECEIPT" (que usa el mismo literal inline mas
# abajo en stop_gate). Con el marcador roto ("_NUNCA" pegado), la guardia
# `! grep "$RECEIPT_MARKER_RE"` vuelve a dar VERDADERO siempre -- la
# escotilla vuelve a disparar sin importar si hay recibo. Lo atrapa
# caso_g4_delegado_incidental_en_recibo_roto_bloquea (el recibo roto con la
# frase incidental vuelve a cerrar en silencio, exit 0 en vez de 2).
mut_delegado_ignora_recibo() { sed "s/RECEIPT_MARKER_RE='SUMMONAIKIT HARNESS RECEIPT'/RECEIPT_MARKER_RE='SUMMONAIKIT HARNESS RECEIPT_NUNCA'/"; }
# Task 8.2 (C4): devuelve las escotillas al texto completo ($text incluye el
# tail con turnos anteriores). Catch: caso_g4_pausa_vieja_solo_en_transcript_
# bloquea (un PAUSED viejo vuelve a saltar el gate).
mut_escotillas_leen_tail_viejo() { sed 's/text_hatch="$(last_assistant_text)"/text_hatch="$text"/'; }
# Las cuatro mitades del arreglo de A2+A8 (Task 3.2), una mutacion cada una.
# Las dos primeras mutan la LLAMADA en stop_gate (no el awk interno) porque
# MSYS2/Git Bash corrompe los backslashes en literales de sed — cambiar la
# funcion llamada es equivalente para lo que el caso prueba y no tiene ese
# problema. Las dos ultimas mutan la condicion del walker directamente.
mut_canal_payload_crudo()    { sed 's/$(last_assistant_text)/$(json_string_field last_assistant_message)/'; }
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

# D4 (Task 6.3): saca la escotilla ROLE FALLBACK del gate de secuencia
# (rompe la CONDICION, no el texto del mensaje). Apunta al ancla unica
# `grep -Eiq 'ROLE FALLBACK: ` -- solo aparece en las tres condiciones nuevas,
# nunca en el texto del mensaje ("...or declare ROLE FALLBACK: VERIFIER
# (reason)...", sin comilla simple ni "grep -Eiq" delante) ni en el bullet del
# contrato inyectado, asi que la mutacion no les pega. Sin escapar el `*` de
# `ROLE FALLBACK: *VERIFIER` (la parte que sigue intacta tras el reemplazo):
# el patron de busqueda no lo incluye, asi que no hace falta la trampa de
# backslashes de MSYS2 documentada en :128-131. Con las tres condiciones
# neutralizadas, un recibo con la declaracion vuelve a bloquear -- lo atrapa
# caso_g3_role_fallback_verifier_permite (ningun otro caso de CASOS_G3 escribe
# "ROLE FALLBACK: " en su recibo, asi que ningun otro reacciona).
mut_role_fallback_quitada() { sed "s/grep -Eiq 'ROLE FALLBACK: /grep -Eiq 'ROLE_FALLBACK_NUNCA: /"; }

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
