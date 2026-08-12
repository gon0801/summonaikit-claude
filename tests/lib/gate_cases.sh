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
#   caso_g3_agent_type_no_cuenta        A9 — el rol del subagente viaja en
#                                       `agent_type` y el hook no lo mira.
#   caso_g2_runner_fallido_forma_real   A11 — el guardia de fallas busca un
#                                       `exitCode` que el payload real no trae.
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

# Recibo donde Verify termina con "pytest." (punto final de frase). Sin la
# alternativa de punto-de-frase en TEST_RUNNER_WORD_RE, el punto despues de
# `pytest` lo excluye y el gate reclama evidencia que esta. Es el test de la
# CORRECCION 2 del plan de la 3.3: el wrapper se aplica a DOS superficies
# (comando y prosa) y un punto al final de una oracion NO es una extension.
_RECIBO_SIN_RETRO_PYTEST_PUNTO='SUMMONAIKIT HARNESS RECEIPT\n- Understand: pediste poder listar las sesiones abiertas.\n- Implement: se agrego el endpoint y su ruta.\n- Verify: se corrio pytest.\n- Review: sin hallazgos.\n- Close: entregado; no se toco codigo despues de la revision.'

_TEXTO_LLANO='Ya quedo el endpoint de sesiones. Avisame si querias otra cosa.'
_TEXTO_PAUSA='Necesito saber que datos van en la lista.\n\nSUMMONAIKIT HARNESS PAUSED - awaiting your answer'

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
CASOS_G1="caso_g1_no_arma_sin_sentinel caso_g1_arma_con_sentinel caso_g1_sentinel_con_frontera caso_g1_dos_sesiones_no_comparten_estado caso_g1_prompt_sin_sentinel_desarma caso_g1_correccion_al_vuelo_no_desarma caso_g1_session_id_anidado_no_reescribe_ruta"

# El bug del vendor que el parche del sentinel existe para tapar: "cualquier"
# contiene "ui", asi que su regex de palabras clave armaba el harness solo.
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
}

# DEFECTO A4 (clausula 1) — cerrado por la Task 3.4. Antes el estado se llaveaba
# solo por proyecto, asi que dos sesiones del mismo repo compartian un solo
# harness-state.env: un turno -saikit abandonado en una cobraba recibo a la otra.
# Ahora se llavea por proyecto Y sesion (session_id viaja en cada payload).
#
# DOS mitades, como pide la revision (CORRECCION 10): no basta con "B no ve el
# estado de A" — un hook que borrara TODO pasaria esa sola mitad. La otra ata que
# el estado de A sobrevive intacto al turno de B.
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

# ============================================ G2 — evidencia de verificacion
CASOS_G2="caso_g2_runner_marca_verificado caso_g2_sin_runner_no_marca caso_g2_runner_no_encontrado_no_marca caso_g2_runner_fallido_forma_real caso_g2_sin_armar_no_crea_estado caso_g2_falta_evidencia_reclama caso_g2_evidencia_presente_no_reclama caso_g2_excusa_declarada_no_reclama caso_g2_runner_en_path_no_marca caso_g2_runner_con_ruta_marca caso_g2_excusa_con_punto_final_no_reclama caso_g2_credenciales_en_comando_se_redactan caso_g2_comando_sin_credenciales_no_se_altera caso_g2_credenciales_en_ruta_de_edicion_se_redactan caso_g2_credencial_entrecomillada_se_redacta_entera"

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

# DEFECTO A11, medido con la captura de la Task 1.4 y grabado a proposito.
#
# El guardia de fallas del hook busca `exitCode[^0-9]*[1-9]` en el payload. El
# tool_response real de Bash NO TIENE ese campo: su forma es
# stdout/stderr/interrupted/isImage/noOutputExpected, medida en 59 de 59
# payloads. O sea que la bateria puede fallar en rojo y el gate igual la acredita
# como verificacion, salvo que el texto del error diga justo una de las tres
# frases que quedan ("command not found", "permission_denied", "failure_type").
#
# Una bateria que falla con un assert normal no dice ninguna de las tres.
caso_g2_runner_fallido_forma_real() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash 'npm test' 'AssertionError: expected true to equal false')"
  _igual "verified pese a que la bateria fallo (A11)" "$(lab_estado verified)" "1"
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

# ============================================== G3 — secuencia de subagentes
CASOS_G3="caso_g3_falta_reviewer_bloquea caso_g3_fuera_de_orden_bloquea caso_g3_cursor_no_exige_secuencia caso_g3_agente_generico_no_cuenta caso_g3_agent_type_no_cuenta caso_g3_gana_el_de_tool_input_no_el_ultimo caso_g3_eco_fuera_de_tool_input_no_cuenta caso_g3_nombres_del_host_mapean caso_g3_turno_completo_por_eventos_permite"

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

