#!/usr/bin/env bash
# gate_cases.sh — la semantica ACTUAL del gate, caso por caso (Task 1.3).
#
# QUE ES: un corpus de casos ejecutables sobre `$HOOK_BAJO_PRUEBA`. Cada caso
# afirma una cosa puntual y devuelve verde/rojo. Lo consumen DOS baterias con
# veredictos opuestos, y por eso vive en una lib y no adentro de un test:
#
#   tests/test_gate_behavior.sh   los corre contra el hook VIVO: todos verdes.
#   tests/test_gate_mutations.sh  los corre contra copias del hook con la
#                                 condicion de un gate rota: al menos uno rojo.
#
# La segunda es la que le da valor a la primera. Un caso que sigue verde con el
# gate roto no esta probando el gate: esta mirando para otro lado. Esa es la
# declaracion de mutation-test que pide la DoD de la Task 1.3, y esta escrita
# como codigo que corre, no como una frase en un reporte.
#
# ---------------------------------------------------------------------------
# ESTO GRABA LO QUE EL HOOK HACE HOY, NO LO QUE DEBERIA HACER.
#
# Cuatro casos afirman comportamiento que ya sabemos DEFECTUOSO, con el numero
# de defecto y la task que lo corrige escritos al lado:
#
#   caso_g4_recibo_corrido_bloquea_a8   A8 — un recibo correcto en texto
#                                       corrido no satisface ninguna etiqueta.
#   caso_g4_pausa_permite               la mitad buena de A2: la pausa se busca
#                                       grepeando el texto crudo, asi que el
#                                       mismo grep la encuentra donde no debe.
#   caso_g3_agent_type_cuenta            A9 — INVERTIDO por la Task 3.7. Antes
#                                       `caso_g3_agent_type_no_cuenta` y afirmaba
#                                       lo opuesto: el rol viaja en `agent_type`
#                                       de primer nivel y el hook no lo miraba.
#                                       Ahora el hook lee agent_type (fallback) y
#                                       el caso afirma que SI cuenta.
#   caso_g2_runner_fallido_forma_real   A11 — INVERTIDO por la Task 3.8. Antes
#                                       afirmaba `verified=1` (defecto): el
#                                       guardia buscaba `exitCode`, campo que
#                                       el payload real no trae. Ahora el hook
#                                       grepea patrones reales de fracaso y el
#                                       caso afirma `verified=0`.
#
# Cuando la Task 3.2 los arregle, estos casos CAMBIAN DE EXPECTATIVA a proposito
# y ese diff es la declaracion de que cambio. No se los "arregla" antes: una
# suite que ya espera el comportamiento corregido no detecta nada el dia que se
# corrige.
# ---------------------------------------------------------------------------
#
# Convenciones:
#   - Un caso NUNCA corre en subshell: marca su veredicto en $CASO_ROJO.
#   - El driver limpia el estado antes de cada caso (turno nuevo).
#   - Los casos se listan en $CASOS_<GATE>, del mas barato al mas caro: la
#     bateria de mutaciones corta en el primer rojo, y en Windows cada corrida
#     del hook cuesta ~2 segundos.

# --------------------------------------------------------------- afirmaciones
CASO_ROJO=0

_mal()      { printf '      FAIL: %s\n' "$1"; CASO_ROJO=1; }
_igual()    { if [ "$2" != "$3" ]; then _mal "$1: esperaba [$3], dio [$2]"; fi; }
_vacio()    { if [ -n "$2" ]; then _mal "$1: esperaba vacio, dio [$(printf '%s' "$2" | head -c 200)]"; fi; }
_no_vacio() { if [ -z "$2" ]; then _mal "$1: esperaba algo, quedo vacio"; fi; }

_contiene() {
  if ! printf '%s' "$2" | grep -Fq "$3"; then
    _mal "$1: no contiene [$3]"
  fi
}

_no_contiene() {
  if printf '%s' "$2" | grep -Fq "$3"; then
    _mal "$1: NO deberia contener [$3]"
  fi
}

# Corre un caso y devuelve su veredicto como exit code. No usar dentro de
# `$(...)`: el caso marca $CASO_ROJO y en un subshell esa marca se perderia.
correr_caso() {
  CASO_ROJO=0
  lab_limpiar_estado
  "$1"
  return "$CASO_ROJO"
}

# ------------------------------------------------------------------- fixtures
# Los saltos van escapados (\n) porque asi los guarda un JSONL real. Ese detalle
# no es cosmetico: de ahi sale A8.
_RECIBO_VINETAS='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.\n- Retro: none.'

_RECIBO_CORRIDO='SUMMONAIKIT HARNESS RECEIPT\nUnderstand: pediste poder listar las sesiones abiertas.\nImplement: se agrego el endpoint y su ruta.\nVerify: se corrio la bateria completa, 12 en verde.\nReview: sin hallazgos.\nClose: entregado; no se toco codigo despues de la revision.\nRetro: none.'

_RECIBO_SIN_RETRO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.'

# Igual al anterior pero declarando que la verificacion no se corrio. El gate
# acepta esa declaracion como sustituto de la evidencia.
_RECIBO_SIN_RETRO_SALTEADO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: skipped, este repo no tiene bateria propia.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.'

# Vivo 2026-08-13 (zcode -saikit): el modelo escribio "No corri los candados"
# y mostro od/wc. El gate reclamo evidencia porque solo aceptaba
# not run / skipped / italiano. Este recibo es el catch: sin esas palabras
# inglesas, con la prosa espanola del turno.
_RECIBO_SIN_RETRO_NO_CORRI='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste un archivo que diga hola.\n- Implement: hola.txt ya existia, no se toco nada.\n- Verify: No corri los candados de commit porque no hay nada nuevo; od -c mostro hola y wc -c dio 5 bytes.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.'

# Recibo donde Verify termina con "pytest." (punto final de frase). Sin la
# alternativa de punto-de-frase en TEST_RUNNER_WORD_RE, el punto despues de
# `pytest` lo excluye y el gate reclama evidencia que esta. Es el test de la
# CORRECCION 2 del plan de la 3.3: el wrapper se aplica a DOS superficies
# (comando y prosa) y un punto al final de una oracion NO es una extension.
_RECIBO_SIN_RETRO_PYTEST_PUNTO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio pytest.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.'

# D4 (Task 6.3) — ROLE FALLBACK: <ROL> (razon) declarado en el recibo, en vez
# del despacho, para cuando el subagente se cae por infraestructura (429,
# limite de uso, error de herramienta). La declaracion puede vivir en
# cualquier parte del recibo; aca se la agrega al final del bullet de Close,
# como la escribiria el lead real. Un fixture por rol (los tres casos abajo
# necesitan el suyo propio: ver el comentario sobre CASOS_G3).
_RECIBO_ROLE_FALLBACK_IMPLEMENTER='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision. ROLE FALLBACK: IMPLEMENTER (429).\n- Retro: none.'

_RECIBO_ROLE_FALLBACK_VERIFIER='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision. ROLE FALLBACK: VERIFIER (429).\n- Retro: none.'

_RECIBO_ROLE_FALLBACK_REVIEWER='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision. ROLE FALLBACK: REVIEWER (429).\n- Retro: none.'

# C7 (auditoria 2026-08-13, Task 8.3) — el recibo con las etiquetas en
# markdown bold (**Label**:), la forma MAS natural en que el modelo escribe
# listas. El `**` entre la etiqueta y el `:` rompia has_receipt_label y un
# recibo honesto y completo se bloqueaba con las seis etiquetas "faltantes".
_RECIBO_BOLD='SUMMONAIKIT HARNESS RECEIPT\n- **Understand**: pediste poder listar las sesiones abiertas.\n- **Implement**: se agrego el endpoint y su ruta.\n- **Verify**: se corrio la bateria completa, 12 en verde.\n- **Review**: sin hallazgos.\n- **Close**: entregado; no se toco codigo despues de la revision.\n- **Retro**: none.'

_TEXTO_LLANO='Ya quedo el endpoint de sesiones. Avisame si querias otra cosa.'
_TEXTO_PAUSA='Necesito saber que datos van en la lista.\n\nSUMMONAIKIT HARNESS PAUSED - awaiting your answer'

# Escotilla "delegado y en vuelo" (arreglo 1): hermana de la pausa, para cuando
# el lead delego a un subagente (implementer/verifier/reviewer) que todavia no
# contesto. Tiene que NOMBRAR el rol -- el segundo fixture omite el rol a
# proposito, para el caso que confirma que sin el la escotilla no vale.
_TEXTO_DELEGADO='Delegue la verificacion al subagente verifier y sigue corriendo.\n\nSUMMONAIKIT HARNESS DELEGATED - awaiting verifier'
_TEXTO_DELEGADO_SIN_ROL='Delegue el trabajo y sigue corriendo.\n\nSUMMONAIKIT HARNESS DELEGATED'

# C11 (auditoria 2026-08-13, Task 9.3) — un mensaje que CITA la mecanica del
# gate: nombra el marcador del recibo y las seis etiquetas entre comillas
# simples, como las escribiria alguien explicando lo que el gate le pidio. La
# comilla pasaba la frontera [^[:alpha:]] de has_receipt_label y el turno
# cerraba sin recibo real.
_TEXTO_CITA_FEEDBACK='El gate me pidio: agregar una linea que empiece con '"'"'Understand:'"'"' dentro del bloque SUMMONAIKIT HARNESS RECEIPT, y lo mismo para '"'"'Implement:'"'"', '"'"'Verify:'"'"', '"'"'Review:'"'"', '"'"'Close:'"'"' y '"'"'Retro:'"'"'. Lo hago en el siguiente turno.'

# Bug de cross-review (ciclo 1), REPRODUCIDO con ejecucion: la escotilla
# DELEGATED disparaba con CUALQUIER texto que trajera la frase, sin comprobar
# que el recibo estuviera ausente. Estos dos fixtures son las dos pruebas del
# revisor.
#
# Mitad "roto": ningun subagente corrio, falta Retro, no hay ROLE FALLBACK, y
# el bullet de Close menciona la frase DELEGATED de pasada (una nota sobre
# OTRA tarea, no una pausa real de esta).
_RECIBO_ROTO_CON_DELEGADO_INCIDENTAL='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; nota aparte: en otra tarea deje dicho SUMMONAIKIT HARNESS DELEGATED - awaiting verifier, no en esta.'

# Mitad "completo": recibo VALIDO con las 6 etiquetas, que menciona la frase
# DELEGATED en el bullet de Retro -- plausible, porque el propio formato del
# recibo invita a comentar mejoras del harness ahi.
_RECIBO_VINETAS_CON_DELEGADO_EN_RETRO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio la bateria completa, 12 en verde.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.\n- Retro: el harness podria documentar mejor el patron SUMMONAIKIT HARNESS DELEGATED - awaiting verifier para subagentes largos.'

# Un turno sembrado como "todo en orden salvo lo que el caso quiera romper".
_sembrar_turno_completo() { lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"; }

# ============================================================== LAB (auto-test)
# El banco siembra estado escribiendo en la ruta que descubrio al arrancar. Si
# esa ruta dejara de ser la que el hook usa, TODOS los casos sembrados pasarian
# a probar nada y quedarian verdes por vacio. Este caso es el que lo impide.
CASOS_LAB="caso_lab_ruta_de_estado_es_la_que_usa_el_hook"

caso_lab_ruta_de_estado_es_la_que_usa_el_hook() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit un turno cualquiera')"
  real="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  _no_vacio "estado tras armar" "$real"
  _igual "ruta de estado del banco" "$LAB_ESTADO_PATH" "$real"
}

# ================================================== G1 — armado por el sentinel
CASOS_G1="caso_g1_no_arma_sin_sentinel caso_g1_arma_con_sentinel caso_g1_sentinel_con_frontera caso_g1_dos_sesiones_no_comparten_estado caso_g1_prompt_sin_sentinel_desarma caso_g1_correccion_al_vuelo_no_desarma caso_g1_session_id_anidado_no_reescribe_ruta caso_g1_dos_hosts_mismo_repo_no_comparten_estado caso_g1_host_segun_senal caso_g1_arma_con_comillas_antes_del_sentinel caso_g1_correccion_con_comillas_no_desarma caso_g1_arma_con_sentinel_en_linea_nueva caso_g1_fast_arma_con_lane caso_g1_pelado_arma_lane_full caso_g1_sufijo_desconocido_arma_full caso_g1_session_inyecta_reglas caso_g1_session_no_desarma caso_g1_session_con_sentinel_en_summary_arma_y_no_da_reglas caso_g1_prompt_sin_campo_no_arma caso_g1_estado_no_se_acumula caso_g1_dos_hosts_codex_y_claude_no_comparten_estado caso_g1_host_codex_solo_literal caso_g1_grok_senal_exportada_vacia_cuenta caso_g1_grok_envelope_arma caso_g1_dos_hosts_grok_y_claude_no_comparten_estado caso_g1_grok_stop_shutdown_no_toca_estado"

# Task 10.6: reglas PERMANENTES en la fase session. No gatean, no arman, no
# cuentan ciclos: dejan escrito el invariante una vez por sesion, arme o no.
#
# Por que existe: la regla "una corrida de la bateria por tarea" YA estaba en el
# contrato (10.2) y se violo igual, porque el contrato solo se inyecta en el
# camino ARMADO y esa sesion nunca armo (se trabajo sin -saikit). Medido en el
# transcript e86ddb2c: 2.6 h bloqueado esperando, ~1.75 h evitables.
#
# Medido antes de disenar (repo descartable, claude -p headless): SessionStart
# en Claude acepta hookSpecificOutput.additionalContext y el texto llega al
# modelo textual. Ver docs/task-10.6-plan.md.
caso_g1_session_inyecta_reglas() {
  lab_run session claude "$(lab_payload_session 'arranca la sesion sin pedir nada especial')"
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" '"hookSpecificOutput"'
  _contiene "stdout" "$LAB_OUT" '"hookEventName":"SessionStart"'
  _contiene "stdout" "$LAB_OUT" 'SUMMONAIKIT STANDING RULES'
  # La fase session NO arma: si creara estado, el Stop gate empezaria a exigir
  # recibo en sesiones que nadie armo — es el defecto A4 en version nueva.
  if lab_hay_estado; then _mal "la fase session NO debe crear estado (el Stop gate se activaria solo)"; fi
}

# Task 9.4 (C9). El fallback `prompt_text="$INPUT"` no estaba acotado: si el
# payload no traia campo `prompt`, el sentinel se buscaba en el PAYLOAD ENTERO y
# un `-saikit` en cualquier otro campo armaba la ceremonia. La forma real es un
# resume, donde el texto viejo viaja en un campo de resumen: nadie pidio nada y
# el gate quedaba exigiendo recibo.
#
# El fallback se conserva SOLO en `session`, donde cursor si arma con el
# sentinel en el texto (medido, caso_g6_armado_por_target).
caso_g1_prompt_sin_campo_no_arma() {
  lab_run prompt claude "$(lab_payload_prompt_sin_campo 'el turno anterior decia -saikit agrega el endpoint')"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then
    _mal "sin campo prompt NO se arma: el sentinel en otro campo del payload no es una peticion"
  fi
}

# LIMITE de la Task 10.6, ATADO por este caso en vez de solo declarado
# (hallazgo Major de CodeRabbit, PR #19).
#
# El payload de SessionStart no trae `prompt` y SI trae `summary`; el summary de
# una sesion reanudada suele CITAR el prompt anterior, que llevaba -saikit. El
# fallback al payload crudo hace que ese texto viejo matchee el sentinel, asi
# que la sesion ARMA: sale el contrato, no las reglas permanentes.
#
# NO se arregla en 10.6 a proposito: el fallback sin acotar es C9 / Task 9.4, y
# su DoD decide EXPLICITAMENTE conservarlo en `session` dejando
# `caso_g6_armado_por_target` intacto. Acotarlo desde aca pisaria el diseno de
# esa tarea y pondria rojo su caso.
#
# Este caso existe para que el limite no se descubra de nuevo por sorpresa: fija
# lo que HOY pasa. Si 9.4 cambia el fallback, este caso se pone rojo y hay que
# venir a decidir si las reglas deben ganar en ese camino.
caso_g1_session_con_sentinel_en_summary_arma_y_no_da_reglas() {
  lab_run session claude "$(lab_payload_session 'resumen del turno anterior: -saikit agrega el endpoint de sesiones')"
  _igual "exit code" "$LAB_RC" "0"
  _no_contiene "las reglas NO salen cuando la sesion arma" "$LAB_OUT" 'SUMMONAIKIT STANDING RULES'
  _contiene "sale el contrato en su lugar" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
}

