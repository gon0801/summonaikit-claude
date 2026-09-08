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
G1|desarma_con_prompt_vacio|la clausula que impide desarmar con prompt vacio se neutraliza y un evento sin texto vuelve a borrar el estado armado
G1|marca_notificacion_laxa|la marca de notificacion vuelve a la forma laxa (contiene) y un prompt humano que la menciona se queda sin gate
G1|reglas_no_dicen_donde|la regla permanente de la bateria deja de nombrar el lugar y vuelve a decir solo cuantas veces
G1|reglas_sin_base_de_rama_limpia|el bullet de higiene de base de rama desaparece de las reglas permanentes y una rama cortada de un master local vuelve a colar commits ajenos al PR
G1|laxa_sin_cierre|la forma laxa deja de exigir la marca de cierre y una mencion humana casual suprime el desarme
G2|despacho_bg_acredita|el guard del despacho en background se neutraliza y un job recien lanzado vuelve a acreditar verificacion sin resultado
G1|notificacion_no_se_reconoce|el acotamiento de notificacion de tarea se neutraliza y una notificacion en background vuelve a desarmar el turno armado
G1|grok_wake_strict_apagado|el skip estricto del auto-wake grok se neutraliza y un wake con sentinel en la descripcion del subagente vuelve a re-armar (18.27)
G1|grok_wake_strict_sin_contenido|la condicion de contenido del skip grok se neutraliza y un sobre de OTRO evento con sentinel deja de armar (18.27, review r2)
G1|session_id_greedy|session_id se vuelve a leer con el lector greedy del payload crudo
G1|host_sin_llave|el estado se vuelve a llavear sin HOST (A y B colapsan al mismo path)
G1|prompt_greedy|el prompt vuelve al lector greedy sin decodificar (comillas o \n antes de -saikit no arman / desarman)
G1|fast_no_se_detecta|el lane fast deja de detectarse y todo arma full
G1|session_sin_reglas|la fase session vuelve a salir muda y las reglas permanentes no se inyectan
G1|session_pisa_gate|la emision de reglas deja de acotarse a session y tambien dispara en prompt sin sentinel
G1|session_sin_codex|se saca codex de la emision de reglas, el host que la medicion de la 10.9 habilito
G1|session_tambien_en_grok|se agrega grok a la emision de reglas, el host que la medicion de la 10.9 descarto por ignorar additionalContext
G1|fallback_sin_acotar|el fallback al payload crudo deja de acotarse a session y un -saikit en cualquier campo vuelve a armar
G1|frontera_izquierda_floja|la frontera izquierda del sentinel vuelve a aceptar / y -, y una ruta o un flag citado arman
G1|estado_inmortal|la poda del dir de sesion se neutraliza y cada limpieza vuelve a dejar un directorio vacio para siempre
G1|barrido_sin_ttl|el barrido pierde el filtro de edad y se lleva tambien el estado de una sesion hermana VIVA (A4)
G1|menu_recetas_apagado|el menu del recetario se apaga y el contrato deja de ofrecer recetas aun con manifiesto valido
G1|alias_pregunta_apagado|el alias -saikit:pregunta deja de bajar el carril
G1|autopilot_no_se_detecta|el carril autopilot deja de detectarse y el flag desaparece del estado y del contrato
G1|autopilot_parrafo_apagado|el parrafo del contrato deja de emitirse en turnos autopilot
G5|autopilot_parrafo_apagado|el parrafo autopilot deja de emitirse tambien en el tercer emisor (presupuesto agotado)
G1|autopilot_no_pisa_alias|autopilot deja de vaciar receta_alias y un turno -saikit:autopilot -saikit:pregunta queda con alias
G1|grok_duplica_parrafo|build_gate_feedback vuelve a agregar el parrafo en grok, donde harness_context adosado ya lo trae (dos veces en el reason)
G1|mark_evidence_tira_autopilot|mark_evidence vacia el arg autopilot al reescribir y el flag desaparece a mitad de turno
G1|record_agent_tira_autopilot|record_agent vacia el arg autopilot al reescribir y el flag desaparece a mitad de turno
G1|alias_sin_receta|el alias baja el carril pero no nombra la receta
G1|alias_no_se_limpia|la limpieza C13 deja de borrar receta_alias en podar_dir_sesion y el directorio de sesion tras un alias queda inmortal
G1|manifiesto_reinyecta_titulo|el runtime vuelve a leer el titulo/carril del manifiesto y un titulo hostil con hash valido vuelve al contrato
G1|menu_pide_todolist|el menu vuelve a pedir el todolist, una herramienta de UN host que la 16.8 midio con 0 usos en 6 de 6 turnos
G1|menu_sin_corte_frontmatter|el menu vuelve a recorrer el archivo entero para titulo/carril y una receta cuyo cuerpo documenta el formato filtra ese texto del cuerpo
G1|alias_sin_validacion|el alias vuelve a bajar el carril y a nombrar la receta aunque la receta no exista en el recetario
G2|runner_sin_pytest|pytest sale de la lista de runners de verificacion
G2|sin_guardia_de_falla|un runner que fallo tambien acredita verificacion
G2|falla_assertion_quitada|AssertionError deja de matchear y un runner que revento por asercion vuelve a acreditarse
G2|falla_failed_quitada|la vía A de failure_signal (digito no-cero antes de failed/failing/failures/errors) se neutraliza
G2|falla_tsc_quitada|el patron error TS[0-9] deja de detectar fracasos de tsc
G2|falla_phpunit_quitada|la vía B (failures/errors: N) deja de matchear
G2|falla_cs_quitada|el grep case-sensitive de fallas se desactiva y cargo/go vuelven a acreditarse
G2|falla_go_quitada|la rama FAIL[^a-zA-Z] del CS se neutraliza y go vuelve a acreditarse (cargo sigue detectado por test result: FAILED)
G2|falla_frontera_aflojada|la frontera [1-9] se afloja a [0-9] y 0 failed se toma como fracaso
G2|falla_excepciones_sin_dospuntos|se quita el ':' despues de las excepciones y un runner exitoso con TypeError/etc. en el comando vuelve a falsamente NO acreditar
G2|estado_sin_turno_armado|un evento de herramienta crea estado sin turno armado
G2|runner_sin_frontera|las fronteras de palabra del runner se quitan
G2|runner_frontera_sin_punto_de_frase|un runner al final de una frase deja de contar
G2|redaccion_quitada|la redaccion de credenciales se desactiva y el secreto vuelve al log
G2|redaccion_sin_ghp|la regla de redaccion de ghp_ se neutraliza y un token ghp_ vuelve al log
G2|skip_sin_espanol|un skip en espanol (no corri) deja de contar y el vivo zcode vuelve a bloquear
G2|command_desacotado|command se vuelve a leer del payload entero y un eco en tool_response acredita verificacion
G2|runner_bash_quitada|las ramas del runner bash propio (tests/run.sh) se neutralizan y bash tests/run.sh vuelve a NO acreditar
G2|falla_dotnet_quitada|'failed' sale de la via B del CI y el banner de dotnet (Failed: 1) vuelve a acreditar
G2|falla_gradle_quitada|los literales de gradle salen del CS y BUILD FAILED / FAILURE: Build failed vuelven a acreditar
G2|credito_por_mencion|la guarda de echo/printf se neutraliza y 'echo pytest' vuelve a acreditar verificacion
G2|credito_por_tool_name|el credito vuelve a evaluar tool_name y una tool llamada como un runner acredita sin correr nada
G2|cmdpos_no_se_aplica|las llamadas a TEST_RUNNER_CMD_RE se neutralizan y la posicion de comando estricta deja de aplicarse (r1)
G2|verif_subagente_label_apagado|el reconocimiento del label VERIFIED BY SUBAGENT se apaga y un recibo con la declaracion honesta vuelve a bloquear por evidencia (Task 14.2)
G2|verif_subagente_host_a_cualquiera|la condicion de host ciego (\$HOST=zcode) se afloja a CUALQUIER host y el label acredita tambien en claude (Task 14.2)
G2|verif_subagente_solo_primer_span|el span del label vuelve a head -n1 y un label con exito seguido de otro con fallo acredita (Greptile P1, PR #72)
G2|verif_subagente_cero_acredita|el veto del conteo cero se apaga y '0 passed' / '0 passing' vuelven a acreditar por la rama passed pelada (CodeRabbit, PR #72)
G2|verif_label_sobre_text_entero|la via del label se juzga sobre \$text entero y un label de un turno ANTERIOR del transcript acredita el turno nuevo (grok r1 #1, PR #72)
G2|verif_fallo_pelado_apagado|el veto del fallo PELADO se apaga y 'pytest -q, ok, failed.' vuelve a acreditar por el ok (residual PR #72, Greptile r3)
G2|verif_fallo_negado_apagado|el descuento de la negacion se apaga y '0 failed' / 'no failures' (formas de exito) pasan a BLOQUEAR
G2|verif_fallo_ruta_no_descontada|el descuento de ruta/archivo se apaga y un 'tests/errors.py' en el COMANDO veta un recibo legitimo (bots PR #81)
G2|verif_fallo_pegado_sin_normalizar|la normalizacion de puntuacion se apaga y '0 failed,error' pierde el veto (grep -o consume la coma) (bots PR #81)
G2|verif_label_vocabulario_cerrado|las dos ramas del runner propio (tests/run.sh) salen del vocabulario del label y 'VERIFIED BY SUBAGENT: bash tests/run.sh exit 0' vuelve a NO acreditar (18.18)
G2|verif_label_resulto_opcional|la guarda de resultado en el MISMO span se quita y un label con comando del vocabulario pero sin resultado acredita (18.18)
G2|verif_label_veto_local|el veto global del label se neutraliza y un fallo declarado en otro span ya no descalifica (18.18)
G2|verif_label_mensaje_generico|el motivo especifico del label deja de llegar al missing y el reclamo vuelve al mensaje generico (18.18)
G3|reviewer_siempre_visto|el gate del reviewer nunca se reporta como faltante
G3|orden_no_se_exige|la secuencia deja de exigir el orden entre los tres roles
G3|secuencia_tambien_en_cursor|la secuencia se exige en cualquier host, no solo claude
G3|subagent_type_greedy|el rol se vuelve a leer con el lector greedy del payload crudo
G3|tool_input_no_se_acota|el escaner deja de exigir que la clave sea de tool_input
G3|agent_type_no_se_lee|el rol de los eventos internos (agent_type) deja de leerse
G3|target_sin_claudecode|el fallback CLAUDECODE=1 se anula y TARGET queda vacio en produccion
G4|retro_no_se_exige|la etiqueta Retro deja de pedirse
G4|ancla_de_linea_quitada|el ancla de linea se quita y la etiqueta vuelve a aceptarse en cualquier posicion: un recibo pegado en un parrafo cierra (18.23)
G4|etiqueta_sin_bold|la alternativa markdown bold se quita y un recibo **Label**: vuelve a bloquear
G4|pausa_no_se_reconoce|la pausa declarada deja de reconocerse
G4|delegado_no_se_reconoce|la escotilla de subagente delegado deja de reconocerse (arreglo 1)
G4|delegado_ignora_recibo|la escotilla DELEGATED deja de exigir que el recibo este ausente (fix cross-review ciclo 1)
G4|delegado_grok_sin_bg|la guardia de backgroundTasks de la escotilla grok se neutraliza y un Stop delegado sin nada en vuelo vuelve a permitir (18.27)
G4|delegado_grok_bg_degenerado|el lector estructural deja de exigir contenido dentro del array y el vacío ([ ]) vuelve a habilitar la escotilla (18.27 r2, 20.4)
G4|delegado_grok_bg_textual|la lectura estructural de backgroundTasks vuelve al grep textual y el Stop multilínea con trabajo en vuelo vuelve a bloquear (20.4)
G4|delegado_grok_bg_solo_balance|el validador completo del documento vuelve a solo balance (sin gram_*) y las formas rotas cuya inval vive solo en gram_* ([1,], clave ajena rota, trailing, escapes) vuelven a habilitar la escotilla (r1; tabla medida en el comentario de la mutacion)
G4|delegado_grok_bg_trailing|la basura tras el cierre del root deja de invalidar y un documento con trailing garbage vuelve a habilitar la escotilla (r1)
G4|delegado_grok_bg_ignora_doc|la validez fuera de la clave deja de pesar y un valor roto en OTRA clave del documento vuelve a habilitar la escotilla (r1)
G4|delegado_grok_bg_escape_leniente|la estrictura de escapes se quita y cualquier caracter tras barra invertida vuelve a valer: "\q" habilita la escotilla (r3)
G4|delegado_grok_bg_control_crudo|el veto del char de control crudo en strings se quita y un tab literal dentro de un string habilita la escotilla (r3)
G4|delegado_grok_bg_uhex_leniente|el veto de "\u"+4hex se quita y "\u12G34" (G colado entre hex) habilita la escotilla (r3)
G4|delegado_grok_bg_escape_clave_sin_decodificar|la decodificacion de escapes al acumular la clave se quita y una clave DISTINTA con escapes vuelve a colisionar con backgroundTasks (review r2 P1)
G4|paused_sin_guardia_de_recibo|la escotilla PAUSED deja de exigir que el recibo este ausente (fix 11.2)
G4|paused_exige_recibo|la escotilla PAUSED invierte la guardia y exige recibo PRESENTE para permitir (11.2)
G4|escotillas_leen_tail_viejo|las escotillas PAUSED/DELEGATED vuelven a leer el tail entero (texto de turnos anteriores decide)
G4|walker_sin_resets|el walker deja de resetear en_text/en_assistant al cerrar llaves y un valor top-level se cuela como texto del asistente
G4|canal_payload_crudo|el canal payload vuelve al lector greedy del vendor sin decodificar
G4|canal_transcript_vacio|el canal transcript se ignora y no devuelve texto del asistente
G4|texto_incluye_tool_result|el walker deja de exigir role:assistant y acepta mensajes user
G4|texto_incluye_tool_use|el walker deja de exigir type:text y acepta thinking/tool_use
G4|transcript_sin_containment|la contencion de transcript_path se anula y se vuelve a leer cualquier ruta
G4|containment_sin_resolver|la contencion compara la ruta cruda en vez de resolverla con cd+pwd
G4|unknown_honesto_quitado|el cierre unknown honesto (11.4) se neutraliza y un Stop con ambos canales de texto ciegos vuelve a bloquear exigiendo evidencia no observable
G4|unknown_ciega_al_payload|la deteccion del canal payload se apaga (11.4) y el unknown honesto dispara tambien con last_assistant_message PRESENTE (ausencia observada deja de bloquear)
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
G5|aviso_se_borra_en_fallo|el borrado del aviso RN pendiente vuelve al elif de todo Stop y un Stop que bloquea se lleva el aviso ajeno
G1|host_grok_sin_rama|la senal GROK_HOOK_EVENT deja de mapear HOST=grok y un turno grok heredando CLAUDECODE=1 vuelve a creerse claude (D2)
G1|host_dsh_no_reconocido|la rama HOST=dsh se apaga y un turno dsh cae en other — no crea state/dsh/ (Phase 15, D2)
G1|tool_hint_sin_dsh|la rama TOOL_HINT de dsh se apaga y el contrato vuelve a nombrar Task tool (Phase 15, D4)
G1|phase_sin_user_prompt_submit|el literal user_prompt_submit sale del case de PHASE y un envelope real de Grok cae a "tool": nunca arma (D4)
G2|toolresult_veto_quitado|el veto de toolResult.exit_code != 0 se neutraliza y un runner rojo grok vuelve a acreditar verificacion (D5)
G2|toolresult_variantes_quitada|la deteccion de FileNotFound/NoMatchesFound en toolResult se neutraliza (D5, variante)
G2|alias_padre_camel_quitado|el fallback camel del padre (toolInput) se quita y command vuelve a leerse solo de tool_input snake (D4)
G1|stop_sin_filtro_end_turn|el filtro de Stop grok distinto de end_turn se neutraliza y el Stop de cierre vuelve a contar ciclo/tocar estado (D6)
G1|grok_setness_por_valor|la deteccion de GROK_HOOK_EVENT vuelve a exigir valor no-vacio y una senal exportada vacia clasifica por las senales heredadas (r1, Greptile P2)
G3|ceremonia_sin_grok|la rama de ceremonia vuelve a claude|codex y el gate queda inerte en grok (D3, 7.4)
G3|ceremonia_sin_dsh|la rama de ceremonia vuelve a claude|codex|grok y el gate queda inerte en dsh (D1/D3, Phase 15)
G3|adv_keyword_sin_precedencia|la rama adversar deja de matchear y adversarial-audit vuelve a acreditar reviewer sin review real (D6, Task 13.5)
G3|adv_delegated_sin_adversary|la escotilla DELEGATED vuelve a no perdonar awaiting adversary y una delegacion viva quema un ciclo (D6, Task 13.5)
G3|adv_linea_no_se_exige|la linea ADVERSARY del recibo deja de exigirse y un turno fast con adversary cierra sin reporte (D4/B1, Task 13.5)
G3|adv_fallback_sin_adversary|la sustitucion ROLE FALLBACK: ADVERSARY deja de aceptarse y un adversary caido vuelve a bloquear el cierre (D4/D6, Task 13.5)
G3|adv_orden_sin_adversary|el chequeo de orden con adversary deja de correr y un adversary fuera de posicion cierra igual (D4, Task 13.5)
G1|adv_contrato_criterio_roto|el contrato deja de nombrar el disparador opt-in del adversary y nadie lo invoca (D1, Task 13.6)
G1|adv_contrato_despacho_roto|la forma del despacho del reviewer que nombra el artefacto desaparece del contrato (M2/D2, Task 13.6)
G7|pretool_gh_pr_merge_apagado|el patron gh pr merge se apaga y el merge a pelo vuelve a pasar
G7|pretool_gh_pr_merge_literal|el patron gh pr merge vuelve al literal -Fq y gh  pr  merge / mayusculas pasan
G7|pretool_gh_api_merge_apagado|el patron gh api /merge se apaga y el endpoint de merge vuelve a pasar
G7|pretool_git_push_protegida_apagado|el patron git push a master|main se apaga y el push a rama protegida vuelve a pasar
G7|pretool_git_push_exige_inmediato|el regex de git push exige push pegado a git y git -C / --no-pager push a master|main pasa
G7|pretool_git_push_dest_sin_plus_colon|el dest de git push pierde + y : inicial y un force-push o delete-ref a master|main pasa
G7|pretool_git_push_token_en_cualquier_lado|el dest de git push vuelve a token-en-cualquier-lado y una URL con main niega un feature
G7|pretool_hatch_siempre_ok|el hatch acepta cualquier hash y un pin distinto deja de negar
G7|pretool_hatch_nunca_ok|el hatch rechaza el pin correcto (falso positivo del script canonico)
G7|pretool_hatch_sin_strip_comillas|el hatch deja de pelar comillas envolventes y un pin correcto entre comillas niega
G7|pretool_hatch_spoof_apagado|el spoof de sufijo (.bak) se apaga y saikit-merge.sh.bak con pin del real deja de negar
G7|pretool_cae_a_tool|PreToolUse cae a PHASE=tool y el comando se acredita como si ya hubiera corrido
G7|pretool_hatch_antes_de_pelo|el hatch vuelve a allow antes de los patrones a pelo y una cadena saikit-merge + gh pr merge pasa
G8|trail_check_eliminado|el chequeo trail/blast del Stop se apaga y un full sin cita cierra
G8|trail_vuelve_a_glob|cite-and-present vuelve a cualquier leftover tsv+blast en disco y un leftover sin cita cierra
G8|trail_acepta_glob_token|el token glob en Close cuenta como cita
G8|trail_sin_existir|una cita sin archivo en disco cierra
G8|trail_solo_tsv|se deja de exigir la familia blast
G8|trail_solo_blast|se deja de exigir la familia tsv
G8|trail_lee_recibo_entero|las citas se leen del recibo entero, no del span Close
G8|trail_skip_vacio|has_trail_skip acepta cualquier texto
G8|trail_skip_sin_razon|TRAIL SKIP: vacio cuenta
G8|trail_skip_substring|el skip se busca como subcadena sin ancla
G8|trail_lee_text_entero|skip/cita se leen de \$text (tail) no de text_hatch
G8|trail_tambien_en_fast|el guard lane!=fast se apaga y fast sin cita bloquea
G8|trail_parrafo_solo_hc|build_gate_feedback deja de adosar trail_parrafo
G8|trail_sin_limite_fisico|una carpeta de evidencia enlazada afuera se acredita
G8|trail_acepta_archivo_enlazado|un archivo de evidencia enlazado afuera se acredita
G8|trail_skip_preambulo|un skip anterior a la cabecera acredita el recibo
G8|trail_close_preambulo|un Close anterior a la cabecera acredita el recibo
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
#
# Task 10.14: la condicion de E2 paso a ser multi-linea (se le sumaron las dos
# clausulas nuevas de la notificacion), asi que el sed ya no puede anclar en
# `; then` (ahora vive dos lineas mas abajo, tras la continuacion `\`). Se
# ancla SOLO al tramo que cambia (sin el `; then` ni la barra de continuacion
# final, que quedan intactos) y se antepone `false &&` a lo que sigue: como es
# una cadena AND, `false` corta el resto SIN tocar las clausulas nuevas -- el
# mismo efecto de siempre (E2 nunca desarma), sin reescribir sus dos lineas.
mut_desarmar_quita_borrado()   { sed 's/if \[ "\$PHASE" = "prompt" \] && \[ -f "\$STATE_PATH" \]/if false \&\& [ -f "$STATE_PATH" ]/'; }
# Task 10.14: revierte SOLO la mitad de la notificacion del acotamiento nuevo
# de E2 -- el grep deja de poder matchear NUNCA (patron imposible), asi que
# "no parece notificacion" da SIEMPRE verdadero y una notificacion de tarea en
# background vuelve a desarmar el turno armado; la clausula de prompt vacio
# (la otra mitad del acotamiento) queda intacta. Lo atrapa
# caso_g1_notificacion_tarea_no_desarma (ningun otro caso de CASOS_G1 usa el
# fixture de notificacion, asi que ningun otro reacciona).
# Task 10.14 (reviewer): la otra clausula del acotamiento, la que exige un
# prompt NO vacio. Sin ella un UserPromptSubmit sin texto vuelve a desarmar.
# La atrapa caso_g1_prompt_vacio_no_desarma.
mut_desarma_con_prompt_vacio() { sed 's/\[ -n "$prompt_text" \]/true/'; }
# PR #30 (greptile P1 + coderabbit Major): volver la marca a la forma laxa.
# La atrapa caso_g1_mencion_humana_de_la_marca_sigue_armando.
mut_marca_notificacion_laxa() { sed "s|'\^\[\[:space:\]\]\*<task-notification>'|'<task-notification>'|"; }
# Task 10.16: podar la mencion al CI de la regla de la bateria. La atrapa
# caso_g1_reglas_nombran_donde_correr_la_bateria.
mut_reglas_no_dicen_donde() { sed 's/OPEN A PULL REQUEST/run it/'; }
# Task 11.1: quita el bullet de higiene de base de rama del heredoc de reglas
# permanentes. La atrapa caso_g1_reglas_exigen_base_de_rama_limpia.
mut_reglas_sin_base_de_rama_limpia() { sed '/NEVER from your local default branch/d'; }
# PR #30: que la forma laxa se conforme con la marca de apertura. La atrapa
# caso_g1_mencion_humana_sin_sentinel_si_desarma.
mut_laxa_sin_cierre() { sed 's|grep -Eq "$SAIKIT_TASK_NOTIFICATION_CIERRE_RE"|true|'; }
# Task 10.15: que un despacho en background vuelva a acreditar. La atrapa
# caso_g2_runner_en_background_no_acredita.
mut_despacho_bg_acredita() { sed 's|grep -Eiq "$SAIKIT_DESPACHO_BG_RE"|false|'; }
mut_notificacion_no_se_reconoce() { sed 's/"\$SAIKIT_TASK_NOTIFICATION_RE"/"NUNCA_MATCHEA_ESTO_10_14"/'; }
# 18.27 (D-A): gemelos grok. El strict apagado deja pasar el auto-wake al gate
# del sentinel y un wake con `-saikit` en la descripcion del subagente re-arma
# (reset de cycle). Lo atrapa caso_g1_grok_autowake_con_sentinel_no_rearma.
mut_grok_wake_strict_apagado() { sed 's/"\$SAIKIT_GROK_WAKE_STRICT_RE"/"NUNCA_MATCHEA_ESTO_18_27"/'; }
# Review r2 (R27-1): sin la condicion de CONTENIDO del skip, cualquier sobre
# de sistema cuya primera linea sea la etiqueta salta el gate — un sobre de
# OTRO evento con sentinel adentro dejaria de armar. Lo atrapa
# caso_g1_grok_sobre_de_otro_evento_con_sentinel_arma. (La via laxa grok se
# RETIRO en r2 — una mencion humana de ambas cadenas heredaba el gate del
# turno anterior — y su mutacion, grok_wake_laxa_sin_contenido, se fue con
# ella.)
mut_grok_wake_strict_sin_contenido() { sed 's|grep -Eq "$SAIKIT_GROK_WAKE_CONTENIDO_RE"|true|'; }
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
# Task 16.4 (D1) — que el recetario se APAGUE (la guarda del manifiesto se vuelve
# `if true`) deje de ofrecer recetas aunque el manifiesto este valido: lo atrapa
# caso_g1_contrato_nombra_recetario. Task 16.6 (D3) — alias: una mutacion mata la
# DETECCION (-saikit:pregunta deja de bajar el carril, lo atrapa
# caso_g1_alias_pregunta_arma_fast_y_nombra_receta) y otra deja el carril en fast
# pero vacia la receta (receta_alias="" ⇒ no se nombra, lo atrapa el mismo caso
# porque 'the recipe is investigar' no aparece).
mut_menu_recetas_apagado()      { sed 's/^  if \[ ! -r "\$m" \]; then printf/  if true; then printf/'; }
mut_alias_pregunta_apagado()    { sed 's/-saikit:pregunta(/-saikit:NUNCA(/'; }
# 18.6: el sed de autopilot_no_se_detecta solo toca la linea de DETECCION (el
# patron `-saikit:autopilot(` vive una sola vez en el hook: el parrafo del
# contrato trae `-saikit:autopilot)` con cierre, grep-verificado). El de
# autopilot_parrafo_apagado rompe la igualdad a "1" en los TRES emisores
# (harness_context, build_gate_feedback y emit_budget_exhausted): el tercero
# lee el flag por `${2:-$(read_state_value autopilot)}`, asi que el sed ancla
# en la cola comun `autopilot)...}" = "1"` y no en el literal entero. Un sed
# que solo tocara el literal de los dos primeros dejaba el budget agotado
# emitiendo el parrafo con la mutacion puesta (medido). Catalogado en G1 (lo
# atrapan arm/gate_failure) Y en G5 (caso_g5_autopilot_parrafo_en_budget_agotado).
mut_autopilot_no_se_detecta()   { sed 's/-saikit:autopilot(/-saikit:NUNCA(/'; }
mut_autopilot_parrafo_apagado() { sed -E 's/(read_state_value autopilot\)\}?" = )"1"/\1"1 NUNCA"/g'; }
mut_autopilot_no_pisa_alias()   { sed 's/autopilot="1"; lane="full"; receta_alias=""/autopilot="1"; lane="full"/'; }
mut_grok_duplica_parrafo()      { sed 's/if \[ "$TARGET" != "grok" \] \&\& \[ "$(read_state_value autopilot)" = "1" \]/if [ "$(read_state_value autopilot)" = "1" ]/'; }
# 18.6 (PR #162, hueco 4): vacia el 12o arg SOLO en el write_state de
# mark_evidence (la linea siguiente es printf '%s: %s\n'). Lo atrapa
# caso_g1_autopilot_sobrevive_mark_evidence. Residual: verdict_registrar_sello
# y adv_reescribir_estado no los toca este sed (medido: sobreviven).
mut_mark_evidence_tira_autopilot() {
  sed '/write_state .*read_state_value autopilot/{
    N
    /printf '\''%s: %s\\n'\''/s/"$(read_state_value autopilot)"/""/
  }'
}
# Gemelo: vacia el arg solo en el write_state de record_agent (linea antes
# de printf 'agent:'). Lo atrapa caso_g1_autopilot_sobrevive_record_agent.
mut_record_agent_tira_autopilot() {
  sed '/write_state .*read_state_value autopilot/{
    N
    /printf '\''agent:/s/"$(read_state_value autopilot)"/""/
  }'
}
mut_alias_sin_receta()          { sed 's/receta_alias="investigar"/receta_alias=""/'; }
# Task 16.6 (reviewer, hallazgo #4 / C13): la limpieza receta_alias de
# podar_dir_sesion se neutraliza y el desarme tras un turno con alias deja el
# directorio inmortal — lo atrapa caso_g1_alias_desarme_limpia_estado (ningun
# otro caso de CASOS_G1 arma con alias y exige que el dir desaparezca).
mut_alias_no_se_limpia()        { sed 's#rm -f "\$STATE_DIR/receta_alias" 2>/dev/null || true; rmdir#rmdir#'; }
# Task 16.4/16.6 (revision lead, fix 1): devuelve el runtime a leer el titulo y
# el carril del MANIFIESTO en vez del archivo autenticado. Con un manifiesto de
# titulo hostil y hash valido, ese texto vuelve al contrato — lo atrapa
# caso_g1_receta_titulo_hostil_no_se_inyecta (el unico caso que planta un
# titulo de manifiesto distinto al del archivo; los demas con recetario usan el
# mismo titulo en ambos, asi que no reaccionan).
mut_manifiesto_reinyecta_titulo() { sed 's/"\$f_titulo" "\$f_carril"/"$titulo" "$carril"/'; }
# Task 16.10: devuelve la instruccion vieja al menu. Lo atrapa
# caso_g1_contrato_nombra_recetario, que ahora exige la conducta ("follow its
# steps IN ORDER") y prohibe nombrar la herramienta ("todolist").
mut_menu_pide_todolist() { sed 's/and follow its steps IN ORDER — do not improvise your own sequence. Declare it/copy its steps into your todolist before reasoning, and declare it/'; }
# Task 16.4/16.6 (lead, fix 1b): hace que el awk vuelva a recorrer el archivo
# entero (sin parar en el segundo '---' y sin la guardia de primera coincidencia)
# -> vuelve a ganar la ULTIMA coincidencia y una receta cuyo cuerpo documenta el
# formato filtra su texto al menu. Lo atrapa caso_g1_receta_menu_lee_solo_
# frontmatter (el unico caso que planta titulo/carril en el cuerpo).
mut_menu_sin_corte_frontmatter() { sed 's/NR>1 && \$0=="---"{exit} //; s/&&!t//; s/&&!c//;'; }
# Task 16.6 (revision lead, fix 2): neutraliza el guard receta_valida de AMBOS
# alias — el alias vuelve a bajar el carril y a nombrar la receta aunque no
# exista. Lo atrapan caso_g1_alias_sin_receta_no_baja_el_carril y
# caso_g1_alias_sin_recetario_queda_full (los positivos del alias y el typo
# siguen verdes: corren con/sin recetario valido).
mut_alias_sin_validacion() { sed 's/if receta_valida "investigar"/if true/; s/if receta_valida "boceto"/if true/'; }
# Task 10.6 — las dos mitades de las reglas permanentes, una mutacion cada una.
# session_sin_reglas mata la EMISION (la fase session vuelve a salir muda) — lo
# atrapa caso_g1_session_inyecta_reglas. session_pisa_gate saca el acotamiento a
# session, asi que la emision tambien corre en prompt sin sentinel — lo atrapa
# caso_g1_no_arma_sin_sentinel, que exige stdout VACIO ahi. Esa segunda mitad es
# la razon por la que 10.6 no agrega un caso propio de "prompt sigue mudo": el
# caso que ya existe es la regresion, y la mutacion lo demuestra.
mut_session_sin_reglas()        { sed 's/^      emit_standing_rules$/      :/'; }
# ACTUALIZADA por la Task 10.9: su sed apuntaba al literal
# `[ "$PHASE" = "session" ] && [ "$TARGET" = "claude" ]`, que esta fila movio al
# sumar codex. Sin actualizarla quedaba INERTE —no cambiaria un byte— y la
# guardia 2 de la bateria (toda mutacion tiene que modificar el archivo)
# reventaba. Mismo tropiezo que ya tuvieron la 6.4 y la 9.3.
mut_session_pisa_gate()         { sed 's/\[ "$PHASE" = "session" \] && { \[ "$TARGET" = "claude" \] || \[ "$TARGET" = "codex" \]; }/{ [ "$TARGET" = "claude" ] || [ "$TARGET" = "codex" ]; }/'; }
# Task 10.9 — una mutacion por cada mitad del veredicto nuevo.
# session_sin_codex saca el host que la medicion HABILITO: lo atrapa
# caso_g1_session_inyecta_reglas_codex. session_tambien_en_grok agrega el host
# que la medicion DESCARTO: lo atrapa caso_g1_session_no_inyecta_en_grok, y es
# la direccion que importa — habilitar de mas es el error que esta fila existe
# para impedir, y sin esta mutacion nadie probaria que el caso lo detecta.
mut_session_sin_codex()         { sed 's/ || \[ "$TARGET" = "codex" \]; }/; }/'; }
mut_session_tambien_en_grok()   { sed 's/\[ "$TARGET" = "codex" \]; }/[ "$TARGET" = "codex" ] || [ "$TARGET" = "grok" ]; }/'; }
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
# Task 17.3 / D12 — la regla de redaccion de ghp_ se neutraliza y un token
# ghp_ vuelve al log. Se ancla en el literal unico `'s/ghp_` (comilla simple +
# `s/ghp_`), que aparece UNA vez, adentro de la regla sed del ghp_ y en ningun
# otro lado (el RE de escaneo usa `|ghp_`, y github_pat_/gho_ difieren). Con
# `@` de delimitador se esquiva la barra `/` de la regla. La regla mutada queda
# `s/ghp_NOPE_...`, que nunca matchea `ghp_`, asi que el token viaja en claro y
# lo atrapa caso_g2_credenciales_token_nuevas_se_redactan (su _no_contiene de
# `ghp_...` deja de cumplirse).
mut_redaccion_sin_ghp() { sed "s@'s/ghp_@'s/ghp_NOPE_@"; }
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

# Task 14.2 — via de credito del label VERIFIED BY SUBAGENT, una mutacion por
# condicion clave. label_apagado neutraliza el reconocimiento del prefijo
# (SAIKIT_VERIFIED_SUBAGENT_RE a un literal imposible): el recibo honesto con el
# label deja de acreditar y vuelve a bloquear — lo atrapa
# caso_g2_zcode_verif_subagente_acredita (ningun otro caso del gate G2 escribe el
# prefijo VERIFIED BY SUBAGENT, asi que ningun otro reacciona; los negativos
# siguen bloqueando porque bloquean por igual sin el label reconocido).
# host_a_cualquiera afloja la condicion de host ciego `[ "$HOST" = "zcode" ]` a
# `true` (cualquier host). El sed reemplaza las DOS ocurrencias (la del helper
# saikit_verif_subagente_credita y la de saikit_verif_evidence_ok): el label
# acredita tambien en claude — lo atrapa caso_g2_claude_verif_subagente_no_acredita
# (el label ya acredita en zcode, asi que el caso de ACREDITA sigue verde; solo el
# caso que espera BLOQUEO en host no ciego se pone rojo).
mut_verif_subagente_label_apagado() { sed "s/^SAIKIT_VERIFIED_SUBAGENT_RE=.*/SAIKIT_VERIFIED_SUBAGENT_RE='NUNCA_MATCHEA_ESTO_14_2'/"; }
mut_verif_subagente_host_a_cualquiera() { sed 's/\[ "$HOST" = "zcode" \]/true/'; }
# solo_primer_span (Greptile P1, PR #72) vuelve a recortar los spans del label a
# `| head -n1`: el veto deja de ver un segundo label con fallo y un recibo
# exito-luego-fallo acredita — lo atrapa caso_g2_zcode_verif_subagente_exito_luego_fallo_bloquea
# (el espejo fallo-luego-exito bloquea con y sin la mutacion: no la discrimina).
mut_verif_subagente_solo_primer_span() { sed 's/grep -Eio "$SAIKIT_VERIFIED_SUBAGENT_RE\[^\[:cntrl:\]\]\*"$/& | head -n1/'; }
# cero_acredita (CodeRabbit, PR #72) apaga SAIKIT_VERIFIED_CERO_RE (literal
# imposible): "0 passed"/"0 passing" vuelven a acreditar por la rama `passed`
# pelada de RESULT_RE — lo atrapan caso_g2_zcode_verif_subagente_cero_passed_bloquea
# y ..._cero_passing_bloquea.
mut_verif_subagente_cero_acredita() { sed "s/^SAIKIT_VERIFIED_CERO_RE=.*/SAIKIT_VERIFIED_CERO_RE='NUNCA_MATCHEA_ESTO_0_PASSED'/"; }
# label_sobre_text_entero (grok r1 #1, fe81de5) vuelve a juzgar la via del label
# sobre $text (tail del transcript + turno actual): un label valido de un turno
# ANTERIOR acredita el turno nuevo — lo atrapa
# caso_g2_zcode_verif_label_de_turno_anterior_no_acredita.
mut_verif_label_sobre_text_entero() { sed 's/saikit_verif_evidence_ok "$text_hatch"/saikit_verif_evidence_ok "$text"/'; }
# fallo_pelado_apagado (residual PR #72) deja SAIKIT_VERIFIED_FALLO_PELADO_RE en
# un literal imposible: la extraccion no devuelve nada, el veto no dispara y
# "ok, failed." acredita — lo atrapa caso_g2_zcode_verif_subagente_fallo_pelado_bloquea.
# fallo_negado_apagado deja SAIKIT_VERIFIED_FALLO_NEGADO_RE imposible: nada se
# descuenta, "0 failed"/"no failures" vetan y los dos casos que ACREDITAN se
# ponen rojos (caso_g2_zcode_verif_subagente_cero_failed_acredita / _sin_fallos_acredita).
mut_verif_fallo_pelado_apagado() { sed "s/^SAIKIT_VERIFIED_FALLO_PELADO_RE=.*/SAIKIT_VERIFIED_FALLO_PELADO_RE='NUNCA_MATCHEA_ESTO_FALLO_PELADO'/"; }
mut_verif_fallo_negado_apagado() { sed "s/^SAIKIT_VERIFIED_FALLO_NEGADO_RE=.*/SAIKIT_VERIFIED_FALLO_NEGADO_RE='NUNCA_MATCHEA_ESTO_NEGADO'/"; }
# ruta_no_descontada (bots #81) deja SAIKIT_VERIFIED_FALLO_RUTA_RE imposible:
# `tests/errors.py` en el comando vuelve a vetar — lo atrapa
# caso_g2_zcode_verif_subagente_cmd_con_error_acredita.
# pegado_sin_normalizar reemplaza saikit_verif_fallo_norm por `cat`: la coma
# pegada vuelve a tragarse la frontera y "0 failed,error" acredita — lo atrapa
# caso_g2_zcode_verif_subagente_fallo_pegado_bloquea.
mut_verif_fallo_ruta_no_descontada() { sed "s/^SAIKIT_VERIFIED_FALLO_RUTA_RE=.*/SAIKIT_VERIFIED_FALLO_RUTA_RE='NUNCA_MATCHEA_ESTO_RUTA'/"; }
mut_verif_fallo_pegado_sin_normalizar() { sed 's/^saikit_verif_fallo_norm() .*/saikit_verif_fallo_norm() { cat; }/'; }
# 18.18 — una mutacion por condicion nueva del carril del label con el runner
# propio, cada una acreditada a su caso (los literales aparecen una sola vez en
# el hook). vocabulario_cerrado apaga SOLO la constante de las dos ramas nuevas
# (el resto del vocabulario queda intacto: pytest/py_compile siguen
# acreditando) — lo atrapa caso_g2_zcode_verif_label_runner_propio_acredita.
# resulto_opcional neutraliza la guarda de RESULT_RE del loop de credito (el
# `|| continue` de esa linea deja de cortar) — lo atrapan los dos casos de
# "comando sin resultado": el preexistente ..._verif_subagente_sin_resultado_
# bloquea (py_compile sin resultado, corre antes en CASOS_G2 y se lleva el
# credito) y el nuevo caso_g2_zcode_verif_label_sin_resultado_sin_fallo_
# no_acredita (runner propio sin resultado — el DISCRIMINANTE pensado para esta
# mutacion: un caso con resultado FALLIDO no sirve porque el veto global corre
# antes y bloquea igual con o sin la guarda).
# veto_local apaga el veto global: los CUATRO greps del bloque leen entrada
# vacia (dejan de ver los spans; el calculo sigue, jamas descalifica por
# FAILURE_SIGNAL/exit [1-9]/cero) — lo atrapa
# caso_g2_zcode_verif_label_exito_y_fallo_en_spans_distintos_no_acredita (y los
# casos de veto preexistentes: exit1/fallido/exito_luego_fallo/cero, que corren
# antes en CASOS_G2 y pueden quedarse con el credito).
# mensaje_generico rompe el nombre de la variable que lleva el motivo al Stop
# (queda siempre vacia y el mensaje vuelve al generico) — lo atrapa
# caso_g2_zcode_verif_label_comando_fuera_de_vocabulario_no_acredita_y_lo_dice
# en su asercion de texto (el generico no nombra el vocabulario).
mut_verif_label_vocabulario_cerrado() { sed "s/^SAIKIT_VERIFIED_RUNNER_PROPIO_RE=.*/SAIKIT_VERIFIED_RUNNER_PROPIO_RE='NUNCA_MATCHEA_ESTO_RUNNER_PROPIO'/"; }
mut_verif_label_resulto_opcional()    { sed 's/grep -Eiq "$SAIKIT_VERIFIED_RESULT_RE"/true/'; }
mut_verif_label_veto_local()          { sed "s/printf '%s\\\\n' \"\$saikit_spans\"/printf '%s\\\\n' \"\"/g"; }
mut_verif_label_mensaje_generico()    { sed 's/"${saikit_verif_motivo:-}"/"${saikit_verif_motivo_NUNCA:-}"/'; }
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
# El early-exit ya no es el one-liner. Ancla: SealableWrite. emit_allow -> true
# deja caer al mark_evidence y caso_g2_sin_armar_no_crea_estado se pone rojo.
mut_estado_sin_turno_armado(){ sed '/SealableWrite igual sella/,/^  fi$/ s/emit_allow/true/g'; }

mut_reviewer_siempre_visto()      { sed 's/\*",reviewer,"\*) ;;/*) ;;/'; }
mut_orden_no_se_exige()           { sed "s/'implementer\.\*verifier\.\*reviewer'/'implementer|verifier|reviewer'/"; }
# Task 6.4 movio la condicion de la ceremonia de `if [ "$TARGET" = "claude" ]`
# a `case "$TARGET" in claude|codex)`: el sed de esta mutacion se actualiza al
# literal nuevo (el patron `*)` matchea cualquier target, mismo efecto que el
# `if true` de antes). Si el sed viejo quedara, la guardia 2 del driver ("la
# mutacion no cambio nada") reventaria la bateria entera.
# Phase 15 (PR #85) sumo dsh al case: el ancla sigue al literal nuevo (misma
# guardia 2 que atrapo ceremonia_sin_grok/sin_codex en CI).
mut_secuencia_tambien_en_cursor() { sed 's/case "\$TARGET" in claude|codex|grok|dsh)/case "$TARGET" in *)/'; }
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
mut_ceremonia_sin_codex()    { sed 's/case "\$TARGET" in claude|codex|grok|dsh)/case "$TARGET" in claude|grok|dsh)/'; }
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
# Task 15.2 (D2): apaga la rama dsh de la deteccion de HOST, espejo de
# mut_host_codex_sin_rama. Sin la rama, target dsh resuelve HOST=other y el
# armado no crea state/dsh/. Lo atrapa caso_g1_dsh_arma_y_aisla_estado.
mut_host_dsh_no_reconocido() { sed 's/= "dsh" \]; then/= "NUNCA_dsh" ]; then/'; }
# Phase 15 (D1/D3): revierte la ceremonia a claude|codex|grok — el gate vuelve a
# quedar inerte en dsh. Lo atrapa caso_g2_dsh_ceremonia_incompleta_bloquea (el
# turno sin verifier pasa a cerrar en vez de bloquear).
mut_ceremonia_sin_dsh()      { sed 's/case "\$TARGET" in claude|codex|grok|dsh)/case "$TARGET" in claude|codex|grok)/'; }
# Phase 15 (D4): vuelve la tool model-facing de dsh a "Task tool". Lo atrapa
# caso_g1_dsh_contrato_nombra_subagent.
mut_tool_hint_sin_dsh()      { sed 's|if \[ "\$TARGET" = "dsh" \]; then TOOL_HINT="the subagent tool"|if [ "$TARGET" = "dsh" ]; then TOOL_HINT="the Task tool"|'; }
# Task 7.4 (D3): revierte la ceremonia a claude|codex — el gate vuelve a ser
# inerte en grok. Lo atrapa caso_g3_grok_ceremonia_incompleta_bloquea (el turno
# incompleto pasa a cerrar limpio y el decision:block desaparece).
# Phase 15 (PR #85) movio el case a `claude|codex|grok|dsh)` y este sed quedo
# OBSOLETO: la guardia 2 ("la mutacion no cambio nada del hook") lo atrapo en CI
# y master quedo rojo desde ese merge. El ancla sigue al literal nuevo; se
# quita SOLO grok (dsh queda) — mismo efecto que antes: el gate inerte en grok.
mut_ceremonia_sin_grok()  { sed 's/case "$TARGET" in claude|codex|grok|dsh)/case "$TARGET" in claude|codex|dsh)/'; }
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
# 18.23: el prefijo anclado (^|\n-literal)[[:space:]]*([-*+][[:space:]]+)?
# (\*\*|__)? de has_receipt_label reemplazo a la frontera izquierda de las
# Tasks 8.3/9.3 — frontera y ancla colapsaron en UN solo concepto, y las dos
# mutaciones viejas (etiqueta_sin_frontera, frontera_acepta_comillas) sedian
# un literal que dejo de existir (la guardia 2, "la mutacion no cambio nada",
# las reventaba). Esta mutacion sola cubre todas las caras: sin el prefijo, la
# etiqueta vuelve a aceptarse pegada a mitad de palabra, citada entre comillas
# en el feedback y transportada como llega a codex (\n literal incluido, que
# `.` tambien traga). Lo atrapan: caso_g4_recibo_en_un_parrafo_bloquea (las
# seis etiquetas en un solo parrafo vuelven a cerrar el turno),
# caso_g4_recibo_codex_escape_doble_cierra, caso_g4_recibo_vineta_asterisco_pasa,
# caso_g4_cita_del_feedback_no_satisface y caso_g4_etiqueta_pegada_no_cuenta
# (el driver nombra solo el primero que reacciona). Escaping BRE: `\^` es el
# circunflejo LITERAL (pelado al inicio del patron seria ancla), los cuatro
# backslashes del \n literales del hook son `\\\\\\\\` (ocho: dos por cada
# backslash literal), el `+` va PELADO (literal en BRE; `\+` es cuantificador
# en GNU sed) y `(\\\*\\\*|__)?` sigue la forma de mut_etiqueta_sin_bold. El
# hook mutado queda `(^|.)(...)`: cualquier posicion con un caracter delante.
mut_ancla_de_linea_quitada(){ sed 's/(\^|\\\\\\\\n)\[\[:space:\]\]\*(\[-\*+\]\[\[:space:\]\]+)?(\\\*\\\*|__)?/(^|.)/'; }
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
# 18.27 (D-B): la guardia de backgroundTasks de la escotilla grok se
# neutraliza (siempre "en vuelo") y un Stop con la linea DELEGATED y el array
# VACIO vuelve a permitir — la salida headless sin recibo del hallazgo E. El
# ancla es la INICIALIZACION grok_bg_en_vuelo=0 (unica ocurrencia del =0; la
# otra asignacion es =1 dentro del case). Lo atrapa
# caso_g4_grok_delegado_sin_bg_bloquea.
mut_delegado_grok_sin_bg() { sed 's/grok_bg_en_vuelo=0/grok_bg_en_vuelo=1/'; }
# 18.27 (D-B) review r2 (R27-3), reescrita para el lector estructural de la
# 20.4: la exigencia de CONTENIDO dentro del array (hay trabajo solo si se VE
# algo entre "[" y su "]") se quita del veredicto del awk — con eso todo array
# que abre y cierra pareado cuenta como poblado, y el VACIO ([] y [ ])
# vuelve a habilitar la escotilla (null no: nunca abre el array). Lo atrapa
# caso_g4_grok_delegado_bg_degenerado_bloquea, y antes a el
# caso_g4_grok_delegado_sin_bg_bloquea con el [] compacto.
# (Una sola linea a proposito: el c\\ multilinea de otras mutaciones no
# inserta texto en el sed BSD local.)
mut_delegado_grok_bg_degenerado() { sed 's/cerro && contenido) { print "1" }/cerro) { print "1" }/'; }
# r1 (cross-review 20.x): la gramatica COMPLETA del documento entro al veredicto
# del awk (gram_arr = validez de lo DENTRO del array buscado, gram_doc = validez
# del documento entero). Tres mutaciones, una por proteccion nueva:
#   solo_balance: el veredicto vuelve a "balance + primer token" (sin gram_*; el
#     estado terminal st == "A" SIGUE en el veredicto). r3 (Grok, medido): NO
#     son "las cuatro formas" — las que viven SOLO en gram_* reabren y las que
#     mata la maquina abierta no. Tabla medida sano→mutante:
#       [nul]=bloquea→bloquea (queda en st="L"≠"A" y eso no lo toca la mutacion)
#       [1. ]=bloquea→bloquea (idem, st queda en subestado de numero incompleto)
#       [1,]=bloquea→PERMITE    bad:oops=bloquea→PERMITE    trailing=bloquea→PERMITE
#       (y desde r3, "\q"=bloquea→PERMITE: la inval del escape vive en gram_*)
#   bg_trailing: la rama de basura tras el cierre del root (o separador invalido
#     tras valor) deja de invalidar — el sub-caso del trailing garbage vuelve a
#     PERMITIR.
#   bg_ignora_doc: gram_doc sale del veredicto; solo cuenta lo de dentro del
#     array — un valor roto en OTRA clave del documento vuelve a PERMITIR
#     ([nul] y [1,] siguen rechazados por gram_arr: la mutacion aisla la
#     validez FUERA de la clave).
# r3 (cross-review hosts, hallazgo ALTA): dos mutaciones mas, una por mitad de
# la estrictura de ESCAPES nueva:
#   bg_escape_leniente: se quita la inval del caracter tras "\" — cualquier
#     escape vuelve a valer y "\q" reabre la escotilla.
#   bg_control_crudo: se quita la inval del char de control crudo en strings y
#     el tab literal dentro de un string vuelve a valer.
#   bg_uhex_leniente: se quita la inval del hex tras "\u" y "\u12G34" (una G
#     colada entre hex) vuelve a valer; "\u12G"/"\u12GX" solas NO discriminan
#     esta rama (sin la inval el string queda abierto y caen igual).
mut_delegado_grok_bg_solo_balance() { sed 's/if (gram_arr && gram_doc && pila == ""/if (pila == ""/'; }
mut_delegado_grok_bg_trailing()     { sed 's/else gram_doc = 0   # r1-trailing/else { }                # r1-trailing/'; }
mut_delegado_grok_bg_ignora_doc()   { sed 's/if (gram_arr && gram_doc && pila/if (gram_arr \&\& pila/'; }
mut_delegado_grok_bg_escape_leniente() { sed '/^            inval()   # r3-escape: tras/d'; }
mut_delegado_grok_bg_control_crudo()   { sed '/^          if (c < " ") { inval(); continue }   # r3-control/d'; }
mut_delegado_grok_bg_uhex_leniente()   { sed '/^            else inval()   # r3-uhex/d'; }
# r4 (review r2 del PR #273, hallazgo P1): la decodificacion de escapes al
# acumular la clave se quita — los escapes se VALIDAN pero su aporte vuelve a
# descartarse (key_buf = key_buf, sin el char decodificado), asi que una clave
# DISTINTA escrita con escapes ("back\ngroundTasks", "background\u0000Tasks",
# "backgroundTasks\t") vuelve a colapsar sobre backgroundTasks y a habilitar
# la escotilla sin trabajo en vuelo. OJO la forma: el `continue` se conserva
# en su lugar — reescribir el bloque a `{ if (st == "SK") continue }` dejaria
# caer los escapes VALIDOS de los strings de VALOR al inval() de abajo y el
# caso multilinea (lastAssistantMessage con \n\n) se pondria rojo ANTES, por
# la razon equivocada. Lo atrapa caso_g4_grok_delegado_bg_clave_escapada (las
# tres contrapruebas esperan block y vuelve a salir allow).
mut_delegado_grok_bg_escape_clave_sin_decodificar() {
  sed -e 's/key_buf = key_buf c; continue/key_buf = key_buf; continue/' \
      -e 's/key_buf = key_buf noascii; continue/key_buf = key_buf; continue/' \
      -e '/key_buf = key_buf udec(uhex)/d'
}
# 20.4: la lectura ESTRUCTURAL del array de primer nivel vuelve al grep
# textual de la 18.27 — con el, la forma MULTILINEA (contenido en la linea
# siguiente a "[") vuelve a NO matchear y el Stop que espera de verdad a un
# subagente async bloquea en vez de permitir. Lo atrapa
# caso_g4_grok_delegado_bg_multilinea_permite. (c\\ de una linea, mismo
# formato que mut_paused_sin_guardia_de_recibo; los \\[ del ERE doblados
# porque el texto de c\ come un nivel de backslash.)
mut_delegado_grok_bg_textual() { sed '/if \[ "\$(json_top_level_array_poblado backgroundTasks)" = "1" \]; then/c\
  if printf '\''%s'\'' "$INPUT" | grep -Eq '\''"backgroundTasks":[[:space:]]*\\[[[:space:]]*[^][:space:]]'\''; then'; }
# Task 11.2 (hallazgo de campo Kimi 2026-08-16), mitad 1: revierte la clausula
# !recibo de la escotilla PAUSED — reescribe el if completo (condicion +
# continuacion + cuerpo) a la forma vieja de una sola condicion. El ancla es el
# grep del PAUSED, que solo aparece en la condicion de la escotilla (el texto
# del contrato y el feedback del gate citan la frase sin "grep -Eiq '" delante,
# asi que la mutacion no los toca). Sin la guardia, un recibo + PAUSED vuelve a
# saltar el gate entero -- lo atrapa caso_g4_recibo_completo_mas_paused_cierra_limpio
# (primero en el orden de CASOS_G4; el roto+PAUSED, caso_g4_recibo_roto_mas_
# paused_sigue_exigiendo, reacciona igual).
mut_paused_sin_guardia_de_recibo() { sed "/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'/,+3c\\
  if printf '%s' \"\$text_hatch\" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'; then emit_allow; fi"; }
# Task 11.2, mitad 2: INVIERTA la guardia — la escotilla solo permite si hay
# recibo PRESENTE (if anidado, sin `&&` para no pelear con el `&` de sed en el
# reemplazo). Con eso, una pausa legitima SIN recibo (la unica que la escotilla
# debe permitir) vuelve a bloquear -- lo atrapa caso_g4_pausa_permite (ningun
# otro caso de CASOS_G4 pausa sin recibo: los nuevos de la 11.2 siempre lo
# llevan puesto).
mut_paused_exige_recibo() { sed "/grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'/,+3c\\
  if printf '%s' \"\$text_hatch\" | grep -Eiq 'SUMMONAIKIT HARNESS PAUSED'; then if printf '%s' \"\$text_hatch\" | grep -Eiq \"\$RECEIPT_MARKER_RE\"; then emit_allow; fi; fi"; }
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

# Task 11.4, mitad 1: neutraliza el cierre unknown honesto — la condicion del
# if nunca se cumple y un Stop con AMBOS canales de texto ciegos vuelve al
# gate normal: rc 2 consumiendo ciclo por evidencia que el gate no puede ver.
# Lo atrapa caso_g4_ambos_canales_ciegos_cierra_unknown (espera rc 0 y estado
# limpio; con la mutacion vuelve a bloquear con estado vivo).
mut_unknown_honesto_quitado() { sed 's/\[ "$canal_payload_observed" -eq 0 \] \&\& \[ "$transcript_observed" -eq 0 \]/[ "$canal_payload_observed" -eq 1 ] \&\& [ "$transcript_observed" -eq 1 ]/'; }
# Task 11.4, mitad 2: apaga SOLO la deteccion del canal payload — el flag ya
# nunca marca observado, asi que el unknown honesto dispara tambien con
# last_assistant_message PRESENTE sin recibo (ausencia OBSERVADA), que debe
# seguir bloqueando. La atrapa caso_g4_campo_presente_sin_recibo_sigue_
# bloqueando (espera rc 2 y estado vivo; con la mutacion cierra en exit 0);
# la declaracion de la corrida puede nombrar antes a otro caso del gate que
# tambien reacciona (p.ej. caso_g4_delegado_sin_rol_bloquea) — con el canal
# payload ciego, TODO caso que espera bloqueo con campo presente se pone rojo.
mut_unknown_ciega_al_payload() { sed 's/canal_payload_observed=1/canal_payload_observed=0/'; }

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

# Task 13.5 (D4/D6) — una mutacion por condicion nueva del rol adversary, cada
# una acreditada a su caso del gate G3 (los 9 casos D6 viven al final de
# CASOS_G3). Anclas: la rama adversar de canonical_agent_role, la alternancia
# DELEGATED, la etiqueta ADVERSARY, la sustitucion ROLE FALLBACK y el trigger
# de orden de 4 roles — cada literal aparece una sola vez en el hook.
mut_adv_keyword_sin_precedencia() { sed "s@grep -Eq '(^|\[^a-z\])adversar'@grep -Eq '(^|[^a-z])adversarZ'@"; }
mut_adv_delegated_sin_adversary() { sed "s@reviewer|adversary)'@reviewer)'@"; }
mut_adv_linea_no_se_exige()       { sed 's/has_receipt_label "ADVERSARY" "ADVERSARIO"/has_receipt_label "ADVERSARY-NUNCA" "ADVERSARIO-NUNCA"/'; }
mut_adv_fallback_sin_adversary()  { sed "s/'ROLE FALLBACK: \*ADVERSARY'/'ROLE FALLBACK: *ADVERSARYNUNCA'/"; }
mut_adv_orden_sin_adversary()     { sed 's/grep -q adversary \&\& printf/grep -q adversaryNUNCA \&\& printf/'; }

# Task 13.6 (D1) — el contrato de armado es el canal que invoca el rol: si el
# texto pierde el criterio de delegacion o la forma del despacho que nombra el
# artefacto, el mecanismo entero queda sin disparador. Ambas las atrapa
# caso_g1_contrato_nombra_adversary (grepea el stdout del armado).
mut_adv_contrato_criterio_roto()  { sed 's/OPTIONAL fourth role/OPTIONAL third role/'; }
mut_adv_contrato_despacho_roto()  { sed 's/NAMING the artifact to adjudicate/NAMING the artifact to discard/'; }

# 18.11 / D24 — una mutacion por guarda nueva. Cada sed apunta a UN ancla
# (anti-patron 18.24: una mutacion que apaga varias guardas a la vez).
mut_pretool_gh_pr_merge_apagado() { sed "s/grep -Eiq 'gh\[\[:space:\]\]+pr\[\[:space:\]\]+merge'/grep -Eiq 'gh[[:space:]]+pr[[:space:]]+MERGE-NUNCA'/"; }
# F1: restaura el match literal; atrapa caso_g7_niega_gh_pr_merge_espaciado.
mut_pretool_gh_pr_merge_literal() { sed "s/grep -Eiq 'gh\[\[:space:\]\]+pr\[\[:space:\]\]+merge'/grep -Fq 'gh pr merge'/"; }
mut_pretool_gh_api_merge_apagado() { sed 's/api\[\^\[:cntrl:\]\]\*\/merge/api[^[:cntrl:]]*\/mergeNUNCA/'; }
mut_pretool_git_push_protegida_apagado() { sed 's/^  _pt_git_push_re=.*/  _pt_git_push_re='\''git[[:space:]]+pushNUNCA'\''/'; }
# F3: restaura git pegado a push; atrapa caso_g7_niega_git_dash_c_push
# y caso_g7_niega_git_no_pager_push.
mut_pretool_git_push_exige_inmediato() { sed 's/^  _pt_git_push_re=.*/  _pt_git_push_re='\''git[[:space:]]+push'\''/'; }
# Dest pierde [+:]? (force/delete); atrapa caso_g7_niega_git_push_force_y_delete.
mut_pretool_git_push_dest_sin_plus_colon() { sed '/_pt_git_dest_re=/s/\[+:\]?//g'; }
# F4: restaura token master|main en cualquier lado; atrapa caso_g7_permite_git_push_url_main.
mut_pretool_git_push_token_en_cualquier_lado() { sed 's/^  _pt_git_dest_re=.*/  _pt_git_dest_re='\''(^|[^[:alnum:]_-])(master|main)([^[:alnum:]_-]|$)'\''/'; }
mut_pretool_hatch_siempre_ok() { sed 's/pretool_pins_iguales() { \[ "$1" = "$2" \]; }/pretool_pins_iguales() { return 0; }/'; }
mut_pretool_hatch_nunca_ok() { sed 's/pretool_pins_iguales() { \[ "$1" = "$2" \]; }/pretool_pins_iguales() { return 1; }/'; }
# F2: el strip de comillas se vuelve identidad; atrapa caso_g7_hatch_comillas_ok.
mut_pretool_hatch_sin_strip_comillas() { sed 's/pretool_strip_comillas_hatch "/printf %s "/'; }
# Lead PR #198: apaga el deny de sufijo; atrapa caso_g7_niega_hatch_sufijo_bak.
mut_pretool_hatch_spoof_apagado() {
  sed 's/^pretool_es_hatch_spoof() {$/pretool_es_hatch_spoof() { return 1; }\npretool_es_hatch_spoof_OFF() {/'
}
mut_pretool_cae_a_tool() { sed 's/PreToolUse|preToolUse|pre_tool_use) PHASE="pretool" ;;//'; }
# Restaura el short-circuit hatch-primero: hash ok => allow aunque el
# mismo comando tambien traiga gh pr merge / gh api /merge / git push.
mut_pretool_hatch_antes_de_pelo() { sed 's/if pretool_es_gh_pr_merge "$_pt_cmd"; then/if pretool_es_hatch "$_pt_cmd"; then if pretool_hatch_verifica "$_pt_cmd" "$_pt_cwd"; then emit_allow; fi; emit_pretool_deny "merge denied: saikit-merge.sh hash does not match the kit manifest"; fi; if pretool_es_gh_pr_merge "$_pt_cmd"; then/'; }

mut_trail_sin_limite_fisico() { sed 's/"$ADV_PROJECT_CANON"|"$ADV_PROJECT_CANON"\/\*) return 0 ;;/\*) return 0 ;;/'; }
mut_trail_skip_preambulo() { sed '/^has_trail_skip()/,/^}/s/trail_receipt="$(trail_receipt_block "$1")"/trail_receipt="$1"/'; }
mut_trail_close_preambulo() { sed '/^close_span()/,/^}/s/trail_receipt="$(trail_receipt_block "$1")"/trail_receipt="$1"/'; }
mut_trail_acepta_archivo_enlazado() { sed '/\[ ! -L "\$_joined" \] || return 1/d'; }
mut_trail_check_eliminado() { sed 's/if ! has_trail_skip "\$text_hatch"; then/if false; then/'; }
mut_trail_vuelve_a_glob() {
  awk '
    /^trail_cited_and_present\(\) \{$/ {
      print "trail_cited_and_present() { [ -n \"$(find \"$PROJECT_ROOT/.saikit/decisiones\" -name \"*.tsv\" 2>/dev/null | head -n1)\" ] && [ -n \"$(find \"$PROJECT_ROOT/.saikit/findings\" -name \"blast-*.json\" 2>/dev/null | head -n1)\" ]; return; }"
      print "trail_cited_and_present_OFF() {"
      next
    }
    { print }
  '
}
mut_trail_acepta_glob_token() {
  awk '
    /^TRAIL_TSV_CITE_RE=/ { print "TRAIL_TSV_CITE_RE='"'"'(\\./)?\\.saikit/decisiones/[^[:space:]]+\\.tsv'"'"'"; next }
    /^TRAIL_BLAST_CITE_RE=/ { print "TRAIL_BLAST_CITE_RE='"'"'(\\./)?\\.saikit/findings/blast-[^[:space:]]+\\.json'"'"'"; next }
    /\*'\''\*'\''\*/ { next }
    /^path_present_under_root\(\) \{$/ {
      print
      print "  case \"$1\" in *\"*\"*) _m=$(find \"$PROJECT_ROOT/$(dirname -- \"$1\")\" -name \"$(basename -- \"$1\")\" 2>/dev/null | head -n1); [ -n \"$_m\" ]; return; esac"
      next
    }
    { print }
  '
}
mut_trail_sin_existir() {
  awk '
    /^path_present_under_root\(\) \{$/ {
      print "path_present_under_root() { return 0; }"
      print "path_present_under_root_OFF() {"
      next
    }
    { print }
  '
}
mut_trail_solo_tsv() { sed 's/\[ "\$_tsv" -eq 0 \] \&\& \[ "\$_blast" -eq 0 \]/[ "$_tsv" -eq 0 ]/'; }
mut_trail_solo_blast() { sed 's/\[ "\$_tsv" -eq 0 \] \&\& \[ "\$_blast" -eq 0 \]/[ "$_blast" -eq 0 ]/'; }
mut_trail_lee_recibo_entero() { sed 's/close_span "\$text_hatch"/printf "%s" "$text_hatch"/'; }
mut_trail_skip_vacio() {
  awk '
    /^has_trail_skip\(\) \{$/ {
      print "has_trail_skip() { return 0; }"
      print "has_trail_skip_OFF() {"
      next
    }
    { print }
  '
}
mut_trail_skip_sin_razon() { sed '/TRAIL SKIP.*\[\^\[:space:]]/d'; }
mut_trail_skip_substring() {
  awk '
    /^has_trail_skip\(\) \{$/ {
      print "has_trail_skip() { printf \"%s\" \"$1\" | grep -Fq \"TRAIL SKIP:\"; }"
      print "has_trail_skip_OFF() {"
      next
    }
    { print }
  '
}
mut_trail_lee_text_entero() { sed 's/has_trail_skip "\$text_hatch"/has_trail_skip "$text"/; s/close_span "\$text_hatch"/close_span "$text"/'; }
mut_trail_tambien_en_fast() {
  awk '
    /has_trail_skip "\$text_hatch"/ {
      if (prev ~ /read_state_value lane/) sub(/!= "fast"/, "!= \"__never__\"", prev)
    }
    NR>1 { print prev }
    { prev=$0 }
    END { print prev }
  '
}
mut_trail_parrafo_solo_hc() { sed 's/_gf="\$(printf '\''%s\\n\\n%s'\'' "\$_gf" "\$(trail_parrafo)")"/_gf="$_gf"/'; }

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

# ------------------------------------------------------ shard para CI (2026-08-29)
# Medido en el run 33232669996: 111 mutaciones a ~3.2 s cada una = ~6 min, y este
# archivo SOLO fijaba el reloj del PR entero (el resto de la bateria son 2.7 min,
# en paralelo). `SAIKIT_MUT_SHARD="i/N"` corre la i-esima de N partes, repartidas
# round-robin POR POSICION (no por gate: asi ninguna parte se queda con todos los
# casos caros de un mismo gate).
#
# No saltea nada: la union de las N partes es la lista ENTERA, y
# `tests/test_gate_mutations_guards.sh` lo canda — una parte que perdiera
# mutaciones seria un candado que deja de correr sin que nadie se entere, la
# misma falla silenciosa que esta bateria existe para evitar. Un shard vacio o
# una forma invalida cortan con exit 2 en vez de reportar verde.
if [ -n "${SAIKIT_MUT_SHARD:-}" ]; then
  case "$SAIKIT_MUT_SHARD" in
    [1-9]/[1-9]|[1-9]/[1-9][0-9]|[1-9][0-9]/[1-9][0-9]) ;;
    *) echo "test_gate_mutations: SAIKIT_MUT_SHARD invalido: [$SAIKIT_MUT_SHARD] — forma i/N" >&2; exit 2 ;;
  esac
  _sh_i="${SAIKIT_MUT_SHARD%%/*}"
  _sh_n="${SAIKIT_MUT_SHARD##*/}"
  if [ "$_sh_i" -gt "$_sh_n" ]; then
    echo "test_gate_mutations: shard $_sh_i fuera de rango (son $_sh_n)" >&2; exit 2
  fi
  MUTACIONES="$(printf '%s\n' "$MUTACIONES" | awk -v i="$_sh_i" -v n="$_sh_n" \
    '/^[A-Za-z0-9]+\|/ { c++; if ((c - 1) % n == i - 1) print }')"
  if [ -z "$MUTACIONES" ]; then
    echo "test_gate_mutations: el shard $SAIKIT_MUT_SHARD quedo VACIO — no corrio ninguna mutacion" >&2
    exit 2
  fi
  echo "test_gate_mutations: shard $SAIKIT_MUT_SHARD — $(printf '%s\n' "$MUTACIONES" | grep -c .) mutaciones"
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