# DEFECTO A9, medido con la captura de la Task 1.4 y grabado a proposito.
#
# Los eventos de ADENTRO de un subagente llevan el rol en `agent_type` de primer
# nivel (281 de 303 payloads reales). El hook busca `subagent_type`, asi que no
# lo ve: el implementer puede correr, editar archivos y dejar su rastro en cada
# payload, y el gate igual reclama que no corrio.
#
# Va junto con lo otro que midio la captura: la herramienta que INVOCA
# subagentes se llama `Agent`, y el matcher registrado nombra `Task`, asi que
# esos eventos no llegan nunca. Entre las dos cosas, el gate de secuencia no
# tiene forma de satisfacerse. El escenario 16 de la linea base graba el turno
# completo; este caso graba la pieza suelta.
caso_g3_agent_type_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'implementer' 'npm test')"
  _igual "agents_seen con agent_type=implementer (A9)" "$(lab_estado agents_seen)" ""
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
CASOS_G4="caso_g4_pausa_permite caso_g4_pausa_en_resultado_bloquea caso_g4_pausa_en_thinking_no_cuenta caso_g4_etiqueta_pegada_no_cuenta caso_g4_recibo_corrido_pasa_a8 caso_g4_recibo_dos_bloques_pasa caso_g4_falta_una_etiqueta_bloquea caso_g4_sin_recibo_bloquea caso_g4_recibo_en_vinetas_pasa caso_g4_recibo_corrido_solo_en_transcript_pasa caso_g4_recibo_solo_en_transcript_pasa"

# La pausa declarada es una forma valida de terminar el turno: el agente
# pregunto y espera. Se acepta sin recibo, sin evidencia y sin subagentes.
# Nota grabada: por esta via el estado NO se borra (el turno sigue abierto a
# proposito). Es la mitad buena de A2; la mitad mala — que la pausa se encuentre
# adentro del resultado de una herramienta — la cierra la Task 3.2.
caso_g4_pausa_permite() {
  lab_sembrar 123456 0 0 0 ""
  lab_run stop claude "$(lab_payload_stop "$_TEXTO_PAUSA")"
  _igual "exit code" "$LAB_RC" "0"
  _vacio "stdout" "$LAB_OUT"
  if ! lab_hay_estado; then _mal "la pausa no cierra el turno: el estado tiene que seguir ahi"; fi
}

# DEFECTO A2, la mitad mala: la cadena de pausa aparece SOLO adentro del
# `content` de un `tool_result` en el transcript — un mensaje `user`, no
# `assistant`. El asistente nunca la escribio; hoy el grep crudo sobre el tail la
# encuentra y el gate deja pasar. La Task 3.2 cierra esto: el walker ignora todo
# texto que no sea de un mensaje assistant, y la pausa aqui vive en uno user.
# Es el caso que habria atrapado A2. Estado NO borrado: el turno sigue abierto.
caso_g4_pausa_en_resultado_bloquea() {
  _sembrar_turno_completo
  lab_run stop claude "$(lab_payload_stop 'Ya lo cambie.')" "$(lab_transcript_pausa_en_resultado)"
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
  lab_run stop claude "$(lab_payload_stop 'Ya lo cambie.')" "$(lab_transcript_thinking_con_pausa)"
  _igual "exit code" "$LAB_RC" "2"
  _contiene "motivo" "$LAB_OUT" 'Missing SUMMONAIKIT HARNESS RECEIPT'
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

# ================================================ G5 — presupuesto de 2 ciclos
CASOS_G5="caso_g5_presupuesto_agotado caso_g5_ciclos_cuentan_y_bloquean caso_g5_ciclo_consumido_no_impide_cerrar caso_g5_agotado_limpia_estado"

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

# ========================================== G6 — salidas por target y por fase
CASOS_G6="caso_g6_bloqueo_por_target caso_g6_permiso_por_target caso_g6_presupuesto_agotado_por_target caso_g6_armado_por_target"

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

# --------------------------------------------------------------------- indice
# Un caso que no este en ninguna lista NO CORRE. La bateria de comportamiento
# verifica que no haya huerfanos; sin ese chequeo, un caso podria quedar fuera
# por un dedazo y nadie se enteraria.
GATES="LAB G1 G2 G3 G4 G5 G6"

casos_de_gate() { eval "printf '%s' \"\${CASOS_$1}\""; }

todos_los_casos() {
  for g in $GATES; do casos_de_gate "$g"; printf ' '; done
}