# El desarme sigue acotado a PHASE=prompt (el mismo acotamiento que ya protegia
# a cursor). Un SessionStart no puede borrar el estado de un turno armado: en
# Claude un /clear dispara SessionStart y se llevaria puesta la ceremonia en
# curso.
caso_g1_session_no_desarma() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit agrega el endpoint de sesiones')"
  if ! lab_hay_estado; then _mal "precondicion: el turno con sentinel tenia que armar"; fi

  lab_run session claude "$(lab_payload_session 'arranca la sesion sin pedir nada especial')"
  _igual "exit code" "$LAB_RC" "0"
  if ! lab_hay_estado; then _mal "un SessionStart sin sentinel NO debe desarmar el turno en curso"; fi
}

# El bug del vendor que el parche del sentinel existe para tapar: "cualquier"
# contiene "ui", asi que su regex de palabras clave armaba el harness solo.
# NOTA (10.6): este caso es TAMBIEN la regresion que atrapa una rama de session
# mal acotada — si la emision de reglas corriera en PHASE=prompt, este stdout
# dejaria de estar vacio. Por eso 10.6 no agrega un caso propio para eso.
caso_g1_no_arma_sin_sentinel() {
  lab_run prompt claude "$(lab_payload_prompt 'arregla cualquier bug del login y corre los tests')"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "sin sentinel NO se debe crear estado (el Stop gate se activaria solo)"; fi
}

caso_g1_arma_con_sentinel() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit agrega el endpoint de sesiones')"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stderr" "$LAB_ERR"
  _contiene "stdout" "$LAB_OUT" '"hookSpecificOutput"'
  _contiene "stdout" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
  _contiene "stdout" "$LAB_OUT" 'SUMMONAIKIT HARNESS RECEIPT'
  if lab_hay_estado; then
    _igual "cycle"       "$(lab_estado cycle)"       "0"
    _igual "implemented" "$(lab_estado implemented)" "0"
    _igual "verified"    "$(lab_estado verified)"    "0"
    _igual "agents_seen" "$(lab_estado agents_seen)" ""
  else
    _mal "con sentinel se debe crear el estado del turno"
  fi
}

# El sentinel pide fronteras a los dos lados. Sin ellas, cualquier archivo o
# flag que lleve el texto adentro armaria el harness.
caso_g1_sentinel_con_frontera() {
  lab_run prompt claude "$(lab_payload_prompt 'nombra el archivo x-saikit.md')"
  _vacio "stdout con frontera izquierda rota" "$LAB_OUT"
  if lab_hay_estado; then _mal "x-saikit no debe armar (frontera izquierda)"; fi

  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'el flag es -saikitx')"
  _vacio "stdout con frontera derecha rota" "$LAB_OUT"
  if lab_hay_estado; then _mal "-saikitx no debe armar (frontera derecha)"; fi

  # Task 9.5 (C10): la frontera izquierda aceptaba `/` y `-`, asi que REFERENCIAR
  # un archivo o un flag que contiene el token armaba la ceremonia entera. Es el
  # mismo dano que x-saikit, por dos caracteres que faltaban en la clase.
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'edita el archivo docs/-saikit.md')"
  _vacio "stdout con / antes del sentinel" "$LAB_OUT"
  if lab_hay_estado; then _mal "docs/-saikit.md no debe armar: es una RUTA, no una peticion"; fi

  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'el flag largo es --saikit')"
  _vacio "stdout con - antes del sentinel" "$LAB_OUT"
  if lab_hay_estado; then _mal "--saikit no debe armar: es un FLAG citado, no una peticion"; fi

  # Controles: lo que SI tiene que seguir armando. Sin estos, apretar la frontera
  # pasaria de tapar un agujero a romper el armado normal — que es el dano de A8.
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt '-saikit arranca al principio del texto')"
  if ! lab_hay_estado; then _mal "control: el sentinel al INICIO del texto tiene que armar"; fi

  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'arranca (-saikit) entre parentesis')"
  if ! lab_hay_estado; then _mal "control: el sentinel tras '(' tiene que armar"; fi

  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt 'hace esto, -saikit, con cuidado')"
  if ! lab_hay_estado; then _mal "control: el sentinel tras ',' tiene que armar"; fi
}

# DEFECTO A4 (clausula 1) — cerrado por la Task 3.4. Antes el estado se llaveaba
# solo por proyecto, asi que dos sesiones del mismo repo compartian un solo
# harness-state.env: un turno -saikit abandonado en una cobraba recibo a la otra.
# Ahora se llavea por proyecto Y sesion (session_id viaja en cada payload).
#
# DOS mitades, como pide la revision (CORRECCION 10): no basta con "B no ve el
# estado de A" — un hook que borrara TODO pasaria esa sola mitad. La otra ata que
# el estado de A sobrevive intacto al turno de B.
# Task 9.7 (C13). `state/` crecia para siempre: cada limpieza borraba los
# ARCHIVOS y dejaba el directorio de la sesion. Una sesion = un dir vacio
# inmortal. Dos mitades, las dos en este caso porque una sin la otra no arregla
# nada: sin (a) el dir del turno actual queda; sin (b) los de las sesiones que
# nunca cerraron limpio quedan igual.
caso_g1_estado_no_se_acumula() {
  # (a) el cierre limpio se lleva el DIRECTORIO, no solo los archivos.
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  dir_turno="$(dirname "$LAB_ESTADO_PATH")"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code del cierre limpio" "$LAB_RC" "0"
  if [ -d "$dir_turno" ]; then
    _mal "un cierre limpio debe llevarse el DIRECTORIO de la sesion, no solo los archivos"
  fi

  # (b) al ARMAR se barren las hermanas muertas del mismo proyecto+host.
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt '-saikit turno que arma y barre')"
  dir_vivo="$(dirname "$LAB_ESTADO_PATH")"
  proyecto_dir="$(dirname "$dir_vivo")"
  _no_vacio "dir de proyecto" "$proyecto_dir"

  mkdir -p "$proyecto_dir/hermana-muerta" "$proyecto_dir/hermana-fresca"
  printf 'cycle=0\n' > "$proyecto_dir/hermana-muerta/harness-state.env"
  printf 'cycle=0\n' > "$proyecto_dir/hermana-fresca/harness-state.env"
  # 15 dias: pasa el TTL de 14. `touch -d` se midio funcionando en MSYS2 antes
  # de disenar esto, asi que no hace falta el TTL-por-env que preveia el plan.
  touch -d '15 days ago' "$proyecto_dir/hermana-muerta/harness-state.env" 2>/dev/null \
    || _mal "no se pudo antedatar la hermana muerta; el barrido no se puede medir"

  lab_run prompt claude "$(lab_payload_prompt '-saikit segundo turno, dispara el barrido')"

  # La muerta se va. La FRESCA sobrevive: barrer por edad sin discriminar seria
  # A4 otra vez, borrandole el estado a una sesion hermana que sigue viva.
  if [ -d "$proyecto_dir/hermana-muerta" ]; then
    _mal "el barrido no se llevo la hermana MUERTA (>14 dias)"
  fi
  if [ ! -d "$proyecto_dir/hermana-fresca" ]; then
    _mal "el barrido se llevo una hermana FRESCA — eso es A4: le borra el estado a una sesion viva"
  fi
  # Y jamas el turno que esta armando.
  if [ ! -f "$LAB_ESTADO_PATH" ]; then
    _mal "el barrido se llevo el estado del turno que lo disparo"
  fi
}

caso_g1_dos_sesiones_no_comparten_estado() {
  # A arma con la sesion por defecto del banco. LAB_ESTADO_PATH queda apuntando a
  # la ruta de A; las aserciones sobre A la leen ahi aunque cambiemos de sesion.
  lab_run prompt claude "$(lab_payload_prompt '-saikit tarea de la sesion A')"
  ruta_A="$LAB_ESTADO_PATH"
  _no_vacio "ruta de estado de A tras armar" "$ruta_A"

  # B es OTRA sesion del mismo repo: le cambio el session_id al payload. El hook
  # deriva otra ruta, no encuentra estado y deja pasar.
  LAB_SESSION_ID="b2b20000-2222-4333-8444-555566667777"
  lab_run stop claude "$(lab_payload_stop 'cierre de la sesion B')"
  # Mitad 1: B no bloquea por el estado de A (no lo ve).
  _igual "Stop de B sin su propio estado — no bloquea por A (A4 c.1)" "$LAB_RC" "0"
  # Mitad 2: el estado de A sobrevive intacto al turno de B.
  [ -f "$ruta_A" ] || _mal "el estado de A se borro al correr un turno de B (A4 c.1, mitad 2)"
  _igual "cycle de A intacto tras el turno de B (A4 c.1, mitad 2)" \
         "$(grep '^cycle=' "$ruta_A" | tail -n 1 | cut -d= -f2-)" "0"
  # Restaurar la sesion por defecto para los casos siguientes.
  LAB_SESSION_ID=""
}

# DEFECTO A4 (clausula 2) — cerrado por la Task 3.4. Antes un prompt sin sentinel
# no tocaba el estado, asi que un turno -saikit abandonado segui cobrando recibo a
# turnos que no lo pidieron. Ahora desarma: borra el estado de ESTA sesion, y el
# Stop siguiente no bloquea. Acotado a PHASE=prompt (un SessionStart sin sentinel
# no toca el estado — cursor arma ahi con -saikit en el texto).
caso_g1_prompt_sin_sentinel_desarma() {
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  lab_run prompt claude "$(lab_payload_prompt 'un prompt sin sentinel a mitad de turno')"
  if lab_hay_estado; then _mal "un prompt sin sentinel debe desarmar (borrar el estado) — A4 c.2"; fi
  lab_run stop claude "$(lab_payload_stop 'cierre sin estar armado')"
  _igual "Stop tras desarme no bloquea (A4 c.2)" "$LAB_RC" "0"
  _vacio "stdout del Stop tras desarme" "$LAB_OUT"
}

# DEFECTO A4 (clausula 3) — correccion al vuelo. Bajo el diseño confirmado
# ("re-armar resetea cycle a 0"), el camino de armado pisa exactamente lo que el
# desarme borraba (STATE_PATH/LOG_PATH/RN_ORDER_PATH), asi que "no desarmar" y
# "desarmar y volver a armar" dejan estado byte a byte identico. Por eso este caso
# es GUARDIA DE REGRESION: hoy da verde con el hook sano Y con uno que desarme
# igual, y ninguna mutacion lo puede atrapar (declarado en docs/task-3.4-plan.md,
# CORRECCION 3, opcion A). El dia que alguien vuelva parcial el camino de armado,
# el caso empieza a discriminar. Se conserva para eso, no como prueba de hoy.
caso_g1_correccion_al_vuelo_no_desarma() {
  lab_sembrar 123456 1 1 1 "implementer,verifier,reviewer"
  lab_run prompt claude "$(lab_payload_prompt '-saikit correccion al vuelo del turno')"
  if ! lab_hay_estado; then _mal "una correccion al vuelo (prompt con -saikit) no desarma — A4 c.3 (guardia)"; fi
}

# DEFECTO A4 (costado de la CORRECCION 2 del plan) — session_id anidado. El
# payload de Stop puede traer session_crons con su PROPIO session_id (depth>1).
# json_top_level_string lo ignora (exige depth==1); el lector greedy
# json_string_field tomaba la ULTIMA ocurrencia y re-llaveaba la ruta a mitad de
# turno: el Stop buscaba estado en la ruta del intruso, no lo encontraba y dejaba
# pasar. Gemelo de caso_g3_eco_fuera_de_tool_input_no_cuenta para session_id.
# Hallazgo [media] de la cross-review codex sobre la 3.4.
caso_g1_session_id_anidado_no_reescribe_ruta() {
  lab_sembrar 123456 0 0 0 ""   # estado armado e incompleto (missing) bajo ESTA sesion
  lab_run stop claude "$(lab_payload_stop_con_cron_intruso 'cierre con cron intruso')"
  _igual "Stop con session_id anidado sigue viendo el estado de ESTA sesion (A4/C2)" "$LAB_RC" "2"
}

# DEFECTO A4-cross-host (Task 5.3) — el caso que lo habria atrapado. A4 llaveo
# por sesion; 5.3 SUMA host. Si el harness se registra desde zcode apuntando al
# MISMO $0 que Claude (~/.claude/hooks/…), STATE_ROOT (dirname $0) es identico y
# dos turnos sobre el MISMO repo con la MISMA sesion escribian el mismo
# harness-state.env: un cierre de zcode podia pisar el turno de Claude. La
# senal de host es el env (medido Task 5.1): CLAUDECODE=1 (Claude/glm) o
# ZCODE_SESSION_ID/ZCODE_PROJECT_DIR (zcode); ZCODE_* gana.
#
# DOS mitades como pide A4 (no basta "B no ve A" — un hook que borrara todo
# pasaria esa sola mitad) MAS un tercio de RN: el aviso pendiente vive en
# PROJECT_DIR, asi que si HOST no aísla PROJECT_DIR, rn_take_pending de B se
# come el aviso de A (defecto 2 del plan).
caso_g1_dos_hosts_mismo_repo_no_comparten_estado() {
  # Mismo $0 (el lab copia un solo hook), mismo PROJECT_ROOT, MISMO session_id
  # (LAB_SESSION_ID default para los dos). La unica diferencia es la senal de
  # host. Lab_SESSION_ID arranca limpio por si un caso anterior lo dejo sucio.
  LAB_SESSION_ID=""

  # --- Lado A: Claude (CLAUDECODE=1, sin ZCODE_*) ---
  LAB_CLAUDECODE=1
  lab_run prompt claude "$(lab_payload_prompt '-saikit tarea del host Claude')"
  LAB_CLAUDECODE=""
  # Redescubrir (hallazgo r2.3): LAB_ESTADO_PATH lo descubrio lab_init SIN
  # senal de host => apunta a state/other/… . A armo bajo claude/; no asumir la
  # profundidad, buscar. Contra el hook SIN arreglar no hay segmento claude/ y
  # el estado queda directo en state/<key>/<session>/.
  ruta_A="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  _no_vacio "ruta de estado de A tras armar" "$ruta_A"
  _igual "cycle de A recien armado" "$(grep '^cycle=' "$ruta_A" | tail -n 1 | cut -d= -f2-)" "0"

  # Sembrar el aviso RN pendiente en el PROJECT_DIR de A. La ruta del estado es
  # PROJECT_DIR/SESSION_KEY/harness-state.env siempre (2 niveles), asi que
  # dirname dos veces da PROJECT_DIR cualquiera sea el esquema de host.
  rn_pending_A="$(dirname "$(dirname "$ruta_A")")/review-notice-pending.log"
  printf 'SAIKIT REVIEW NOTICE: aviso pendiente sembrado del lado Claude.\n' > "$rn_pending_A"

  # --- Lado B: zcode (LAB_ZCODE_SESSION_ID, sin CLAUDECODE) ---
  # B ARMA (no un Stop sin estado): el armado es lo que corre rn_take_pending
  # (hallazgo r1.2 — un Stop sin estado propio sale por emit_allow y no toca RN).
  LAB_ZCODE_SESSION_ID="sess_zcode_host_b"
  lab_run prompt claude "$(lab_payload_prompt '-saikit tarea del host zcode')"
  LAB_ZCODE_SESSION_ID=""
  ruta_B="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | sort | tail -n 1)"
  _no_vacio "ruta de estado de B tras armar" "$ruta_B"

  # Mitad 1: B no ve el estado de A — rutas distintas. Sin el arreglo A y B
  # colapsan al mismo path (mismo $0 + misma sesion + STATE_ROOT identico).
  if [ "$ruta_A" = "$ruta_B" ]; then
    _mal "A (claude) y B (zcode) comparten harness-state.env — A4 cross-host (Task 5.3)"
  fi
  # Mitad 2: el estado de A sobrevive intacto al armado de B.
  [ -f "$ruta_A" ] || _mal "el estado de A se perdio al armar B (A4 cross-host, mitad 2)"
  _igual "cycle de A intacto tras el armado de B" \
         "$(grep '^cycle=' "$ruta_A" 2>/dev/null | tail -n 1 | cut -d= -f2-)" "0"
  # Mitad 3 (RN): el aviso pendiente de A sigue — rn_take_pending de B mira su
  # PROPIO PROJECT_DIR. Si HOST no aísla PROJECT_DIR, B se come el aviso de A.
  [ -f "$rn_pending_A" ] \
    || _mal "el aviso RN de A fue tomado/borrado por B — HOST no aísla PROJECT_DIR (defecto 2)"

  # Restaurar (hallazgo r2.2): correr_caso no restaura LAB_CLAUDECODE /
  # LAB_ZCODE_*. Sin esto, los G1 siguientes heredan ZCODE_SESSION_ID y buscan
  # estado bajo zcode/.
  LAB_CLAUDECODE=""; LAB_ZCODE_SESSION_ID=""; LAB_ZCODE_PROJECT_DIR=""
  LAB_SESSION_ID=""
}

# Control de DETECCION de host (Task 5.3, A3). No es el catch (no tiene mutacion
# propia): afirma que el segmento de host sale de la senal correcta. Sin el
# control de ZCODE_PROJECT_DIR-only (hallazgo 5), una implementacion que leyera
# solo ZCODE_SESSION_ID pasaria la bateria entera. Va DESPUES del catch en
# CASOS_G1: asi mut_host_sin_llave se acredita al catch (corre antes) y este
# caso aporta cobertura sin robar la declaracion.
caso_g1_host_segun_senal() {
  _senal_espera_host() {
    _senial="$1"; _esperado="$2"
    lab_limpiar_estado
    case "$_senial" in
      claude)        LAB_CLAUDECODE=1 ;;
      zcode-sid)     LAB_ZCODE_SESSION_ID="sess_ctrl_zcode" ;;
      zcode-pdir)    LAB_ZCODE_PROJECT_DIR="/c/dummy/proyecto-zcode" ;;
      ninguna)       : ;;
    esac
    lab_run prompt claude "$(lab_payload_prompt '-saikit detectar host')"
    LAB_CLAUDECODE=""; LAB_ZCODE_SESSION_ID=""; LAB_ZCODE_PROJECT_DIR=""
    _ruta="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
    _no_vacio "ruta de estado con senal=$_senial" "$_ruta"
    case "$_ruta" in
      *"/$_esperado/"*) : ;;
      *) _mal "con senal=$_senial esperaba segmento /$_esperado/, dio: $_ruta" ;;
    esac
  }
  _senal_espera_host claude    claude   # CLAUDECODE=1 => claude (regresion A10)
  _senal_espera_host zcode-sid zcode    # solo ZCODE_SESSION_ID => zcode
  _senal_espera_host zcode-pdir zcode   # solo ZCODE_PROJECT_DIR => zcode (hallazgo 5)
  _senal_espera_host ninguna   other    # sin senal => other, NUNCA claude
}

# Task 6.4 (D2) — el caso que ata HOST=codex, espejo del cross-host zcode de
# arriba. El escenario REAL que la rama previene (medido 6.1): el operador
# corre Codex DESDE ADENTRO de Claude (codex-rescue, cross-review.ps1) y el
# hook de Codex hereda CLAUDECODE=1 del proceso padre — sin la senal explicita
# PRIMERO en el orden, el lado codex resuelve HOST=claude y ambos turnos
# comparten estado. Lado B lleva LAS DOS senales a proposito: la explicita
# (SUMMONAIKIT_HOOK_TARGET=codex, la unica que en Codex llega de verdad —
# 6.1) tiene que GANARLE a la heredada.
caso_g1_dos_hosts_codex_y_claude_no_comparten_estado() {
  LAB_SESSION_ID=""

  # --- Lado A: Claude (CLAUDECODE=1, sin TARGET explicito) ---
  LAB_CLAUDECODE=1
  lab_run prompt claude "$(lab_payload_prompt '-saikit tarea del host Claude')"
  LAB_CLAUDECODE=""
  ruta_A="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  _no_vacio "ruta de estado de A tras armar" "$ruta_A"
  _igual "cycle de A recien armado" "$(grep '^cycle=' "$ruta_A" | tail -n 1 | cut -d= -f2-)" "0"

  # --- Lado B: Codex lanzado desde adentro de Claude (CLAUDECODE=1 heredado
  # + TARGET=codex explicito; lab_run exporta SUMMONAIKIT_HOOK_TARGET) ---
  LAB_CLAUDECODE=1
  lab_run prompt codex "$(lab_payload_prompt '-saikit tarea del host Codex')"
  LAB_CLAUDECODE=""
  ruta_B="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep '/codex/' | head -n 1)"
  _no_vacio "estado de B bajo state/codex/ (la senal explicita gana a CLAUDECODE)" "$ruta_B"

  # Mitad 1: rutas distintas — sin la rama, B colapsa al path de A.
  if [ -n "$ruta_B" ] && [ "$ruta_A" = "$ruta_B" ]; then
    _mal "A (claude) y B (codex) comparten harness-state.env — D2 sin rama (Task 6.4)"
  fi
  # Mitad 2: el estado de A sobrevive intacto al armado de B.
  [ -f "$ruta_A" ] || _mal "el estado de A se perdio al armar B (Task 6.4, mitad 2)"
  _igual "cycle de A intacto tras el armado de B" \
         "$(grep '^cycle=' "$ruta_A" 2>/dev/null | tail -n 1 | cut -d= -f2-)" "0"

  LAB_CLAUDECODE=""; LAB_SESSION_ID=""
}

# Control de allowlist (Task 6.4, sin mutacion propia — el catch es el caso de
# arriba): SOLO el literal `codex` mapea a HOST=codex; cualquier otro valor de
# SUMMONAIKIT_HOOK_TARGET cae por las senales de abajo hasta other (Core Rule
# 2: un valor que no reconozco no es evidencia de nada). Y codex va PRIMERO:
# le gana incluso a la senal de zcode (7.3 insertara grok encima, orden final
# grok > codex > zcode > claude > other).
caso_g1_host_codex_solo_literal() {
  _target_espera_host() {
    _t="$1"; _esperado="$2"
    lab_limpiar_estado
    lab_run prompt "$_t" "$(lab_payload_prompt '-saikit detectar host por target')"
    LAB_CLAUDECODE=""; LAB_ZCODE_SESSION_ID=""
    _ruta="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
    _no_vacio "ruta de estado con target=$_t" "$_ruta"
    case "$_ruta" in
      *"/$_esperado/"*) : ;;
      *) _mal "con target=$_t esperaba segmento /$_esperado/, dio: $_ruta" ;;
    esac
  }
  _target_espera_host codex codex        # el literal acredita
  _target_espera_host codexx other       # valor no reconocido: NUNCA codex, y sin otra senal => other
  LAB_CLAUDECODE=1
  _target_espera_host codexy claude      # no reconocido + CLAUDECODE=1 => cae al fallback claude
  LAB_ZCODE_SESSION_ID="sess_zcode_ctrl"
  _target_espera_host codex codex        # codex le GANA a la senal zcode presente
  lab_limpiar_estado
}


# C1 (auditoria 2026-08-13, Task 8.1) — json_string_field cortaba el valor del
# prompt en la primera comilla escapada: `arregla el "bug" -saikit` llegaba
# truncado a `arregla el \` y el sentinel jamas se veia. Comillas en un prompt
# son entrada de todos los dias (mensajes de error, nombres de campo, salida
# pegada). Rojo medido contra el hook pre-8.1.
caso_g1_arma_con_comillas_antes_del_sentinel() {
  lab_run prompt claude "$(lab_payload_prompt 'arregla el \"bug\" del login -saikit')"
  _contiene "stdout con comillas antes del sentinel" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
  if ! lab_hay_estado; then _mal "un prompt con comillas antes de -saikit debe armar (C1)"; fi
}

# C1, mitad desarme — la correccion a mitad de ceremonia CON sentinel pero con
# una comilla antes tomaba la rama de desarme (el sentinel quedaba del otro
# lado del corte) y borraba el estado armado en silencio.
caso_g1_correccion_con_comillas_no_desarma() {
  lab_sembrar 123456 1 1 1 "implementer,verifier,reviewer"
  lab_run prompt claude "$(lab_payload_prompt 'ojo, el campo es \"user_id\" no user -saikit')"
  if ! lab_hay_estado; then _mal "una correccion con comillas y -saikit no debe desarmar (C1)"; fi
}

# C2 (auditoria 2026-08-13, Task 8.1) — el sentinel se grepeaba sobre el JSON
# crudo sin decodificar: un salto de linea antes de -saikit llega como los DOS
# caracteres literales \n, la `n` es alfanumerica y la frontera izquierda
# rechaza. El sentinel en su propia linea es la colocacion mas natural de un
# prompt multilinea.
caso_g1_arma_con_sentinel_en_linea_nueva() {
  lab_run prompt claude "$(lab_payload_prompt 'arregla el bug del parser\n-saikit')"
  _contiene "stdout con sentinel en linea nueva" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
  if ! lab_hay_estado; then _mal "un prompt multilinea con -saikit en su propia linea debe armar (C2)"; fi
}

# ================================================= Task 10.1 — carril -saikit:fast
# El carril NO se infiere de regex de trivialidad: el usuario lo pide explicito
# (-saikit:fast). OJO (cross-review codex r1, hallazgo 4): -saikit:fast YA ARMA
# con el sentinel de siempre (el `:` pasa la frontera derecha) — el ROJO de los
# dos primeros casos es por el CAMPO lane ausente del estado (lab_estado lane da
# vacio != fast/full), no por no armar. El RE del sentinel no cambia; lo nuevo
# es la DETECCION del carril. Con lane=fast el Stop gate exige recibo completo +
# evidencia de verificacion (o skip) pero NO la ceremonia de 3 subagentes;
# -saikit pelado = ceremonia completa, sin cambios.
caso_g1_fast_arma_con_lane() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo del header')"
  _igual "lane" "$(lab_estado lane)" "fast"
}

caso_g1_pelado_arma_lane_full() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit agrega el endpoint')"
  _igual "lane" "$(lab_estado lane)" "full"
}

# r1 hallazgo 4: el match del sufijo es EXACTO (:fast con frontera derecha).
# Cualquier otro sufijo (-saikit:fasst, -saikit:rapido) arma FULL — limite
# declarado: un typo del carril cae al lado seguro (ceremonia completa), nunca
# a un fast silencioso. Se ATA con este caso propio.
caso_g1_sufijo_desconocido_arma_full() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fasst corrige el typo')"
  _igual "lane con sufijo desconocido" "$(lab_estado lane)" "full"
  if ! lab_hay_estado; then _mal "sufijo desconocido arma igual (full), no silencio"; fi
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt '-saikit:rapido corrige el typo')"
  _igual "lane con sufijo :rapido" "$(lab_estado lane)" "full"
}

# ============================================ G2 — evidencia de verificacion
CASOS_G2="caso_g2_runner_marca_verificado caso_g2_sin_runner_no_marca caso_g2_runner_no_encontrado_no_marca caso_g2_runner_fallido_forma_real caso_g2_runner_fallido_pytest_summary_no_marca caso_g2_runner_fallido_tsc_no_marca caso_g2_runner_fallido_phpunit_no_marca caso_g2_runner_fallido_cargo_no_marca caso_g2_runner_fallido_go_no_marca caso_g2_runner_pasa_0_failed_sigue_acreditado caso_g2_runner_pasa_typeerror_en_comando_sigue_acreditado caso_g2_sin_armar_no_crea_estado caso_g2_falta_evidencia_reclama caso_g2_evidencia_presente_no_reclama caso_g2_excusa_declarada_no_reclama caso_g2_excusa_espanol_no_reclama caso_g2_runner_en_path_no_marca caso_g2_runner_con_ruta_marca caso_g2_excusa_con_punto_final_no_reclama caso_g2_credenciales_en_comando_se_redactan caso_g2_comando_sin_credenciales_no_se_altera caso_g2_credenciales_en_ruta_de_edicion_se_redactan caso_g2_credencial_entrecomillada_se_redacta_entera caso_g2_comando_entrecomillado_marca_verificado caso_g2_eco_de_command_en_tool_response_no_marca caso_g2_eco_de_tool_name_en_tool_response_no_marca caso_g2_runner_bash_run_sh_marca caso_g2_runner_bash_ruta_absoluta_marca caso_g2_runner_bash_tras_and_marca caso_g2_runner_run_sh_directo_marca caso_g2_runner_run_sh_en_cat_no_marca caso_g2_runner_run_sh_en_grep_no_marca caso_g2_runner_bash_con_args_marca caso_g2_runner_zsh_marca caso_g2_runner_decoy_contest_no_marca caso_g2_runner_decoy_typo_no_marca caso_g2_runner_decoy_grep_bash_no_marca caso_g2_runner_decoy_printf_no_marca caso_g2_runner_decoy_echo_no_marca caso_g2_runner_fallido_dotnet_no_marca caso_g2_runner_fallido_gradle_no_marca caso_g2_dotnet_exitoso_sigue_acreditado caso_g2_runner_en_echo_no_marca caso_g2_echo_seguido_de_runner_no_acredita caso_g2_runner_con_and_y_var_sigue_acreditando caso_g2_tool_name_runner_con_comando_ajeno_no_marca caso_g2_grok_write_marca_implemented caso_g2_grok_runner_marca_verificado caso_g2_grok_runner_fallido_no_marca caso_g2_grok_nomatchesfound_no_marca caso_g2_grok_edit_marca_implemented caso_g2_grok_precedencia_toolinput_gana_snake caso_g2_grok_precedencia_toolname_gana_snake"

# C1, tercio de evidencia (auditoria 2026-08-13, Task 8.1) — un runner
# entrecomillado dentro de bash -c perdia el credito: json_string_field cortaba
# command en la primera \" y el regex jamas veia pytest. El Stop de ese turno
# reclamaba evidencia que SI existia (ciclo de revision de mas).
caso_g2_comando_entrecomillado_marca_verificado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash -c \"cd app && pytest -q\"')"
  _igual "verified con runner entrecomillado" "$(lab_estado verified)" "1"
}

# C3 (auditoria 2026-08-13, Task 8.1) — clase A1 para command: una clave
# "command" DENTRO de tool_response (texto que el turno no escribio) era tomada
# por el lector greedy (ultima ocurrencia gana) y acreditaba verified=1 por un
# comando que nunca corrio. Gemelo de caso_g3_eco_fuera_de_tool_input_no_cuenta.
caso_g2_eco_de_command_en_tool_response_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_con_eco_command 'echo hola' 'pytest -q')"
  _igual "verified tras eco de command en tool_response" "$(lab_estado verified)" "0"
}

# C3, gemelo para tool_name — el eco {"tool_name":"pytest"} dentro de
# tool_response pisaba la herramienta real del evento con el lector greedy y
# el chequeo del runner acreditaba sin comando de test alguno.
caso_g2_eco_de_tool_name_en_tool_response_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  # El comando NO puede empezar con echo: desde 9.2 ECHO_LEAD_RE lo bloquea por
  # su cuenta y enmascararia la mutacion (el caso quedaria verde por el motivo
  # equivocado). Se usa un comando que no es runner ni lleva echo adelante.
  lab_run tool claude "$(lab_payload_bash_con_eco_tool_name 'ls -la' 'pytest')"
  _igual "verified tras eco de tool_name en tool_response" "$(lab_estado verified)" "0"
}

caso_g2_runner_marca_verificado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  _igual "verified" "$(lab_estado verified)" "1"
}

caso_g2_sin_runner_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cat README.md')"
  _igual "verified" "$(lab_estado verified)" "0"
}

# La evidencia se acredita por el COMANDO, y un comando que ni existe no cuenta.
# Esta es la UNICA mitad del guardia de fallas que sigue viva contra payloads
# reales: la otra mitad busca `exitCode`, un campo que el tool_response real de
# Bash no trae (ver el caso de abajo).
caso_g2_runner_no_encontrado_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest -q' 'bash: pytest: command not found')"
  _igual "verified" "$(lab_estado verified)" "0"
}

# A11 INVERTIDO por la Task 3.8. Antes este caso afirmaba `verified=1` (defecto):
# el guardia de fallas buscaba `exitCode[^0-9]*[1-9]`, un campo que el
# tool_response real de Bash NO trae (medido 59/59 en la Task 1.4). Una bateria
# que fallaba con un assert normal no decia ninguna de las 3 senales textuales
# que quedaban (`command not found` / `permission_denied` / `failure_type`) y el
# gate la acreditaba igual. Ahora el hook grepea patrones reales de fracaso
# (`AssertionError` entre ellos) y el caso afirma `verified=0`.
caso_g2_runner_fallido_forma_real() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'npm test' 'AssertionError: expected true to equal false')"
  _igual "A11 cerrado: runner que revento por asercion NO acredita" "$(lab_estado verified)" "0"
}

# Cada uno de los 5 casos siguientes aisla UNA rama del FAILURE_SIGNAL_RE_CI / _CS
# (definidos en el hook por la Task 3.8). La mutacion correspondiente
# (mut_falla_*_quitada) neutraliza esa rama y hace que el caso vuelva al defecto
# (verified=1) -- si eso pasara, el caso da rojo. El sexto caso es NEGATIVO:
# protege la frontera [1-9] del regex CI para que una mutacion que la afloje a
# [0-9] (matcheando `0 failed`) se detecte.
#
# Los fixtures de phpunit y cargo se recortan a SOLO la senal de la rama que
# aislan (vía B / CS), sin la señal `N failed` que tambien apareceria en
# produccion: si trajeran ambas, la mutacion de su rama no aislaria el caso (la
# otra rama seguiria matcheando) y la bateria de mutaciones no acreditaria. Es
# el compromiso que pide la regla "una mutacion por caso propio".

caso_g2_runner_fallido_pytest_summary_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest -q' '=== 1 failed in 0.5s ===')"
  _igual "pytest summary con 1 failed no acredita (vía A)" "$(lab_estado verified)" "0"
}

caso_g2_runner_fallido_tsc_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'tsc --noEmit' 'src/x.ts(3,1): error TS2322: Type string is not assignable to type number.')"
  _igual "tsc con error TS2322 no acredita" "$(lab_estado verified)" "0"
}

caso_g2_runner_fallido_phpunit_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'phpunit tests/' 'Failures: 1, Errors: 0.')"
  _igual "phpunit con Failures: 1 no acredita (vía B)" "$(lab_estado verified)" "0"
}

caso_g2_runner_fallido_cargo_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cargo test' 'test result: FAILED.')"
  _igual "cargo con test result: FAILED no acredita (CS)" "$(lab_estado verified)" "0"
}

# Task 9.1 (C6). Los banners de dotnet y gradle NO matcheaban ninguna via del
# guardia de fallas, asi que un runner que REVENTO acreditaba verificacion:
#   - dotnet dice `Failed:     1` — la via B pedia (failures?|errors?), sin
#     `failed`, y la via A pide el digito ANTES de la palabra;
#   - gradle dice `FAILURE: Build failed` / `BUILD FAILED` — el `FAIL[^a-zA-Z]`
#     del CS exige un NO-letra despues, y ahi siguen `U` y `E`.
caso_g2_runner_fallido_dotnet_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'dotnet test' 'Failed!  - Failed:     1, Passed:    12, Skipped:     0, Total:    13')"
  _igual "dotnet con Failed: 1 no acredita" "$(lab_estado verified)" "0"
}

caso_g2_runner_fallido_gradle_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'gradle test' 'FAILURE: Build failed with an exception.')"
  _igual "gradle con FAILURE: Build failed no acredita" "$(lab_estado verified)" "0"

  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'gradle test' 'BUILD FAILED in 3s')"
  _igual "gradle con BUILD FAILED no acredita" "$(lab_estado verified)" "0"
}

# Control negativo de 9.1: dotnet EXITOSO sigue acreditando. Es lo que protege
# la frontera [1-9] al agregar `failed` a la via B — sin el, `Failed:     0` de
# una corrida verde pasaria a contarse como fracaso y el gate exigiria de mas.
caso_g2_dotnet_exitoso_sigue_acreditado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'dotnet test' 'Passed!  - Failed:     0, Passed:    13, Skipped:     0, Total:    13')"
  _igual "dotnet exitoso con Failed: 0 sigue acreditando" "$(lab_estado verified)" "1"
}

# Task 9.2 (C8), mitad que faltaba. TEST_RUNNER_CMD_RE (llegada en el PR #20) ya
# exige POSICION de comando, pero `echo` es un comando: `echo pytest` pone al
# runner en posicion legitima y acreditaba verificacion sin correr nada.
# ECHO_LEAD_RE lo tapa: si el PRIMER token es echo/printf, ese comando jamas
# acredita.
caso_g2_runner_en_echo_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'echo pytest' 'pytest')"
  _igual "un runner mencionado por echo no acredita" "$(lab_estado verified)" "0"

  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'printf "%s" "pytest -q"' 'pytest -q')"
  _igual "un runner mencionado por printf no acredita" "$(lab_estado verified)" "0"
}

# LIMITE del lado estricto, ATADO por test (r1 del plan): si el primer token es
# echo, el comando NO acredita aunque despues del && haya un runner de verdad.
# Es a proposito: distinguirlo exigiria parsear el shell, y el gate es advisory.
# Si algun dia se afloja, este caso se pone rojo y obliga a decidirlo.
caso_g2_echo_seguido_de_runner_no_acredita() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'echo empiezo && pytest -q' '5 passed')"
  _igual "limite declarado: con echo adelante no acredita ni con runner despues" "$(lab_estado verified)" "0"
}

# Controles verdes: el lado estricto no puede comerse los casos legitimos.
caso_g2_runner_con_and_y_var_sigue_acreditando() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest -q && echo listo' '5 passed')"
  _igual "runner primero y echo despues SI acredita" "$(lab_estado verified)" "1"

  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'CI=1 pytest -q' '5 passed')"
  _igual "prefijo VAR=val sigue acreditando" "$(lab_estado verified)" "1"
}

# CodeRabbit PR #22 (Major). El credito miraba `$tool_name $command_text` con el
# regex laxo, asi que una tool LLAMADA como un runner —posible con un servidor
# MCP— acreditaba verificacion con un comando que no corre nada. ECHO_LEAD_RE no
# lo tapa: el comando no empieza con echo.
caso_g2_tool_name_runner_con_comando_ajeno_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  # El tool_name REAL va en pytest; el comando no corre nada y no empieza con
  # echo, asi que ECHO_LEAD_RE no puede tapar el agujero por casualidad.
  lab_run tool claude "$(lab_payload_tool_name_arbitrario 'pytest' 'ls -la')"
  _igual "una tool llamada como un runner no acredita si el comando no lo corre" "$(lab_estado verified)" "0"
}

caso_g2_runner_fallido_go_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'go test ./...' 'FAIL\texample.com/pkg\t0.12s')"
  _igual "go con FAIL al inicio de linea no acredita (CS)" "$(lab_estado verified)" "0"
}

# Negativo: un runner que PASA con `0 failed` en el log sigue acreditando. Protege
# la frontera [1-9] del regex CI: una mutacion que la afloje a [0-9] haria que
# `0 failed` matchee y este caso daria rojo.
caso_g2_runner_pasa_0_failed_sigue_acreditado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest -q' '=== 5 passed, 0 failed in 0.5s ===')"
  _igual "runner que pasa con 0 failed sigue acreditando" "$(lab_estado verified)" "1"
}

# Negativo H2 (cross-review del codigo, codex 2026-08-12): un runner que PASA cuyo
# COMANDO menciona el nombre de una excepcion (`pytest tests/test_typeerror.py`)
# sigue acreditando. Sin el fix, el regex CI case-insensitive matcheaba `TypeError`
# dentro del nombre del archivo (combined incluye command_text) y el runner exitoso
# dejaba de acreditar -- falso positivo. Tras exigir `:` despues del nombre de la
# excepcion, los tracebacks reales (`TypeError: ...`) siguen matcheando pero los
# nombres de archivo (`test_typeerror.py`) no.
caso_g2_runner_pasa_typeerror_en_comando_sigue_acreditado() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest tests/test_typeerror.py')"
  _igual "runner que pasa con TypeError en el nombre del test sigue acreditando (H2)" "$(lab_estado verified)" "1"
}

# Sin turno armado NO se crea estado: si se creara con task_hash=unknown, el
# Stop gate se activaria solo en cualquier edicion y el sentinel no serviria.
caso_g2_sin_armar_no_crea_estado() {
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un evento de herramienta sin turno armado no debe crear estado"; fi
}

# Los tres casos que siguen usan un recibo al que le falta la linea Retro: el
# turno se bloquea igual, y eso permite LEER el motivo y afirmar sobre la linea
# de verificacion, que es lo que este gate decide.
caso_g2_falta_evidencia_reclama() {
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}

caso_g2_evidencia_presente_no_reclama() {
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}

caso_g2_excusa_declarada_no_reclama() {
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO_SALTEADO")"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}

# Catch del vivo zcode: prosa espanola de skip, sin "skipped"/"not run".
caso_g2_excusa_espanol_no_reclama() {
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO_NO_CORRI")"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}

# DEFECTO A3, el caso que lo habria atrapado. `cat pytest.log` matchea el
# fragmento `pytest` y marca verified=1; `cat tsconfig.json` matchea `tsc`.
# Ninguno corrio nada. Con el wrapper de fronteras, el `.` despues del runner lo
# excluye (es una extension de archivo, no un separador).
caso_g2_runner_en_path_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cat pytest.log')"
  _igual "exit code" "$LAB_RC" "0"
  _igual "verified con cat pytest.log (A3)" "$(lab_estado verified)" "0"
  lab_run tool claude "$(lab_payload_bash 'cat tsconfig.json')"
  _igual "verified con cat tsconfig.json (A3)" "$(lab_estado verified)" "0"
  # Hallazgo de la revision cruzada (codex, 2026-08-11): la rama del punto-de-frase
  # original aceptaba pytest._cache, pytest.-old, pytest..bak porque esos chars no
  # son alfanumericos. Pero SI son validos en nombres de archivo — reabrian A3.
  lab_run tool claude "$(lab_payload_bash 'cat pytest._cache')"
  _igual "verified con cat pytest._cache (A3 bis)" "$(lab_estado verified)" "0"
  lab_run tool claude "$(lab_payload_bash 'cat pytest.-old')"
  _igual "verified con cat pytest.-old (A3 bis)" "$(lab_estado verified)" "0"
}

# La via legitima que el wrapper NO debe romper: el runner invocado por ruta
# (`./node_modules/.bin/vitest run`). Los `.` y `/` del path no son problema
# porque `vitest` esta flanqueado por `/` (izq) y espacio (der). La DoD del
# renglon nombra este caso explicitamente.
caso_g2_runner_con_ruta_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash './node_modules/.bin/vitest run')"
  _igual "verified con el runner invocado por ruta" "$(lab_estado verified)" "1"
}

# CORRECCION 2 del plan de la 3.3: el wrapper se aplica a DOS superficies — el
# comando (:729) y la PROSA del asistente (:870, texto decodificado desde la
# 3.2). Un punto al final de una oracion (`Verify: se corrio pytest.`) NO es una
# extension de archivo. Sin la alternativa `\.([^A-Za-z0-9]|$)` en el lado
# derecho, el gate reclamaria evidencia que esta presente — el mismo daño que
# A8 acaba de cerrar. Este caso lo separa del wrapper simple.
caso_g2_excusa_con_punto_final_no_reclama() {
  lab_sembrar 123456 0 1 0 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO_PYTEST_PUNTO")"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verification evidence'
}

# DEFECTO A5, el caso que lo habria atrapado. Un comando de test runner que
# ademas lleva credenciales en la linea (token=, password=, ://user:pass@) se
# persistia crudo en harness-evidence.log hasta el cierre limpio -- y si el
# turno no cierra, indefinidamente. El arreglo redacta las tres formas en
# mark_evidence (el unico punto que escribe al log), preservando el resto del
# comando, incluido el nombre del runner.
caso_g2_credenciales_en_comando_se_redactan() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'pytest --db-url postgresql://admin:s3cret@host/db --api-token=sk-12345 --db-password=p4ss')"
  _igual "verified (el runner pytest sigue contando)" "$(lab_estado verified)" "1"
  _no_contiene "secreto URL user:pass@ no en log" "$(lab_log)" 'admin:s3cret'
  _no_contiene "secreto token= no en log" "$(lab_log)" 'sk-12345'
  _no_contiene "secreto password= no en log" "$(lab_log)" 'p4ss'
  _contiene "runner preservado en log (utilidad diagnostica)" "$(lab_log)" 'pytest'
  _contiene "marcador REDACTED presente en log" "$(lab_log)" '[REDACTED]'
}

# La redaccion es transparente para comandos sin credenciales: el log los
# conserva tal cual. Sin este caso, un redact_secrets que vaciara todo pasaria
# la primera asercion (el runner sigue presente) y romperia el log en silencio.
# Incluye los guardias de las CORRECCIONES 6 y 12: una @ despues del path, o un
# ?owner=a@, NO son credenciales y no deben disparar la redaccion de URL.
caso_g2_comando_sin_credenciales_no_se_altera() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'python -m pytest -q')"
  _contiene "comando sin credenciales, intacto en log" "$(lab_log)" 'python -m pytest -q'
  _no_contiene "sin marcador REDACTED cuando no hay credenciales" "$(lab_log)" '[REDACTED]'
  lab_run tool claude "$(lab_payload_bash 'pytest --report https://ci.example.com/runs/owner@corp.com/log')"
  _contiene "host y path intactos (CORR 6)" "$(lab_log)" 'https://ci.example.com/runs/owner@corp.com/log'
  lab_run tool claude "$(lab_payload_bash 'pytest --report https://host?owner=a@corp.com')"
  _contiene "host intacto con query (CORR 12)" "$(lab_log)" 'https://host?owner=a@corp.com'
}

# La redaccion vive en mark_evidence, no en el call site de la verificacion: el
# OTRO caller (`:811`, la evidencia de implementacion) tiene que quedar cubierto
# por el mismo punto. Sin este caso, mover la redaccion al call site de :835
# dejaria :811 filtrando y la suite no se enteraria.
caso_g2_credenciales_en_ruta_de_edicion_se_redactan() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_edit 'smb://admin:s3cret@share/src/x.ts')"
  _igual "implemented (la edicion sigue contando)" "$(lab_estado implemented)" "1"
  _no_contiene "secreto de la ruta no en log" "$(lab_log)" 'admin:s3cret'
  _contiene "ruta preservada salvo credenciales" "$(lab_log)" '@share/src/x.ts'
}

# La cola de un valor entrecomillado tambien es el secreto. Sin la alternativa
# de comillas en redact_secrets, `password='hunter dos-palabras'` deja
# `dos-palabras'` en el log (medido). Hallazgo de la revision cruzada con codex.
# La cola se elige DISTINTIVA a proposito: un needle corto como `two` es
# subcadena de palabras comunes (`network`) y daria rojo falso.
caso_g2_credencial_entrecomillada_se_redacta_entera() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash "pytest --db-password='hunter dos-palabras' -q")"
  _igual "verified (el runner sigue contando)" "$(lab_estado verified)" "1"
  _no_contiene "la cola del secreto no queda en el log" "$(lab_log)" 'dos-palabras'
  _contiene "runner preservado" "$(lab_log)" 'pytest'
}

# ============================================= Task 9.10 — runner bash propio
# `bash tests/run.sh` es el gate FINAL de ESTE repo (~18 min de MSYS2) y no
# matcheaba NINGUNA rama de TEST_RUNNER_RE: en hosts sin transcript legible el
# gate de verificacion quedaba insatisfible — el comando CORRECTO no acreditaba
# y el gate exigia una bateria que ya se habia corrido. Se extiende la
# constante compartida (misma superficie para el evento y la prosa del recibo)
# con DOS ramas: verbo shell + ruta sin espacios, e invocacion directa anclada
# a inicio de comando. Sin reabrir A3: `cat tests/run.sh` y
# `grep run.sh tests/run.sh` siguen sin contar (el wrapper de fronteras y la
# clase de exclusion [^A-Za-z0-9_.-] hacen el trabajo: el `sh` dentro de
# `run.sh` queda precedido por `.` y no puede iniciar el match).
caso_g2_runner_bash_run_sh_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash tests/run.sh')"
  _igual "verified con bash tests/run.sh" "$(lab_estado verified)" "1"
}

caso_g2_runner_bash_ruta_absoluta_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash /c/dev/proyecto/tests/run.sh')"
  _igual "verified con bash y ruta absoluta" "$(lab_estado verified)" "1"
}

caso_g2_runner_bash_tras_and_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cd /repo && bash tests/run.sh')"
  _igual "verified con bash tras &&" "$(lab_estado verified)" "1"
}

# Invocacion directa (sin verbo): solo cuenta ANCLADA al inicio del comando —
# `./tests/run.sh` y `tests/run.sh` pelados. Desanclarla reabriria A3.
caso_g2_runner_run_sh_directo_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash './tests/run.sh')"
  _igual "verified con ./tests/run.sh" "$(lab_estado verified)" "1"
  lab_run tool claude "$(lab_payload_bash 'tests/run.sh')"
  _igual "verified con tests/run.sh directo" "$(lab_estado verified)" "1"
}

# 9.10, clase A3 — mencionar/leer el runner NO es correrlo: el cat del propio
# runner y un grep sobre su texto no acreditan (analogos a cat pytest.log).
caso_g2_runner_run_sh_en_cat_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'cat tests/run.sh')"
  _igual "verified con cat tests/run.sh" "$(lab_estado verified)" "0"
}

caso_g2_runner_run_sh_en_grep_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'grep run.sh tests/run.sh')"
  _igual "verified con grep run.sh tests/run.sh" "$(lab_estado verified)" "0"
}

# ================= 9.10 r2 — posición de comando (cross-review codex r1, ALTA)
# Las ramas run.sh dentro de TEST_RUNNER_RE aceptaban DECOYS: el wrapper de
# fronteras no sabe de POSICION, y `bash contest/run.sh` ("contest" termina en
# "test"), `bash tests/run.sh/typo` (el `/` pasaba por frontera derecha),
# `grep bash tests/run.sh`, `printf 'bash tests/run.sh'` y `echo bash
# tests/run.sh` acreditaban verified=1 sin correr la suite. El fix mueve las
# ramas run.sh a TEST_RUNNER_CMD_RE (constante propia, SIN wrapper, con
# posición de comando y segmentos de path estrictos); TEST_RUNNER_RE/WORD_RE
# vuelve a su forma pre-9.10 para los runners clásicos.

# Positivos nuevos de la matriz de aceptación r2 (args tras el runner y otro
# verbo shell): controlan que el endurecimiento no coma las formas legitimas.
caso_g2_runner_bash_con_args_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash tests/run.sh arg --flag')"
  _igual "verified con bash tests/run.sh arg --flag" "$(lab_estado verified)" "1"
}

caso_g2_runner_zsh_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'zsh tests/run.sh')"
  _igual "verified con zsh tests/run.sh" "$(lab_estado verified)" "1"
}

# Decoy 1 (r1): "contest" termina en "test" y `[^[:space:]]*` se comia "con" —
# un directorio que NO es tests/ acreditaba la suite entera.
caso_g2_runner_decoy_contest_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash contest/run.sh')"
  _igual "verified con bash contest/run.sh (decoy)" "$(lab_estado verified)" "0"
}

# Decoy 2 (r1): el `/` tras run.sh pasaba por frontera derecha del wrapper —
# un path typo'eado acreditaba.
caso_g2_runner_decoy_typo_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'bash tests/run.sh/typo')"
  _igual "verified con bash tests/run.sh/typo (decoy)" "$(lab_estado verified)" "0"
}

# Decoys 3-5 (r1): mencionar el verbo NO es correrlo. `grep bash tests/run.sh`,
# `printf 'bash tests/run.sh'` y `echo bash tests/run.sh` ponen el verbo en
# posicion de ARGUMENTO o dentro de comillas/prosa — el espacio o la comilla
# antes de `bash` pasaba la frontera izquierda del wrapper.
caso_g2_runner_decoy_grep_bash_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'grep bash tests/run.sh')"
  _igual "verified con grep bash tests/run.sh (decoy)" "$(lab_estado verified)" "0"
}

caso_g2_runner_decoy_printf_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash "printf 'bash tests/run.sh'")"
  _igual "verified con printf entrecomillado (decoy)" "$(lab_estado verified)" "0"
}

caso_g2_runner_decoy_echo_no_marca() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'echo bash tests/run.sh')"
  _igual "verified con echo bash tests/run.sh (decoy)" "$(lab_estado verified)" "0"
}

# ============================================== G3 — secuencia de subagentes
CASOS_G3="caso_g3_grok_ceremonia_completa_cierra caso_g3_grok_ceremonia_incompleta_bloquea caso_g3_grok_ceremonia_no_corre_en_cursor caso_g3_falta_reviewer_bloquea caso_g3_fuera_de_orden_bloquea caso_g3_cursor_no_exige_secuencia caso_g3_agente_generico_no_cuenta caso_g3_agent_type_cuenta caso_g3_agent_type_generico_no_cuenta caso_g3_gana_el_de_tool_input_no_el_ultimo caso_g3_eco_fuera_de_tool_input_no_cuenta caso_g3_nombres_del_host_mapean caso_g3_turno_completo_por_eventos_permite caso_g3_target_por_claudecode_fallback caso_g3_target_por_zcode_fallback caso_g3_ceremonia_se_exige_en_codex caso_g3_role_fallback_implementer_permite caso_g3_role_fallback_verifier_permite caso_g3_role_fallback_reviewer_permite caso_g3_fast_cierra_sin_subagentes caso_g3_fast_sin_recibo_sigue_bloqueando caso_g3_grok_spawn_registra_rol caso_g3_grok_interno_registra_rol"

caso_g3_falta_reviewer_bloquea() {
  lab_sembrar 123456 0 1 1 "implementer,verifier"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "stdout" "$LAB_OUT" '"decision":"block"'
  _contiene "motivo" "$LAB_OUT" 'Missing reviewer subagent run'
  _no_contiene "motivo" "$LAB_OUT" 'Missing implementer subagent run'
  _no_contiene "motivo" "$LAB_OUT" 'Missing verifier subagent run'
}

caso_g3_fuera_de_orden_bloquea() {
  lab_sembrar 123456 0 1 1 "reviewer,implementer,verifier"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Subagents ran out of order'
}

# La secuencia es una primitiva de Claude Code (Task/subagent_type). En cursor
# el mismo estado cierra limpio: el gate no la exige.
caso_g3_cursor_no_exige_secuencia() {
  lab_sembrar 123456 0 1 1 ""
  lab_run stop cursor "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "0"
  _igual "stdout" "$LAB_OUT" '{}'
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# Los agentes genericos no llevan rol: si contaran, un Explore cualquiera
# satisfaria un gate sin que corriera el subagente que corresponde.
caso_g3_agente_generico_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_agent 'general-purpose')"
  _igual "agents_seen tras general-purpose" "$(lab_estado agents_seen)" ""
  lab_run tool claude "$(lab_payload_agent 'Explore')"
  _igual "agents_seen tras Explore" "$(lab_estado agents_seen)" ""
}

# A9, CERRADO por la Task 3.7. Antes `caso_g3_agent_type_no_cuenta` y afirmaba
# lo opuesto (el defecto grabado a proposito): el rol de los eventos INTERNOS del
# subagente viaja en `agent_type` de primer nivel, y el hook solo leia
# `subagent_type` (que vive en los eventos Agent, que el matcher no cubre) ->
# agents_seen quedaba vacio con los tres subagentes corridos. Ahora el hook lee
# agent_type como fallback (:831) y el caso afirma que SI cuenta. El escenario 16
# de la linea base graba el turno entero; este caso graba la pieza suelta.
caso_g3_agent_type_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'implementer' 'npm test')"
  _igual "agents_seen con agent_type=implementer (A9 cerrado)" "$(lab_estado agents_seen)" "implementer"
}

# El canal que abre A9 (agent_type top-level) necesita las MISMAS dos guardias
# que ya tiene el de subagent_type, y no las hereda gratis (CORRECCION 6 del
# plan). Dos afirmaciones:
#   1. un agent_type generico no inventa rol (gemelo de
#      caso_g3_agente_generico_no_cuenta, que solo cubre subagent_type);
#   2. es FALLBACK: con los dos presentes gana subagent_type. La forma del
#      segundo payload es real -- una delegacion ANIDADA trae el agent_type del
#      subagente padre y el subagent_type del hijo.
caso_g3_agent_type_generico_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'general-purpose' 'ls')"
  _igual "agent_type generico no inventa rol" "$(lab_estado agents_seen)" ""
  lab_run tool claude "$(lab_payload_agent_anidado 'implementer' 'reviewer')"
  _igual "subagent_type gana sobre agent_type (fallback)" "$(lab_estado agents_seen)" "implementer"
}

# DEFECTO A10, el caso que lo habria atrapado. El host no propaga el prefijo
# VAR=val del comando registrado (medido 2026-08-11), asi que
# SUMMONAIKIT_HOOK_TARGET llega vacio y [ "$TARGET" = "claude" ] era siempre
# falso -> la secuencia nunca se exigi. El arreglo detecta Claude por
# CLAUDECODE=1 (fallback). Aqui NO se setea SUMMONAIKIT_HOOK_TARGET (target=auto)
# pero SI CLAUDECODE=1 (via LAB_CLAUDECODE). El RECIBO VA COMPLETO a proposito:
# es lo unico que hace discriminar al caso (CORRECCION 5 del plan). Con recibo,
# sin el arreglo el Stop cierra LIMPIO (exit 0, TARGET vacio => la rama de
# secuencia no corre); con el arreglo bloquea reclamando los tres roles.
caso_g3_target_por_claudecode_fallback() {
  # Task 5.3: CLAUDECODE=1 hace que el hook lea state/claude/ (HOST entra al
  # path). lab_sembrar escribe a LAB_ESTADO_PATH, que lab_init descubrio sin
  # senal => state/other/. Para que el seed caiga donde el hook leera, se apunta
  # LAB_ESTADO_PATH al path de claude/ SOLO al sembrar y se restaura enseguida.
  # (Local: los helpers del lab siguen esquema-agnosticos — no asumir state/<host>/
  # porque la bateria de mutaciones muta el esquema, p. ej. host_sin_llave.)
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/claude/|')"
  lab_sembrar 123456 0 1 1 ""   # todo en orden salvo agents_seen (vacio)
  LAB_ESTADO_PATH="$_ep_backup"
  LAB_CLAUDECODE=1
  lab_run stop auto "$(lab_payload_stop "$_RECIBO_VINETAS")"
  LAB_CLAUDECODE=""
  _igual "exit code (CLAUDECODE=1 => TARGET=claude => secuencia exigida)" "$LAB_RC" "2"
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'
}

# Task 6.4 (D3) — la ceremonia se exige TAMBIEN con TARGET=codex. 6.1 midio que
# el rol llega en Codex (agent_type de primer nivel, forma identica a Claude
# post-3.7), asi que la rama SE PRENDE: [ "$TARGET" = "claude" ] pasa a
# case claude|codex. La forma del bloqueo es la que 6.2 midio: el JSON viaja
# con exit 0 porque Codex descarta el stdout si el exit no es 0 — la mitad de
# salida la ata caso_g6_bloqueo_codex_exit_cero. Y la escotilla ROLE FALLBACK
# (D4) tiene que valer por la MISMA rama: es la primera vez que la ceremonia
# corre en Codex y sin escotilla un 429 dejaria el turno sin salida.
caso_g3_ceremonia_se_exige_en_codex() {
  # Sembrar bajo state/codex/: el Stop con TARGET=codex lee ahi (Task 5.3).
  # Mismo malabar que caso_g3_target_por_claudecode_fallback y por el mismo
  # motivo: los helpers del lab son esquema-agnosticos a proposito.
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/codex/|')"
  lab_sembrar 123456 0 1 1 ""   # todo en orden salvo agents_seen (vacio)
  lab_run stop codex "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit (el bloqueo codex viaja con exit 0, medido 6.2)" "$LAB_RC" "0"
  _contiene "decision de bloqueo en codex" "$LAB_OUT" '"decision":"block"'
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'

  # La escotilla D4 vale en codex: dos roles corridos, el tercero declarado.
  lab_limpiar_estado
  lab_sembrar 123456 0 1 1 "implementer,verifier"
  lab_run stop codex "$(lab_payload_stop "$_RECIBO_ROLE_FALLBACK_REVIEWER")"
  _igual "exit con ROLE FALLBACK: REVIEWER declarado en codex" "$LAB_RC" "0"
  _no_contiene "sin bloqueo con la escotilla declarada" "$LAB_OUT" '"decision":"block"'
  LAB_ESTADO_PATH="$_ep_backup"
}

# ===================== Task 5.4 — TARGET/budget/PHASE para el segundo host ====

# G3: ZCODE_* es la senal del segundo host. TARGET resuelve a "claude" por ese
# fallback (no por CLAUDECODE, que zcode no setea). Mismo truco de LAB_ESTADO_PATH
# que el fallback CLAUDECODE, pero el seed cae en state/zcode/.
caso_g3_target_por_zcode_fallback() {
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/zcode/|')"
  lab_sembrar 123456 0 1 1 ""   # todo en orden salvo agents_seen (vacio)
  LAB_ESTADO_PATH="$_ep_backup"
  LAB_ZCODE_SESSION_ID="sess_lab"
  lab_run stop auto "$(lab_payload_stop "$_RECIBO_VINETAS")"
  LAB_ZCODE_SESSION_ID=""
  _igual "exit code (ZCODE_* => TARGET=claude => secuencia exigida)" "$LAB_RC" "2"
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'
}

# D4 (Task 6.3) — absorbe la escotilla ROLE FALLBACK del sabor Codex del kit
# (unica de las cinco divergencias que es codigo en la condicion del gate, no
# texto de contrato). Sembrado SIN despachar el rol correspondiente y CON la
# declaracion en el recibo: el gate tiene que aceptarla en vez del despacho y
# cerrar limpio, no reclamar "Missing <rol> subagent run".
#
# UN CASO POR ROL, no uno solo (revision cruzada, ciclo 1): las tres ramas del
# gate estan tipeadas a mano con un literal de rol distinto cada una -- no son
# un loop sobre una lista -- y `mut_role_fallback_quitada` rompe las tres A LA
# VEZ con un solo sed sobre la subcadena compartida. Esa mutacion prueba que el
# mecanismo anda en ALGUN lado, no que cada rama sea correcta por separado: un
# typo en la rama de IMPLEMENTER (el literal del rol mal escrito, o el mensaje
# de otro rol pegado ahi) no lo atrapaba nadie sin su propio caso. Mismo
# precedente que ya tiene este archivo en G2 (un caso por runner sobre un
# mecanismo compartido: pytest/tsc/phpunit/cargo/go).
#
# El caso que bloquea sin despacho Y sin declaracion ya existe para el rol
# reviewer (caso_g3_falta_reviewer_bloquea ejercita la MISMA rama *) con un
# recibo sin ROLE FALLBACK) — no se duplica esa mitad.
caso_g3_role_fallback_implementer_permite() {
  lab_sembrar 123456 0 1 1 "verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_ROLE_FALLBACK_IMPLEMENTER")"
  _igual "exit code (ROLE FALLBACK sustituye al despacho, D4)" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

caso_g3_role_fallback_verifier_permite() {
  lab_sembrar 123456 0 1 1 "implementer,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_ROLE_FALLBACK_VERIFIER")"
  _igual "exit code (ROLE FALLBACK sustituye al despacho, D4)" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

caso_g3_role_fallback_reviewer_permite() {
  lab_sembrar 123456 0 1 1 "implementer,verifier"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_ROLE_FALLBACK_REVIEWER")"
  _igual "exit code (ROLE FALLBACK sustituye al despacho, D4)" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# Task 10.1 — carril fast en la secuencia: con lane=fast (armado por eventos con
# -saikit:fast), un turno con recibo completo y verify cierra SIN subagentes; el
# mismo turno sin recibo sigue bloqueando por el recibo (el carril no es un
# salta-gate: exime la ceremonia, no el recibo ni la evidencia). El turno se
# arma por EVENTOS (no lab_sembrar): el campo lane del estado lo escribe el
# armado, y sembrarlo a mano probaria otra cosa.
caso_g3_fast_cierra_sin_subagentes() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "fast cierra sin ceremonia" "$LAB_RC" "0"
  if lab_hay_estado; then _mal "un cierre limpio fast debe borrar el estado del turno"; fi
}

caso_g3_fast_sin_recibo_sigue_bloqueando() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit:fast corrige el typo')"
  lab_run tool claude "$(lab_payload_edit '/proyecto/src/header.ts')"
  lab_run stop claude "$(lab_payload_stop 'listo, creo')"
  _igual "fast sin recibo bloquea" "$LAB_RC" "2"
  _contiene "motivo (el recibo sigue exigido en fast)" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  _no_contiene "motivo (la ceremonia no se exige en fast)" "$LAB_OUT" 'Missing implementer subagent run'
}

# G5: en zcode continue:false+exit 0 es ignorado (5.2). El corte por presupuesto
# depende del exit 2 que esta task anade al budget. Sin ZCODE_* sigue exit 0
# (regresion Claude = caso_g5_presupuesto_agotado).
caso_g5_presupuesto_zcode_exit2() {
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/zcode/|')"
  lab_sembrar 123456 2 1 1 "implementer,verifier,reviewer"
  LAB_ESTADO_PATH="$_ep_backup"
  LAB_ZCODE_SESSION_ID="sess_lab"
  lab_run stop auto "$(lab_payload_stop "$_TEXTO_LLANO")"
  LAB_ZCODE_SESSION_ID=""
  _igual "exit code (zcode budget => exit 2)" "$LAB_RC" "2"
  _no_contiene "stdout (continue:false no se emite en zcode)" "$LAB_OUT" '"continue":false'
  _contiene "stderr" "$LAB_ERR" 'REVISION BUDGET EXHAUSTED'
}

# G4: un Stop de zcode trae SOLO hookEventName (camel). Sin leer camel, PHASE cae
# a "tool" y stop_gate no corre (el Stop no bloquea). Usa CLAUDECODE=1 para aislar
# el cambio PHASE del cambio TARGET.
caso_g4_stop_camel_solo_bloquea() {
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/claude/|')"
  lab_sembrar 123456 0 1 1 ""
  LAB_ESTADO_PATH="$_ep_backup"
  LAB_CLAUDECODE=1
  # fase=auto (NO se pasa SUMMONAIKIT_HOOK_PHASE): el hook tiene que detectar
  # PHASE del payload. Es justamente lo que este caso prueba — un Stop camel-only
  # debe resolver PHASE=stop leyendo hookEventName. Con `lab_run stop auto` el env
  # le daria la fase y el lector camel nunca se ejercitaria (leccion de 5.4).
  lab_run auto auto "$(lab_payload_stop_camel "$_RECIBO_VINETAS")"
  LAB_CLAUDECODE=""
  _igual "exit code (Stop camel-only => PHASE=stop => gate corre)" "$LAB_RC" "2"
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'
}

# DEFECTO A1 — cerrado por la Task 3.1. Los dos casos que siguen son las dos
# mitades del vector medido en el escenario 12 de la linea base, y hasta la 3.1
# los dos estaban en ROJO contra el hook vivo.
#
# El lector de campos del hook arrancaba con `.*` greedy sobre el payload CRUDO,
# que incluye `tool_response` — texto que el turno NO escribio. De ahi salen las
# dos afirmaciones: que una clave fuera de `tool_input` no acredite nada, y que
# cuando estan las dos gane la de `tool_input` y no la ultima.
#
# La primera es la que mide el dano real: el greedy no solo INVENTABA un rol,
# BORRABA el legitimo — con `tool_input.subagent_type=implementer` y un eco
# `reviewer` mas adelante, el hook anotaba reviewer y perdia al implementer.
#
# El orden entre los dos no es cosmetico: van en este porque cada uno atrapa una
# mutacion DISTINTA (la bateria de mutaciones corta en el primer rojo). El de
# abajo atrapa que el lector vuelva a ser greedy; el de arriba, que el escaner
# deje de acotarse a `tool_input`. Invertirlos dejaria una de las dos mutaciones
# sin caso propio en la declaracion.
caso_g3_gana_el_de_tool_input_no_el_ultimo() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_agent_con_eco 'implementer' 'reviewer')"
  _igual "gana el subagent_type de tool_input, no la ultima ocurrencia (A1)" \
         "$(lab_estado agents_seen)" "implementer"
}

caso_g3_eco_fuera_de_tool_input_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_eco_subagent_type 'reviewer')"
  _igual "agents_seen con subagent_type fuera de tool_input (A1)" "$(lab_estado agents_seen)" ""
}

# El gate mapea por FUNCION, no por una lista fija por host: los agentes
# globales de Claude Code tienen otros nombres que los del kit y un turno bien
# delegado con esos nombres tiene que satisfacerlo igual.
caso_g3_nombres_del_host_mapean() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_agent 'backend-engineer')"
  lab_run tool claude "$(lab_payload_agent 'test-engineer')"
  lab_run tool claude "$(lab_payload_agent 'code-reviewer')"
  _igual "agents_seen" "$(lab_estado agents_seen)" "implementer,verifier,reviewer"
}

# El unico caso que maneja el turno ENTERO por eventos reales. Es el que ata que
# los eventos PRODUCEN el estado que los demas casos siembran: sin el, sembrar
# seria probar contra una ficcion.
caso_g3_turno_completo_por_eventos_permite() {
  lab_run prompt claude "$(lab_payload_prompt '-saikit agrega el endpoint de sesiones')"
  lab_run tool claude "$(lab_payload_agent 'implementer')"
  lab_run tool claude "$(lab_payload_agent 'verifier')"
  lab_run tool claude "$(lab_payload_agent 'reviewer')"
  lab_run tool claude "$(lab_payload_bash 'pytest -q')"
  _igual "agents_seen" "$(lab_estado agents_seen)" "implementer,verifier,reviewer"
  _igual "verified"    "$(lab_estado verified)"    "1"

  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  _vacio "stderr" "$LAB_ERR"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# ================================================================ G4 — recibo
# ORDEN load-bearing: la bateria de mutacion corta en el primer caso rojo, asi
# que cada mutacion necesita su caso posicionado para ser alcanzado antes de que
# otro caso se ponga rojo por otra razon. Ver docs/task-3.2-plan.md CORRECCION 5.
CASOS_G4="caso_g4_pausa_permite caso_g4_pausa_en_resultado_bloquea caso_g4_pausa_en_thinking_no_cuenta caso_g4_delegado_permite caso_g4_delegado_sin_rol_bloquea caso_g4_delegado_incidental_en_recibo_roto_bloquea caso_g4_delegado_incidental_en_recibo_completo_cierra_limpio caso_g4_etiqueta_pegada_no_cuenta caso_g4_recibo_corrido_pasa_a8 caso_g4_recibo_dos_bloques_pasa caso_g4_falta_una_etiqueta_bloquea caso_g4_sin_recibo_bloquea caso_g4_recibo_en_vinetas_pasa caso_g4_recibo_corrido_solo_en_transcript_pasa caso_g4_recibo_solo_en_transcript_pasa caso_g4_transcript_fuera_de_perfil_se_ignora caso_g4_transcript_ruta_windows_y_traversal caso_g4_stop_camel_solo_bloquea caso_g4_pausa_vieja_solo_en_transcript_bloquea caso_g4_delegado_con_recibo_viejo_en_transcript_permite caso_g4_recibo_bold_pasa caso_g4_fuga_top_level_no_cierra caso_g4_cita_del_feedback_no_satisface caso_g4_grok_turno_completo_camel_cierra caso_g4_grok_stop_sin_recibo_bloquea caso_g4_grok_precedencia_lastmessage_gana_snake caso_g4_grok_transcriptpath_camel"

# La pausa declarada es una forma valida de terminar el turno: el agente
# pregunto y espera. Se acepta sin recibo, sin evidencia y sin subagentes.
# Nota grabada: por esta via el estado NO se borra (el turno sigue abierto a
# proposito). Es la mitad buena de A2; la mitad mala — que la pausa se encuentre
# adentro del resultado de una herramienta — la cierra la Task 3.2.
# Task 9.6 (C12). El walker pone en_text/en_assistant en 1 y NUNCA los resetea al
# cerrar llaves, y su condicion de emision no mira `depth`. Consecuencia: un
# valor top-level POSTERIOR a `message` se concatena al texto del asistente y
# aporta etiquetas que el turno no escribio. Aca la fuga trae justo la etiqueta
# que falta (Retro), asi que con el defecto el gate CIERRA por texto ajeno.
#
# Stop sin last_assistant_message a proposito: asi decide el canal transcript,
# que es donde vive la condicion que se esta probando.
caso_g4_fuga_top_level_no_cierra() {
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop_sin_mensaje)"           "$(lab_transcript_fuga_top_level "$_RECIBO_SIN_RETRO" 'Retro: none.')"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Retro'
}

caso_g4_pausa_permite() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_PAUSA")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if ! lab_hay_estado; then _mal "la pausa no cierra el turno: el estado tiene que seguir ahi"; fi
}

# C11 (Task 9.3) — citar el feedback del gate no es escribir un recibo. El
# turno esta completo salvo por el recibo (agents/implemented/verified
# sembrados), y el mensaje final CITA el marcador y las etiquetas entre
# comillas: sin la frontera que excluye comillas, las seis contaban y el gate
# cerraba. Limite declarado (advisory por diseno): citar el TEMPLATE completo
# del recibo, con sus saltos de linea reales, seguiria contando — es
# indistinguible de un recibo real.
caso_g4_cita_del_feedback_no_satisface() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_CITA_FEEDBACK")"
  _igual "exit citando el feedback" "$LAB_RC" "2"
}

# C4 (auditoria 2026-08-13, Task 8.2), mitad PAUSED — el tail de 160 lineas
# conserva texto de turnos ANTERIORES: un PAUSED viejo en el transcript dejaba
# pasar el gate ENTERO de un turno que no pauso (el mensaje final del turno es
# texto llano sin recibo). La escotilla debe mirar el turno actual
# (last_assistant_message), no la historia.
caso_g4_pausa_vieja_solo_en_transcript_bloquea() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop 'Ya quedo el cambio, avisame.')" "$(lab_transcript_asistente "$_TEXTO_PAUSA")"
  _igual "exit code con PAUSED viejo en el tail" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
}

# C4, mitad DELEGATED — el recibo del turno ANTERIOR en el tail hacia fallar la
# clausula "recibo ausente" de la escotilla, y un turno de delegacion legitimo
# se bloqueaba: falso rojo => ciclos de revision de mas (la lentitud medida).
caso_g4_delegado_con_recibo_viejo_en_transcript_permite() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_DELEGADO")" "$(lab_transcript_asistente "$_RECIBO_VINETAS")"
  _igual "exit code delegando con recibo viejo en el tail" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if ! lab_hay_estado; then _mal "la delegacion no cierra el turno: el estado debe seguir (C4)"; fi
}

# C7 (auditoria 2026-08-13, Task 8.3) — un recibo completo y honesto con las
# etiquetas en markdown bold cierra limpio; antes las 6 etiquetas fallaban por
# el `**` entre la etiqueta y el `:` (falso rojo => ciclos de mas).
caso_g4_recibo_bold_pasa() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_BOLD")"
  _igual "exit code con recibo bold" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio con recibo bold debe borrar el estado"; fi
}

# DEFECTO A2, la mitad mala: la cadena de pausa aparece SOLO adentro del
# `content` de un `tool_result` en el transcript — un mensaje `user`, no
# `assistant`. El asistente nunca la escribio; hoy el grep crudo sobre el tail la
# encuentra y el gate deja pasar. La Task 3.2 cierra esto: el walker ignora todo
# texto que no sea de un mensaje assistant, y la pausa aqui vive en uno user.
# Es el caso que habria atrapado A2. Estado NO borrado: el turno sigue abierto.
caso_g4_pausa_en_resultado_bloquea() {
  _sembrar_turno_completo
  # Stop SIN last_assistant_message a proposito (Task 8.2): la escotilla ahora
  # mira el turno actual y solo cae al canal transcript cuando el payload no
  # trae el campo — que es exactamente el camino donde la condicion role:assistant
  # del walker decide, y lo que mantiene atrapable a mut_texto_incluye_tool_result.
  lab_run stop claude "$(lab_payload_stop_sin_mensaje)" "$(lab_transcript_pausa_en_resultado)"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  if ! lab_hay_estado; then _mal "el turno sigue abierto: el estado no se borra mientras el gate reclama"; fi
}

# CORRECCION 1 (plan 3.2): la pausa en un content item que NO es type:text de
# un mensaje ASSISTANT tampoco cuenta. Es el caso que separa "lo escribio el
# asistente como respuesta" (type:text) de "lo escribio el asistente pensando o
# en otra clave". El walker tiene que exigir `"type":"text"` exacto; sin este
# caso, mutar el walker para que acepte cualquier content[] de assistant
# pasaria inadvertida. Se usa thinking (no tool_use) porque su `text` vive a la
# profundidad que el walker rastrea y asi la mutacion type:text es atrapable.
caso_g4_pausa_en_thinking_no_cuenta() {
  _sembrar_turno_completo
  # Stop sin last_assistant_message por la misma razon que
  # caso_g4_pausa_en_resultado_bloquea (Task 8.2): la condicion type:text del
  # walker decide en el fallback, y asi mut_texto_incluye_tool_use sigue atrapable.
  lab_run stop claude "$(lab_payload_stop_sin_mensaje)" "$(lab_transcript_thinking_con_pausa)"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
}

# ARREGLO 1 — escotilla "delegado y en vuelo", hermana de la pausa de arriba.
# El contrato exige delegar a tres subagentes en secuencia, y esos subagentes
# tardan (30-100 min medidos). Sin esta escotilla, un turno que delego y sigue
# esperando queda atrapado: o bloquea horas, o cierra y el Stop gate reclama
# el recibo que todavia no puede escribir. Se acepta sin recibo, sin evidencia
# y sin la secuencia completa -- igual que la pausa, y por la misma razon: el
# agente esta correctamente esperando, no fallando.
caso_g4_delegado_permite() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_DELEGADO")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if ! lab_hay_estado; then _mal "la delegacion no cierra el turno: el estado tiene que seguir ahi"; fi
}

# La escotilla SOLO vale si nombra uno de los tres roles canonicos
# (implementer/verifier/reviewer) -- igual disciplina que ROLE FALLBACK (D4,
# Task 6.3): sin el rol, "DELEGATED" a secas seria un "salteate el gate"
# generico y no uno auditable. El turno sigue abierto (mismo criterio que la
# pausa: el gate reclama el recibo normal, no una etiqueta puntual).
caso_g4_delegado_sin_rol_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_DELEGADO_SIN_ROL")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  if ! lab_hay_estado; then _mal "el turno sigue abierto: el estado no se borra mientras el gate reclama"; fi
}

# Bug de cross-review (ciclo 1), REPRODUCIDO con ejecucion: la escotilla
# DELEGATED disparaba (exit 0, sin feedback) con un recibo ROTO que solo
# menciona la frase de pasada -- exactamente el "salteate el gate" que la
# exigencia del rol queria evitar. Con el arreglo (exigir recibo AUSENTE), el
# recibo (esta presente, aunque roto) desactiva la escotilla y el turno cae
# al gate normal, que reclama lo que falta de verdad.
caso_g4_delegado_incidental_en_recibo_roto_bloquea() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_ROTO_CON_DELEGADO_INCIDENTAL")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _contiene "motivo" "$LAB_OUT" 'Missing implementer subagent run'
  if ! lab_hay_estado; then _mal "el turno sigue abierto: el estado no se borra mientras el gate reclama"; fi
}

# La otra mitad del mismo bug: un recibo COMPLETO que menciona la frase
# DELEGATED en Retro cerraba exit 0 pero NO borraba el estado (la escotilla
# lo interceptaba antes de llegar al cierre limpio de verdad). Con el
# arreglo, el recibo desactiva la escotilla, el turno cae al camino normal, y
# como esta completo cierra limpio DE VERDAD (estado borrado) -- la regla de
# hierro del repo (recibo completo = cierre limpio) se restablece.
caso_g4_delegado_incidental_en_recibo_completo_cierra_limpio() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS_CON_DELEGADO_EN_RETRO")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un recibo completo tiene que cerrar limpio de verdad (estado borrado), no colgarse de la escotilla DELEGATED"; fi
}

# Repone el atrapador de mut_etiqueta_sin_frontera que el caso A8 invertido le
# quito. La palabra `misunderstand` termina en `understand:` — con la frontera
# sana `(^|[^[:alpha:]])` la `s` alfabetica que precede impide el match y la
# etiqueta falta; con la mutacion `(^|.)` cuenta y "Missing Understand" desaparece
# del motivo. Afirma SOLO sobre Understand para no robarle la declaracion a
# mut_retro_no_se_exige.
caso_g4_etiqueta_pegada_no_cuenta() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'hubo un misunderstand: aclarar con el usuario.')"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing Understand gate summary'
}

# DEFECTO A8, INVERTIDO por la Task 3.2. Antes este recibo escrito en texto
# corrido (sin viñetas) fallaba las 6 etiquetas: en el JSONL el salto va escapado
# y el caracter que precede a cada etiqueta es la `n` de `\n`, alfabetico, que la
# frontera `[^[:alpha:]]` rechaza. El arreglo decodifica el texto del asistente
# antes de evaluar, asi que `\n` se vuelve un salto real y la etiqueta pasa.
# Verifica ademas que el canal payload (last_assistant_message) decodifica.
caso_g4_recibo_corrido_pasa_a8() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_CORRIDO")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# Hallazgo de la revision cruzada (codex, 2026-08-11): un mensaje assistant con
# DOS content items type:text se concatenaban sin separador. Si el primero
# termina en letra, la etiqueta del segundo no se reconoce por la frontera
# [^[:alpha:]] de has_receipt_label. El walker ahora agrega \n al cerrar cada
# content item. Sin este caso, revertir ese salto pasaria inadvertido.
caso_g4_recibo_dos_bloques_pasa() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'Listo.')" "$(lab_transcript_dos_bloques_recibo)"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

caso_g4_falta_una_etiqueta_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_SIN_RETRO")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing Retro gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing Understand gate summary'
  _no_contiene "motivo" "$LAB_OUT" 'Missing Close gate summary'
}

caso_g4_sin_recibo_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  for etiqueta in Understand Implement Verify Review Close Retro; do
    _contiene "motivo" "$LAB_OUT" "Missing $etiqueta gate summary"
  done
}

caso_g4_recibo_en_vinetas_pasa() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# Cruce que faltaba: canal transcript x A8 (texto corrido). Con dos
# decodificadores hay que probar cada canal por separado; el plan original
# probaba corrido-en-payload y viñetas-en-transcript, dejando esta combinacion
# sin cubrir. Verifica que el walker del transcript decodifica los `\n`.
caso_g4_recibo_corrido_solo_en_transcript_pasa() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'Listo.')" "$(lab_transcript_asistente "$_RECIBO_CORRIDO")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# El recibo tiene DOS canales y los dos cuentan: el payload del Stop trae
# `last_assistant_message` (por donde entra en los casos de arriba) y ademas el
# hook lee el tail del transcript. Aca el payload dice cualquier cosa y el recibo
# esta solo en el transcript.
#
# No es un detalle: que el tail del transcript CRUDO tambien cuente es la raiz de
# A2 — por ahi entra tambien lo que aparece adentro del resultado de una
# herramienta, que el asistente no escribio. El escenario 14 de la linea base lo
# graba; este caso ata la mitad legitima.
caso_g4_recibo_solo_en_transcript_pasa() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'Listo.')" "$(lab_transcript_asistente "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado del turno"; fi
}

# DEFECTO A6, el caso que lo habria atrapado. transcript_path sale del payload y el
# hook le hacia tail sin acotar: primitiva de lectura de archivo arbitrario. Un
# payload con transcript_path apuntando a un transcript falso plantado fuera del
# perfil del host (aqui, un hermano del banco bajo TMPDIR) entregaba un recibo que
# el asistente no escribio, y el gate cerraba limpio. El arreglo (Task 3.6) exige
# que la ruta resuelva DENTRO del perfil (dirname HOOK_DIR); fuera de ahi se ignora
# (fail-open, transcript=unknown) y el gate corre solo con last_assistant_message.
caso_g4_transcript_fuera_de_perfil_se_ignora() {
  _sembrar_turno_completo
  # Transcript con recibo valido, AFUERA de $LAB. mktemp crea bajo TMPDIR (run.sh
  # lo apunta a la caja del test); $LAB es un subdirectorio de ahi, asi que este
  # hermano queda fuera del perfil del hook del banco.
  _tr_externo="$(mktemp "${TMPDIR:-/tmp}/saikit-a6-XXXXXX.jsonl")" || { _mal "no se pudo crear transcript externo"; return; }
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_externo"
  # Stop con transcript_path = ruta externa literal y mensaje neutro (sin recibo).
  lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$_tr_externo")"
  rm -f "$_tr_externo"
  _igual "exit code (el transcript externo se ignora, A6)" "$LAB_RC" "2"
  _contiene "motivo (el recibo externo no cuenta)" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
  _contiene "reporte por stderr (fail-open, A6)" "$LAB_ERR" 'transcript=unknown'
  if ! lab_hay_estado; then _mal "el turno sigue abierto: el estado no se borra mientras el gate reclama"; fi
}

# La otra mitad del arreglo de A6: la contencion NO puede apagar el canal legitimo.
# Dos vectores que una comparacion de strings crudos manejaria mal:
#   (a) forma WINDOWS: en produccion transcript_path llega como C:\\Users\\... (el
#       lector raw no decodifica) y HOOK_DIR como /c/Users/... . Solo cd+pwd las
#       vuelve comparables; sin eso el canal transcript se apaga en TODA la
#       produccion y ningun escenario de la linea base lo ve (todos usan rutas POSIX
#       del sandbox). La ruta entra cruda (backslash simple): json_string_field es un
#       extractor raw y cd+pwd la resuelve (medido; doblar backslashes se rompe en
#       MSYS2, ver hook_lab.sh).
#   (b) TRAVERSAL: una ruta que arranca adentro del perfil y sale con .. tiene el
#       prefijo crudo correcto y el destino equivocado. cd+pwd la resuelve antes de
#       mirar.
caso_g4_transcript_ruta_windows_y_traversal() {
  # (a) recibo en un transcript ADENTRO del perfil, apuntado en forma Windows.
  _sembrar_turno_completo
  _tr_dentro="$LAB/entrada/transcript-a6-win.jsonl"
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_dentro"
  if command -v cygpath >/dev/null 2>&1; then
    _tr_win="$(cygpath -w "$_tr_dentro")"
    lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$_tr_win")"
    _igual "exit code (ruta Windows in-bounds SI se lee)" "$LAB_RC" "0"
    _vacio "stdout (cierre limpio con el recibo del transcript)" "$LAB_OUT"
  fi
  # (b) una ruta que ARRANCA adentro del perfil y sale con ..: el prefijo crudo
  # matchea, el destino real no. Se re-siembra porque si (a) corrio, cerro limpio
  # y borro el estado del turno; sin re-sembrar (b) correria contra STATE_PATH
  # inexistente y stop_gate saldria por emit_allow (verde por vacio).
  _sembrar_turno_completo
  _tr_externo="$(mktemp "${TMPDIR:-/tmp}/saikit-a6-XXXXXX.jsonl")" || { _mal "no se pudo crear transcript externo"; return; }
  printf '%s\n' "$(lab_transcript_asistente "$_RECIBO_VINETAS")" > "$_tr_externo"
  lab_run stop claude "$(lab_payload_stop_ruta_literal 'Listo.' "$LAB/entrada/../../$(basename "$_tr_externo")")"
  rm -f "$_tr_externo"
  _igual "exit code (traversal fuera del perfil se ignora)" "$LAB_RC" "2"
  _contiene "reporte por stderr (traversal)" "$LAB_ERR" 'transcript=unknown'
}

# ================================================ G5 — presupuesto de 2 ciclos
CASOS_G5="caso_g5_presupuesto_agotado caso_g5_ciclos_cuentan_y_bloquean caso_g5_ciclo_consumido_no_impide_cerrar caso_g5_agotado_limpia_estado caso_g5_presupuesto_zcode_exit2 caso_g5_stop_fallido_no_borra_aviso_ajeno caso_g5_tool_name_eco_no_marca_edicion"

# Agotado el presupuesto cambia el CONTRATO DE SALIDA: ya no es un bloqueo con
# exit 2, es un `continue:false` con exit 0 — el turno se detiene y se le pide
# al usuario, en vez de mandar al agente a otra vuelta.
caso_g5_presupuesto_agotado() {
  lab_sembrar 123456 2 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" '"continue":false'
  _contiene "stdout" "$LAB_OUT" '"stopReason"'
  _contiene "stdout" "$LAB_OUT" 'REVISION BUDGET EXHAUSTED'
  _no_contiene "stdout" "$LAB_OUT" '"decision":"block"'
  _no_vacio "stderr" "$LAB_ERR"
}

caso_g5_ciclos_cuentan_y_bloquean() {
  lab_sembrar 123456 0 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code del ciclo 1" "$LAB_RC" "2"
  _contiene "motivo del ciclo 1" "$LAB_OUT" 'Current revision cycle: 1/2'
  _igual "cycle tras el primer bloqueo" "$(lab_estado cycle)" "1"

  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code del ciclo 2" "$LAB_RC" "2"
  _contiene "motivo del ciclo 2" "$LAB_OUT" 'Current revision cycle: 2/2'
  _igual "cycle tras el segundo bloqueo" "$(lab_estado cycle)" "2"
}

# El lado que deja pasar: haber gastado un ciclo no es en si mismo un motivo de
# bloqueo. Un turno que ya fallo una vez y ahora esta completo cierra limpio; el
# presupuesto solo decide QUE se hace cuando ademas falta algo.
caso_g5_ciclo_consumido_no_impide_cerrar() {
  lab_sembrar 123456 1 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if lab_hay_estado; then _mal "un cierre limpio debe borrar el estado aunque haya ciclos gastados"; fi
}

# DEFECTO A4 (clausula 4) — cerrado por la Task 3.4. Antes el presupuesto agotado
# dejaba el estado (cycle=MAX) en disco: el turno seguia cobrando recibo despues
# de declararse agotado. Ahora lo limpia. Sibling de caso_g5_presupuesto_agotado
# (que ata el contrato de salida); este ata la limpieza, para no mover la
# declaracion del caso existente.
caso_g5_agotado_limpia_estado() {
  lab_sembrar 123456 2 1 1 "implementer,verifier,reviewer"
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code del presupuesto agotado" "$LAB_RC" "0"
  _contiene "stdout del presupuesto agotado" "$LAB_OUT" 'REVISION BUDGET EXHAUSTED'
  if lab_hay_estado; then _mal "presupuesto agotado debe limpiar el estado — A4 c.4"; fi
}

# C14 (auditoria 2026-08-13, Task 9.8) — el borde declarado dice "el Stop de
# una sesion con secuencia RN limpia puede borrar el aviso pendiente"; un Stop
# que BLOQUEA no es eso. El elif del bloque REVIEW-NOTICE corria en TODO Stop:
# con contadores observados y secuencia limpia (review >= edit), un Stop
# fallido se llevaba el aviso que una sesion hermana dejo para el proximo
# turno del proyecto (RN_PENDING_PATH es per-PROYECTO a proposito).
# Task 10.10. El lector de `tool_name` esta acotado al nivel correcto del
# payload, pero desde que la 9.2 saco `tool_name` del credito de verificacion
# esa propiedad se quedo SIN ningun caso que la sostenga: la mutacion que
# devolvia el lector greedy no la atrapaba nadie y hubo que retirarla.
#
# Donde SIGUE siendo observable es aca: la deteccion de edicion del aviso RN
# mira `tool_name` contra `^(edit|write|...)$`. Con el lector greedy, un
# `tool_name` ECOADO adentro de `tool_response` se lee como si fuera el del
# evento, y el hook marca una edicion de codigo que nunca ocurrio — con lo que
# el aviso RN reclamaria una re-revision por un archivo que solo se LEYO.
caso_g5_tool_name_eco_no_marca_edicion() {
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt '-saikit turno que arma para medir el aviso RN')"
  rn_orden="${LAB_ESTADO_PATH%.env}-review-notice.env"

  lab_run tool claude "$(lab_payload_read_con_eco_tool_name '/proyecto/src/app.ts')"

  # MEDIDO al escribir el caso: el archivo de orden se crea en CADA evento con
  # las tres claves, y `last_code_edit` queda VACIA salvo que se detecte una
  # edicion real. Por eso el aserto mira el VALOR (`=.` = hay algo despues del
  # igual), no la presencia de la clave — la primera version miraba la clave y
  # daba rojo contra el hook sano.
  if [ -f "$rn_orden" ] && grep -q '^last_code_edit=.' "$rn_orden" 2>/dev/null; then
    _mal "un tool_name ECOADO en tool_response no puede contar como edicion: el evento fue un Read (valor: $(grep '^last_code_edit=' "$rn_orden"))"
  fi
}

caso_g5_stop_fallido_no_borra_aviso_ajeno() {
  # Armado e incompleto (este Stop bloquea), con secuencia RN limpia observada:
  # el elif pre-9.8 disparaba aqui y borraba el aviso ajeno.
  lab_sembrar 123456 0 0 0 ""
  printf 'last_code_edit=1\nlast_review=2\n' > "${LAB_ESTADO_PATH%.env}-review-notice.env"
  rn_ajeno="$(dirname "$(dirname "$LAB_ESTADO_PATH")")/review-notice-pending.log"
  printf 'SAIKIT REVIEW NOTICE: aviso de la sesion hermana.\n' > "$rn_ajeno"
  lab_run stop claude "$(lab_payload_stop 'sin recibo, sigo trabajando')"
  _igual "el Stop bloquea" "$LAB_RC" "2"
  [ -f "$rn_ajeno" ] || _mal "un Stop FALLIDO no debe borrar el aviso pendiente ajeno (C14)"

  # La mitad buena del borde: el CIERRE limpio de esa misma secuencia si puede
  # llevarselo (aviso desactualizado; si hiciera falta uno nuevo, el `if` del
  # bloque lo reescribe en ese mismo Stop).
  _sembrar_turno_completo
  printf 'last_code_edit=1\nlast_review=2\n' > "${LAB_ESTADO_PATH%.env}-review-notice.env"
  lab_run stop claude "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "el cierre limpio cierra" "$LAB_RC" "0"
  if [ -f "$rn_ajeno" ]; then
    _mal "el cierre LIMPIO con secuencia observada debe llevarse el aviso desactualizado (borde C14)"
  fi
}

# ========================================== G6 — salidas por target y por fase
CASOS_G6="caso_g6_bloqueo_por_target caso_g6_permiso_por_target caso_g6_presupuesto_agotado_por_target caso_g6_armado_por_target caso_g6_bloqueo_codex_exit_cero"

# El mismo estado, el mismo veredicto, dos contratos de salida distintos: en
# claude el host lee el exit code 2 y el JSON de decision; en cursor solo lee un
# mensaje de seguimiento, y un exit 2 ahi seria un error de hook.
caso_g6_bloqueo_por_target() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code en claude" "$LAB_RC" "2"
  _contiene "stdout en claude" "$LAB_OUT" '"decision":"block"'
  _no_vacio "stderr en claude" "$LAB_ERR"

  _sembrar_turno_completo
  lab_run stop cursor "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code en cursor" "$LAB_RC" "0"
  _contiene "stdout en cursor" "$LAB_OUT" '"followup_message"'
  _no_contiene "stdout en cursor" "$LAB_OUT" '"decision"'
  _vacio "stderr en cursor" "$LAB_ERR"
}

# Dejar pasar tambien tiene forma: en claude es silencio; en cursor hay que
# emitir JSON, y ademas cambia segun la fase.
caso_g6_permiso_por_target() {
  lab_run prompt claude "$(lab_payload_prompt 'un prompt sin sentinel')"
  _vacio "stdout en claude" "$LAB_OUT"

  lab_run prompt cursor "$(lab_payload_prompt 'un prompt sin sentinel')"
  _igual "stdout en cursor, fase prompt" "$LAB_OUT" '{"continue":true}'

  lab_run stop cursor "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "stdout en cursor, fase stop" "$LAB_OUT" '{}'
}

caso_g6_presupuesto_agotado_por_target() {
  lab_sembrar 123456 2 1 1 "implementer,verifier,reviewer"
  lab_run stop cursor "$(lab_payload_stop "$_TEXTO_LLANO")"
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" '"followup_message"'
  _contiene "stdout" "$LAB_OUT" 'REVISION BUDGET EXHAUSTED'
  _no_contiene "stdout" "$LAB_OUT" '"continue":false'
}

# Armar tambien cambia de forma por target Y por fase. Asimetria grabada: en
# cursor el contrato se entrega SOLO en la fase de sesion; en la fase de prompt
# el turno se arma (queda estado) pero el contrato no se inyecta.
caso_g6_armado_por_target() {
  lab_run session cursor "$(lab_payload_session 'continuar la tarea -saikit del turno anterior')"
  _contiene "stdout en cursor, fase session" "$LAB_OUT" '"additional_context"'
  _contiene "stdout en cursor, fase session" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'

  lab_limpiar_estado
  lab_run prompt cursor "$(lab_payload_prompt '-saikit agrega el endpoint de sesiones')"
  _igual "stdout en cursor, fase prompt" "$LAB_OUT" '{"continue":true}'
  if ! lab_hay_estado; then _mal "en cursor el turno se arma igual aunque el contrato no se inyecte"; fi

  lab_limpiar_estado
  lab_run session claude "$(lab_payload_session 'continuar la tarea -saikit del turno anterior')"
  _contiene "stdout en claude, fase session" "$LAB_OUT" '"hookEventName":"UserPromptSubmit"'
}

# Task 6.4 — la forma de salida de codex, medida en 6.2 (12 turnos headless):
# Codex DESCARTA el stdout del hook cuando el exit no es 0 (exit 2 => 1 Stop,
# 0 hook_prompt, NO bloquea; el mismo JSON con exit 0 => 4 Stops, bloquea).
# El emit_gate_failure del vivo (decision:block + exit 2) era DECORATIVO ahi.
# En target codex el JSON de bloqueo viaja con exit 0; claude conserva su
# exit 2 (caso_g6_bloqueo_por_target, arriba, lo sigue atando).
caso_g6_bloqueo_codex_exit_cero() {
  _ep_backup="$LAB_ESTADO_PATH"
  LAB_ESTADO_PATH="$(printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/codex/|')"
  _sembrar_turno_completo
  lab_run stop codex "$(lab_payload_stop "$_TEXTO_LLANO")"
  LAB_ESTADO_PATH="$_ep_backup"
  _igual "exit code en codex (con exit 2 Codex descarta el stdout, 6.2)" "$LAB_RC" "0"
  _contiene "stdout en codex" "$LAB_OUT" '"decision":"block"'
  _no_vacio "stderr en codex (el feedback igual se reporta)" "$LAB_ERR"
}

# ============================ Task 7.3: envelope Grok Build (D2+D4+D5+D6) ====
# Casos contra el envelope medido en 7.1 (claves camel, valor de evento snake,
# prompt wrappeado en <user_query>, toolResult con exit_code, reason en el
# Stop). La senal de host va por env (LAB_GROK_HOOK_EVENT): GROK_HOOK_EVENT la
# inyecta el runner de Grok, nunca el payload. Fase "auto": la fase la deriva
# el hook del hookEventName del payload, que es lo que esta task agrego al
# case — inyectar PHASE por env saltaria el codigo bajo prueba.

# Re-apunta al arbol de estado de grok (patron del caso codex de arriba). El
# armado real ya creo el archivo ahi.
_grok_ruta_estado() {
  printf '%s' "$LAB_ESTADO_PATH" | sed 's|/state/[^/]*/|/state/grok/|'
}

caso_g1_grok_envelope_arma() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit agrega el endpoint de sesiones')"
  LAB_GROK_HOOK_EVENT=""
  _igual "exit code" "$LAB_RC" "0"
  _contiene "stdout" "$LAB_OUT" 'SUMMONAIKIT HARNESS REQUIRED'
  _gk="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep '/grok/' | head -n 1)"
  _no_vacio "estado bajo state/grok/ tras armar con envelope real (D4)" "$_gk"
}

# D2 — el catch de mut_host_grok_sin_rama. El escenario que la rama previene
# (espejo del caso codex): el operador lanza Grok DESDE ADENTRO de Claude, el
# runner de Grok setea GROK_HOOK_EVENT pero el proceso tambien hereda
# CLAUDECODE=1 del padre. Grok va PRIMERO en el orden: sin la rama, B resolveria
# HOST=claude y ambos turnos compartirian estado.
caso_g1_dos_hosts_grok_y_claude_no_comparten_estado() {
  LAB_SESSION_ID=""
  LAB_CLAUDECODE=1
  lab_run prompt claude "$(lab_payload_prompt '-saikit tarea del host Claude')"
  LAB_CLAUDECODE=""
  ruta_A="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep -v '/grok/' | head -n 1)"
  _no_vacio "ruta de estado de A tras armar" "$ruta_A"

  LAB_CLAUDECODE=1
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit tarea del host Grok')"
  LAB_CLAUDECODE=""
  LAB_GROK_HOOK_EVENT=""
  ruta_B="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep '/grok/' | head -n 1)"
  _no_vacio "estado de B bajo state/grok/ (GROK gana al CLAUDECODE heredado)" "$ruta_B"
  [ "$ruta_A" != "$ruta_B" ] || _mal "A (claude) y B (grok) comparten harness-state.env — D2 sin rama (Task 7.3)"
  [ -f "$ruta_A" ] || _mal "el estado de A se perdio al armar B"
}

# r1 (Greptile P2 / CR PR #27): la senal EXPORTADA VACIA tambien cuenta. El
# comentario de la rama dice "por presencia" y `-n` no la honraba: un runner
# que exporte GROK_HOOK_EVENT="" clasificaria por las senales heredadas (un
# CLAUDECODE=1 del padre) y el estado iria al arbol de otro host. Con el fix
# (setness), armar con la senal vacia deja el estado bajo state/grok/ — y el
# Stop de cierre (shutdown) tampoco lo toca. Es el catch de
# mut_grok_setness_por_valor.
caso_g1_grok_senal_exportada_vacia_cuenta() {
  LAB_GROK_HOOK_EVENT_VACIA=1
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit senal exportada vacia')"
  LAB_GROK_HOOK_EVENT_VACIA=""
  _gk="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep '/grok/' | head -n 1)"
  _no_vacio "GROK_HOOK_EVENT exportada VACIA sigue siendo senal de grok (setness)" "$_gk"

  LAB_GROK_HOOK_EVENT_VACIA=1
  lab_run auto grok "$(lab_payload_grok_stop 'el proceso se cierra' shutdown)"
  LAB_GROK_HOOK_EVENT_VACIA=""
  _igual "exit del Stop de cierre con senal vacia" "$LAB_RC" "0"
  [ -f "$_gk" ] || _mal "el Stop de cierre con senal vacia borro el estado del turno"
}

# D6 — el Stop de CIERRE (reason=shutdown, el proceso que se va) no es un Stop
# de turno: sale inmediato, sin contar ciclo, limpiar ni crear estado. El
# control del final ata que el Stop de TURNO (end_turn) si corre el gate.
caso_g1_grok_stop_shutdown_no_toca_estado() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit tarea con doble stop')"
  LAB_GROK_HOOK_EVENT=""
  _gk="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | grep '/grok/' | head -n 1)"
  _no_vacio "estado grok armado" "$_gk"

  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop 'el proceso se cierra' shutdown)"
  LAB_GROK_HOOK_EVENT=""
  _igual "exit del Stop de cierre" "$LAB_RC" "0"
  _vacio "stdout del Stop de cierre" "$LAB_OUT"
  [ -f "$_gk" ] || _mal "el Stop de cierre borro el estado del turno (D6)"
  _igual "cycle intacto tras el Stop de cierre" "$(grep '^cycle=' "$_gk" 2>/dev/null | tail -n 1 | cut -d= -f2-)" "0"

  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop 'todavia no cierro' end_turn)"
  LAB_GROK_HOOK_EVENT=""
  # 7.4: el bloqueo grok viaja con exit 0 (exit 2 es ignorado, 7.2) — el
  # control ahora mira la decision, no el exit code.
  _contiene "control D6: el Stop end_turn corre el gate" "$LAB_OUT" '"decision":"block"'
}

# D5 — el credito de verificacion con las formas camel completas: command bajo
# toolInput, exit_code 0.
caso_g2_grok_runner_marca_verificado() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit verifico con runner')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  _contiene "log con runner camel (verified)" "$(cat "$_gk_log" 2>/dev/null)" 'verified'
}

# D5, el catch — el runner rojo VISIBLE: toolResult.exit_code != 0 veta el
# credito (PostToolUseFailure no dispara en Grok 1.0.3, medido 7.1). Sin el
# veto, este comando acreditaba verificacion por ausencia de senal.
caso_g2_grok_runner_fallido_no_marca() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit runner reventado')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 1)"
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  case "$(cat "$_gk_log" 2>/dev/null)" in
    *verified*) _mal "runner rojo (toolResult.exit_code=1) acredito verificacion — D5 (Task 7.3)" ;;
  esac
}

# Variante de error medida (NoMatchesFound a primer nivel del toolResult),
# ejercida donde importa: command con runner y toolResult de error.
caso_g2_grok_nomatchesfound_no_marca() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit variante de error del toolResult')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok '{"sessionId":"__SESSION_ID__","hookEventName":"post_tool_use","toolName":"run_terminal_command","toolInput":{"command":"pytest -q","description":"paso"},"toolResult":{"type":"SearchReplace","NoMatchesFound":{}},"toolUseId":"tu-gk-05"}'
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  case "$(cat "$_gk_log" 2>/dev/null)" in
    *verified*) _mal "toolResult con NoMatchesFound acredito verificacion — D5 variante (Task 7.3)" ;;
  esac
}

# D5 — search_replace (la tool de edicion nativa que faltaba en la lista)
# acredita implemented via toolInput.file_path.
caso_g2_grok_edit_marca_implemented() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit edito un archivo')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  _contiene "log con edicion grok (implemented)" "$(cat "$_gk_log" 2>/dev/null)" 'implemented'
}

# La SEGUNDA tool de edicion nativa de Grok, la que el diseño ponia en negrita
# porque la doc la desconocia (7.1 la midio: write, minuscula, aparte de
# search_replace). End-to-end del canal: toolInput.file_path camel -> credito
# implemented (hallazgo CR PR #27).
caso_g2_grok_write_marca_implemented() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit escribe un archivo')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok '{"sessionId":"__SESSION_ID__","hookEventName":"post_tool_use","toolName":"write","toolInput":{"file_path":"/proyecto/src/nueva.py","content":"hola"},"toolResult":{"type":"Write"},"toolUseId":"tu-gk-06"}'
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  _contiene "log con write grok (implemented)" "$(cat "$_gk_log" 2>/dev/null)" 'implemented'
}

# Precedencia snake del padre: el runner viaja SOLO en toolInput (camel); el
# tool_input snake trae un comando sin runner. El snake gana -> no acredita.
caso_g2_grok_precedencia_toolinput_gana_snake() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit precedencia del padre')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok '{"sessionId":"__SESSION_ID__","hookEventName":"post_tool_use","toolName":"run_terminal_command","tool_input":{"command":"echo listo"},"toolInput":{"command":"pytest -q"},"toolResult":{"exit_code":0,"output_for_prompt":"ok"}}'
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  case "$(cat "$_gk_log" 2>/dev/null)" in
    *verified*) _mal "toolInput (camel) gano sobre tool_input (snake) — precedencia D4" ;;
  esac
}

# Precedencia snake de toolName: el snake trae una tool sin runner (Read) y el
# camel el nombre del runner (pytest). El snake tiene que ganar.
caso_g2_grok_precedencia_toolname_gana_snake() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit precedencia de toolName')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok '{"sessionId":"__SESSION_ID__","hookEventName":"post_tool_use","tool_name":"Read","toolName":"pytest","tool_input":{"command":"echo listo"},"toolResult":{"exit_code":0,"output_for_prompt":"ok"}}'
  LAB_GROK_HOOK_EVENT=""
  _gk_log="$(dirname "$(_grok_ruta_estado)")/harness-evidence.log"
  case "$(cat "$_gk_log" 2>/dev/null)" in
    *verified*) _mal "toolName (camel) gano sobre tool_name (snake) — precedencia D4" ;;
  esac
}

# El rol YA tiene que registrarse por los canales medidos (la ceremonia grok es
# 7.4; sin estos casos, 7.4 no tendria con que construir).
caso_g3_grok_spawn_registra_rol() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit delego')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_spawn implementer)"
  LAB_GROK_HOOK_EVENT=""
  _gk="$(_grok_ruta_estado)"
  _contiene "agents_seen con despacho spawn_subagent" "$(grep '^agents_seen=' "$_gk" 2>/dev/null)" 'implementer'
}

caso_g3_grok_interno_registra_rol() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit subagente adentro')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_interno reviewer 'echo listo')"
  LAB_GROK_HOOK_EVENT=""
  _gk="$(_grok_ruta_estado)"
  _contiene "agents_seen con evento interno (subagentType top-level)" "$(grep '^agents_seen=' "$_gk" 2>/dev/null)" 'reviewer'
}

# D4 walker — el recibo viaja en lastAssistantMessage (camel). Turno completo
# grok: arma, acredita verificacion y edicion con tools nativas, cierra con
# recibo. La ceremonia no se exige en grok hasta 7.4 (case claude|codex).
caso_g4_grok_turno_completo_camel_cierra() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit turno completo grok')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_spawn implementer)"
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  lab_run auto grok "$(lab_payload_grok_interno verifier 'npm test')"
  lab_run auto grok "$(lab_payload_grok_spawn reviewer)"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop "$_RECIBO_VINETAS" end_turn)"
  LAB_GROK_HOOK_EVENT=""
  _igual "exit del turno completo grok" "$LAB_RC" "0"
  _vacio "stdout del cierre limpio" "$LAB_OUT"
  _gk="$(_grok_ruta_estado)"
  [ -f "$_gk" ] && _mal "el cierre limpio grok no borro el estado"
}

caso_g4_grok_stop_sin_recibo_bloquea() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit turno sin recibo')"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop 'listo, entrega' end_turn)"
  LAB_GROK_HOOK_EVENT=""
  _contiene "Stop grok end_turn sin recibo bloquea (7.4: exit 0 + decision)" "$LAB_OUT" '"decision":"block"'
}

# Precedencia snake del walker: AMBOS mensajes en el payload; el snake (sin
# recibo) tiene que ganar sobre el camel (con recibo completo).
caso_g4_grok_precedencia_lastmessage_gana_snake() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit precedencia del walker')"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","hookEventName":"stop","reason":"end_turn","stopHookActive":false,"last_assistant_message":"%s","lastAssistantMessage":"%s","promptId":"p1","backgroundTasks":[],"sessionCrons":[]}' "$_TEXTO_LLANO" "$_RECIBO_VINETAS")"
  LAB_GROK_HOOK_EVENT=""
  _contiene "last_message snake gano: bloquea (7.4: exit 0 + decision)" "$LAB_OUT" '"decision":"block"'
}

# transcriptPath camel: el recibo SOLO en el transcript (canal 2), el payload
# sin lastAssistantMessage — la contencion A6 contiene ($LAB/entrada bajo el
# perfil del banco). Mitad 2: transcript_path (snake) inexistente gana sobre
# transcriptPath real -> canal muerto -> sin recibo -> bloquea.
caso_g4_grok_transcriptpath_camel() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit recibo en transcript camel')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_spawn implementer)"
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  lab_run auto grok "$(lab_payload_grok_interno verifier 'npm test')"
  lab_run auto grok "$(lab_payload_grok_spawn reviewer)"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","hookEventName":"stop","reason":"end_turn","stopHookActive":false,"promptId":"p1","backgroundTasks":[],"sessionCrons":[]}' "$(lab_transcript_asistente "$_RECIBO_VINETAS")"
  LAB_GROK_HOOK_EVENT=""
  _igual "cierre con recibo solo en transcript camel" "$LAB_RC" "0"

  lab_limpiar_estado
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit precedencia transcript')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok '{"sessionId":"__SESSION_ID__","transcript_path":"/no/existe/transcript.jsonl","transcriptPath":"__TRANSCRIPT__","hookEventName":"stop","reason":"end_turn","stopHookActive":false,"lastAssistantMessage":"'"$_TEXTO_LLANO"'","promptId":"p1","backgroundTasks":[],"sessionCrons":[]}' "$(lab_transcript_asistente "$_RECIBO_VINETAS")"
  LAB_GROK_HOOK_EVENT=""
  _contiene "transcript snake gano: bloquea (7.4: exit 0 + decision)" "$LAB_OUT" '"decision":"block"'
}

# ============================== Task 7.4: ceremonia Grok (D3) ================
# La secuencia implementer->verifier->reviewer se exige en TARGET=grok (7.1
# midio el rol por tres canales y el env map entrega TARGET=grok). El bloqueo
# viaja con decision:block + exit 0 (7.2: exit 2 es IGNORADO en Grok) y el
# contrato viaja adosado al reason del bloqueo (additionalContext ignorado,
# la re-planificacion que 7.2 decidio). El budget usa la forma default
# (continue:false + exit 0), que es la aceptada — sin cambio.

# Caso que PASA: ceremonia completa en grok cierra limpio.
caso_g3_grok_ceremonia_completa_cierra() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit turno con ceremonia')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_spawn implementer)"
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  lab_run auto grok "$(lab_payload_grok_interno verifier 'npm test')"
  lab_run auto grok "$(lab_payload_grok_spawn reviewer)"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop "$_RECIBO_VINETAS" end_turn)"
  LAB_GROK_HOOK_EVENT=""
  _igual "ceremonia completa grok cierra" "$LAB_RC" "0"
  _gk="$(_grok_ruta_estado)"
  [ -f "$_gk" ] && _mal "el cierre con ceremonia completa no borro el estado"
}

# Caso que BLOQUEA (el catch de mut_ceremonia_sin_grok): sin despachar
# verifier/reviewer, el Stop bloquea con la forma grok (exit 0 + decision:block
# + el contrato en el reason — la re-planificacion del armado de 7.2).
caso_g3_grok_ceremonia_incompleta_bloquea() {
  LAB_GROK_HOOK_EVENT=user_prompt_submit
  lab_run auto grok "$(lab_payload_grok_prompt '-saikit ceremonia incompleta')"
  LAB_GROK_HOOK_EVENT=post_tool_use
  lab_run auto grok "$(lab_payload_grok_spawn implementer)"
  lab_run auto grok "$(lab_payload_grok_bash 'pytest -q' 0)"
  lab_run auto grok "$(lab_payload_grok_edit '/proyecto/src/sesion.py')"
  LAB_GROK_HOOK_EVENT=stop
  lab_run auto grok "$(lab_payload_grok_stop "$_RECIBO_VINETAS" end_turn)"
  LAB_GROK_HOOK_EVENT=""
  _igual "bloqueo grok con exit 0 (exit 2 es ignorado, 7.2)" "$LAB_RC" "0"
  _contiene "bloqueo grok con decision:block" "$LAB_OUT" '"decision":"block"'
  _contiene "el motivo nombra al verifier faltante" "$LAB_ERR" 'Missing verifier'
  _contiene "el contrato viaja en el bloqueo (reason, 7.2)" "$LAB_OUT" 'SUMMONAIKIT HARNESS RECEIPT'
}

# Prueba negativa: SIN TARGET=grok la rama no aplica. Un Stop de cursor con la
# misma forma de estado NO exige secuencia (regresion: si grok se prendiera en
# cualquier host, el gate de cursor volveria a falsos bloqueos).
caso_g3_grok_ceremonia_no_corre_en_cursor() {
  lab_run prompt cursor "$(lab_payload_prompt '-saikit turno de cursor')"
  lab_run tool cursor "$(lab_payload_edit '/proyecto/src/x.ts')"
  lab_run tool cursor "$(lab_payload_bash 'pytest -q')"
  lab_run stop cursor "$(lab_payload_stop "$_RECIBO_VINETAS")"
  _igual "cursor sin ceremonia cierra (la rama grok no se filtra)" "$LAB_RC" "0"
}


# --------------------------------------------------------------------- indice
# Un caso que no este en ninguna lista NO CORRE. La bateria de comportamiento
# verifica que no haya huerfanos; sin ese chequeo, un caso podria quedar fuera
# por un dedazo y nadie se enteraria.
GATES="LAB G1 G2 G3 G4 G5 G6"

casos_de_gate() { eval "printf '%s' \"\${CASOS_$1}\""; }

todos_los_casos() {
  for g in $GATES; do casos_de_gate "$g"; printf ' '; done
}
