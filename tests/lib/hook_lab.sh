#!/usr/bin/env bash
# hook_lab.sh — banco de pruebas de UN hook, paso a paso (Task 1.3).
#
# El arnes de la Task 1.2 (`tools/golden-harness.sh`) GRABA lo que el hook hace
# contra escenarios enteros: detecta que algo cambio, pero no dice que semantica
# se rompio. Esta lib es la otra mitad: correr un paso suelto y poder AFIRMAR
# algo puntual sobre el resultado ("sin sentinel no se crea estado"). Las dos se
# necesitan; ninguna reemplaza a la otra.
#
# Reglas que hereda del arnes, por los mismos motivos:
#
#   - EL HOOK SE COPIA AL BANCO Y SE CORRE AHI, nunca en su lugar: deriva su
#     directorio de estado de `dirname $0`, asi que correrlo donde vive
#     escribiria sobre el estado VIVO del gate en cada corrida de la bateria.
#   - HOME, USERPROFILE y el temporal quedan adentro del banco (Core Rule 4).
#
# Decision de costo que explica el resto del archivo: en Windows cada corrida
# del hook cuesta ~2 segundos (el hook lanza decenas de subprocesos por evento).
# Manejar cada caso del Stop gate por eventos reales — armar, tres Task, un
# runner, y recien ahi el Stop — serian 6 corridas por caso. Por eso el banco
# sabe SEMBRAR el estado directo (`lab_sembrar`): el Stop gate decide leyendo
# ese archivo, asi que un caso enfocado cuesta 1 corrida en vez de 6. La
# cobertura de que los eventos PRODUCEN ese estado no se pierde: vive en el caso
# de extremo a extremo (`caso_g3_turno_completo_por_eventos_permite`), que si lo
# maneja todo por eventos.
#
# La ruta del estado NO se recalcula: se DESCUBRE armando un turno y mirando donde
# quedo. Hoy depende del proyecto Y de la sesion (Task 3.4 / A4), asi que dos
# sesiones del mismo repo dejan estado en rutas distintas — pero el banco sigue
# sin asumir el esquema: lo probea. Recalcularla seria adivinar — si el hook
# cambiara de esquema, los casos sembrados escribirian en un archivo que nadie lee
# y quedarian verdes por vacio. Por eso `lab_init` Y `lab_hook_swap` re-descubren
# la ruta despues de cada cambio de hook (sin eso, un mutante que aplana la ruta
# deja el LAB_ESTADO_PATH cacheado apuntando al hoyo y acredita el caso equivocado).
#
# API:
#   lab_init [HOOK]      crea el banco y copia el hook (def: $HOOK_BAJO_PRUEBA)
#   lab_hook_swap HOOK   cambia el hook bajo prueba sin rehacer el banco
#   lab_fin              borra el banco
#   lab_run FASE TARGET PAYLOAD [TRANSCRIPT]
#                        corre un paso y deja LAB_RC / LAB_OUT / LAB_ERR.
#                        FASE o TARGET en "auto" => esa variable NO se exporta
#                        (caso real: el registro no las pone y el hook deriva la
#                        fase del payload). El token __TRANSCRIPT__ del payload
#                        se sustituye por la ruta del transcript; sin TRANSCRIPT
#                        apunta a un archivo inexistente, que tambien es un caso
#                        real (transcript ilegible => tail vacio).
#   lab_sembrar HASH CICLO IMPL VERIF AGENTES   escribe el estado directo
#   lab_limpiar_estado   borra todo lo que el hook dejo en disco: turno nuevo
#   lab_hay_estado       exit 0 si existe el archivo de estado
#   lab_estado CLAVE     valor de esa clave del estado ('' si no hay)
#   lab_log              contenido del harness-evidence.log
#
# Constructores de payload (la forma sale de payloads reales; ver
# tests/fixtures/README.md):
#   lab_payload_prompt TEXTO
#   lab_payload_session TEXTO
#   lab_payload_task SUBAGENTE
#   lab_payload_bash COMANDO EXITCODE
#   lab_payload_edit RUTA
#   lab_payload_stop
#   lab_transcript_asistente TEXTO   (los saltos van escapados como \n, igual
#                                     que en un JSONL real — de ahi sale A8)

# --------------------------------------------------------------- ciclo de vida
lab_init() {
  lab_hook_origen="${1:-${HOOK_BAJO_PRUEBA:-}}"
  if [ -z "$lab_hook_origen" ] || [ ! -r "$lab_hook_origen" ]; then
    printf 'hook_lab: no hay hook legible que ejercitar: %s\n' "$lab_hook_origen" >&2
    return 1
  fi
  LAB="$(mktemp -d "${TMPDIR:-/tmp}/saikit-lab-XXXXXX")" || return 1
  mkdir -p "$LAB/hooks/state" "$LAB/proyecto" "$LAB/home" "$LAB/entrada" || return 1
  LAB_PASO=0
  LAB_RC=""; LAB_OUT=""; LAB_ERR=""
  cp "$lab_hook_origen" "$LAB/hooks/summonaikit-harness.sh" || return 1

  lab_run prompt claude "$(lab_payload_prompt '-saikit descubrimiento de la ruta de estado')"
  LAB_ESTADO_PATH="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  if [ -z "$LAB_ESTADO_PATH" ]; then
    printf 'hook_lab: el hook no dejo estado al armar un turno con sentinel.\n' >&2
    printf '          El banco no puede sembrar estado a ciegas; se detiene.\n' >&2
    return 1
  fi
  lab_limpiar_estado
}

# Cambia el archivo bajo prueba conservando el banco, y RE-DESCUBRE la ruta de
# estado para el hook recien puesto. Lo usa la bateria de mutaciones: un mutante
# puede cambiar el esquema de la ruta (p.ej. `mut_session_sin_llave` la aplana un
# nivel), y si el banco conservara la ruta cacheada del hook sano, `lab_hay_estado`
# miraria al hoyo y el caso se pondria rojo por la razon equivocada — acreditando
# la mutacion a un caso anterior en vez del suyo. Re-descubrir lo arregla.
#
# Si el probe no halla estado (un mutante que rompe el armado del todo, que los
# hay) NO se aborta como hace `lab_init`: se conserva la ruta anterior y se deja
# que el caso se ponga rojo, que es justo lo que la bateria viene a comprobar.
lab_hook_swap() {
  cp "$1" "$LAB/hooks/summonaikit-harness.sh" || return 1
  lab_limpiar_estado
  lab_run prompt claude "$(lab_payload_prompt '-saikit descubrimiento de ruta tras swap')"
  _swap_path="$(find "$LAB/hooks/state" -type f -name harness-state.env 2>/dev/null | head -n 1)"
  if [ -n "$_swap_path" ]; then
    LAB_ESTADO_PATH="$_swap_path"
  fi
  lab_limpiar_estado
}

lab_fin() {
  if [ -n "${LAB:-}" ] && [ -d "$LAB" ]; then rm -rf "$LAB"; fi
  return 0
}

# ------------------------------------------------------------------- ejecucion
lab_run() {
  lab_fase="$1"; lab_target="$2"; lab_payload="$3"; lab_transcript="${4:-}"
  LAB_PASO=$((LAB_PASO + 1))

  lab_tr="$LAB/entrada/transcript-inexistente-$LAB_PASO.jsonl"
  if [ -n "$lab_transcript" ]; then
    lab_tr="$LAB/entrada/transcript-$LAB_PASO.jsonl"
    printf '%s\n' "$lab_transcript" > "$lab_tr"
  fi

  lab_entrada="$LAB/entrada/paso-$LAB_PASO.json"
  lab_sid="${LAB_SESSION_ID:-$LAB_SESION_DEF}"
  printf '%s' "$lab_payload" | sed "s|__TRANSCRIPT__|$lab_tr|g; s|__SESSION_ID__|$lab_sid|g" > "$lab_entrada"

  lab_cmd=(env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE -u SUMMONAIKIT_HOOK_TARGET
           -u CLAUDECODE -u ZCODE_SESSION_ID -u ZCODE_PROJECT_DIR
           -u GROK_HOOK_EVENT -u GROK_SESSION_ID -u GROK_WORKSPACE_ROOT
           HOME="$LAB/home" USERPROFILE="$LAB/home")
  [ "$lab_fase" != "auto" ]   && lab_cmd+=(SUMMONAIKIT_HOOK_PHASE="$lab_fase")
  [ "$lab_target" != "auto" ] && lab_cmd+=(SUMMONAIKIT_HOOK_TARGET="$lab_target")
  # CLAUDECODE solo lo repone el caso que lo pide (A10/Task 3.7): el default es
  # ausente, asi el lab es determinista aunque la suite corra adentro de Claude
  # Code (que setea CLAUDECODE=1). Sin esto, el fallback de A10 resolveria
  # TARGET=claude en cualquier caso con target=auto y los tests no probarian lo
  # que creen. Expansion segura bajo set -u (CORRECCION 17 del plan).
  [ -n "${LAB_CLAUDECODE:-}" ] && lab_cmd+=(CLAUDECODE="$LAB_CLAUDECODE")
  [ -n "${LAB_ZCODE_SESSION_ID:-}" ]  && lab_cmd+=(ZCODE_SESSION_ID="$LAB_ZCODE_SESSION_ID")
  [ -n "${LAB_ZCODE_PROJECT_DIR:-}" ] && lab_cmd+=(ZCODE_PROJECT_DIR="$LAB_ZCODE_PROJECT_DIR")
  # Task 7.3: mismo determinismo para Grok. GROK_HOOK_EVENT la inyecta el runner
  # de hooks de Grok (senal de host D2); sin unsetearla, la suite corriendo
  # DENTRO de un Grok hijo heredaria la senal del runner padre y todo el lab
  # resolveria HOST=grok. Solo el caso que la pide via LAB_GROK_*.
  [ -n "${LAB_GROK_HOOK_EVENT:-}" ]    && lab_cmd+=(GROK_HOOK_EVENT="$LAB_GROK_HOOK_EVENT")
  [ -n "${LAB_GROK_SESSION_ID:-}" ]    && lab_cmd+=(GROK_SESSION_ID="$LAB_GROK_SESSION_ID")
  [ -n "${LAB_GROK_WORKSPACE_ROOT:-}" ] && lab_cmd+=(GROK_WORKSPACE_ROOT="$LAB_GROK_WORKSPACE_ROOT")
  # Task 5.3: ZCODE_SESSION_ID / ZCODE_PROJECT_DIR son la senal de host de zcode
  # (medido Task 5.1: las inyecta el host, no el comando registrado). Mismo
  # determinismo que CLAUDECODE: el lab las unsetea SIEMPRE y solo las repone el
  # caso que las pide via LAB_ZCODE_*. Sin esto, si la suite corre DENTRO de
  # zcode, el lado "Claude" (LAB_CLAUDECODE=1) hereda ZCODE_* del env padre y
  # ambos hosts salen HOST=zcode (cross-review codex r1, hallazgo 1).

  ( cd "$LAB/proyecto" && "${lab_cmd[@]}" bash "$LAB/hooks/summonaikit-harness.sh" ) \
    < "$lab_entrada" > "$LAB/.out" 2> "$LAB/.err"
  LAB_RC=$?
  LAB_OUT="$(cat "$LAB/.out")"
  LAB_ERR="$(cat "$LAB/.err")"
  return 0
}

# ----------------------------------------------------------------------- estado
lab_limpiar_estado() {
  [ -n "${LAB:-}" ] || return 0
  rm -rf "$LAB/hooks/state" 2>/dev/null || true
  mkdir -p "$LAB/hooks/state" 2>/dev/null || true
  return 0
}

lab_sembrar() {
  mkdir -p "$(dirname "$LAB_ESTADO_PATH")" 2>/dev/null || true
  {
    printf 'task_hash=%s\n' "$1"
    printf 'cycle=%s\n' "$2"
    printf 'implemented=%s\n' "$3"
    printf 'verified=%s\n' "$4"
    printf 'agents_seen=%s\n' "$5"
  } > "$LAB_ESTADO_PATH"
}

lab_hay_estado() { [ -f "$LAB_ESTADO_PATH" ]; }

lab_estado() {
  [ -f "$LAB_ESTADO_PATH" ] || return 0
  grep "^$1=" "$LAB_ESTADO_PATH" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

lab_log() {
  lab_log_f="$(dirname "$LAB_ESTADO_PATH")/harness-evidence.log"
  [ -f "$lab_log_f" ] || return 0
  cat "$lab_log_f"
}

# ------------------------------------------------------- payloads y transcripts
# Forma CALCADA de la captura de la Task 1.4 (308 payloads reales): mismos
# campos, mismo orden de claves, mismos nombres de herramienta. El hook no
# parsea JSON — usa `sed` sobre el texto crudo — asi que la forma no es un
# detalle cosmetico: de ella dependen los greps de todos los gates.
#
# session_id va como marcador __SESSION_ID__ y lo sustituye `lab_run` (mismo
# mecanismo que __TRANSCRIPT__). Un caso puede correr dos sesiones del mismo
# repo cambiando LAB_SESSION_ID entre llamadas (Task 3.4 / A4: dos sesiones no
# comparten estado). El default es el UUID que usaba el lab antes del cambio,
# para que los casos existentes sigan sin saber nada de sesiones.
LAB_SESION_DEF="c1a70000-1111-4222-8333-444455556666"
lab_payload_prompt() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}

# Task 9.4 (C9): un UserPromptSubmit SIN campo `prompt`, con el sentinel en OTRO
# campo del payload. Es la forma de un resume: el texto viejo viaja en un campo
# de resumen, no en una peticion del usuario. Con el fallback al payload crudo
# sin acotar, ese texto armaba la ceremonia entera sin que nadie la pidiera.
lab_payload_prompt_sin_campo() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","hook_event_name":"UserPromptSubmit","resumen_previo":"%s"}' "$1"
}

# El payload de SessionStart NO trae campo `prompt`: el hook cae al INPUT entero
# como texto del prompt. Por eso el sentinel, si aparece, aparece en otro campo
# (un resumen de sesion reanudada, por ejemplo).
# Declarado: esta fase NO se capturo en la Task 1.4 (el capturador registra las
# 3 fases que nombra su DoD), asi que su forma sigue siendo reconstruida.
lab_payload_session() {
  printf '{"session_id":"__SESSION_ID__","hook_event_name":"SessionStart","source":"resume","cwd":"/proyecto","summary":"%s"}' "$1"
}

# La herramienta que invoca subagentes se llama `Agent`, no `Task` (medido: los
# 8 payloads reales con subagent_type son todos tool_name=Agent).
lab_payload_agent() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"paso del harness","prompt":"hace lo tuyo","subagent_type":"%s","run_in_background":false},"tool_response":{"status":"completed","agentType":"%s","content":"listo","resolvedModel":"claude-opus-5"},"tool_use_id":"toolu_01a1b2c3d4e5f60718293a4b","duration_ms":4200}' "$1" "$1"
}

# DEFECTO A1 — el vector MEDIDO (escenario 12, paso 03): `subagent_type` como
# CLAVE JSON REAL fuera de `tool_input`. Ningun subagente corrio; el campo viaja
# adentro del resultado de la herramienta, o sea texto que el turno no escribio.
# Ojo con el vector que el spec describia y NO reproduce: el CONTENIDO de un
# archivo que mencione el campo llega con las comillas escapadas, y ahi no hay
# clave que leer.
lab_payload_eco_subagent_type() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/proyecto/docs/nota.md"},"tool_response":{"type":"text","eco_del_host":{"subagent_type":"%s"}},"tool_use_id":"toolu_01e5f60718293a4b5c6d7e8f","duration_ms":1200}' "$1"
}

# Las dos ocurrencias a la vez, y el eco DESPUES de `tool_input`: es la forma
# exacta en que el lector greedy pierde. Su `sed` arranca con `.*`, asi que se
# queda con la ULTIMA — no solo inventa un rol, BORRA el legitimo.
lab_payload_agent_con_eco() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"paso del harness","prompt":"hace lo tuyo","subagent_type":"%s","run_in_background":false},"tool_response":{"status":"completed","agentType":"%s","content":"listo","eco_del_host":{"subagent_type":"%s"},"resolvedModel":"claude-opus-5"},"tool_use_id":"toolu_01f60718293a4b5c6d7e8f90","duration_ms":4200}' "$1" "$1" "$2"
}

# El tool_response real de Bash NO trae exitCode (0 de 59 payloads): la unica
# senal de falla posible es el TEXTO de stdout/stderr. El segundo argumento es
# ese stderr. Desde la Task 3.8 el hook grepea patrones reales de fracaso sobre
# ese texto (dos regex CI/CS en FAILURE_SIGNAL_RE_*); por eso los casos
# caso_g2_runner_fallido_* usan stderrs con la forma real de cada runner.
lab_payload_bash() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"paso del turno"},"tool_response":{"stdout":"salida","stderr":"%s","interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01b2c3d4e5f60718293a4b5c","duration_ms":1200}' "$1" "${2:-}"
}

# C3 (auditoria 2026-08-13) — un evento Bash cuyo tool_response trae una clave
# "command" PROPIA (eco del host, texto que el turno no escribio). El turno solo
# corrio $1; $2 viaja adentro del resultado. Gemelo de lab_payload_eco_subagent_type
# para command: el lector greedy tomaba la ULTIMA ocurrencia y acreditaba
# verified=1 por un comando que nunca corrio.
lab_payload_bash_con_eco_command() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"paso del turno"},"tool_response":{"stdout":"salida","stderr":"","eco_del_host":{"command":"%s"},"interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01c9d0e1f2a3b4c5d6e7f809","duration_ms":1200}' "$1" "$2"
}

# C3, gemelo para tool_name — el eco viaja como clave "tool_name" adentro de
# tool_response. Con el lector greedy (ultima ocurrencia gana), ese eco pisaba
# LA herramienta del evento y "$tool_name $command_text" acreditaba verified=1
# sin runner alguno en el comando real.
lab_payload_bash_con_eco_tool_name() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"paso del turno"},"tool_response":{"stdout":"salida","stderr":"","eco_del_host":{"tool_name":"%s"},"interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01d0e1f2a3b4c5d6e7f8091a","duration_ms":1200}' "$1" "$2"
}

# Un evento de ADENTRO de un subagente: el rol viaja en `agent_type` de primer
# nivel. 281 de 303 payloads reales son de esta forma.
lab_payload_bash_en_subagente() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","agent_id":"a11111111impleme","agent_type":"%s","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"paso del turno"},"tool_response":{"stdout":"salida","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"tool_use_id":"toolu_01c3d4e5f60718293a4b5c6d","duration_ms":1200}' "$1" "$2"
}

# Una delegacion ANIDADA: evento Agent (tool_name=Agent) que a la vez trae
# tool_input.subagent_type (el rol del hijo) y agent_type de primer nivel (el
# rol del subagente PADRE que lo invoca). Es la forma real de una delegacion
# dentro de un subagente. Sirve para afirmar que subagent_type gana sobre
# agent_type cuando ambos estan (A9 es fallback, CORRECCION 6 del plan).
# Args: $1 = subagent_type (hijo), $2 = agent_type top-level (padre).
lab_payload_agent_anidado() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","agent_type":"%s","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"delegacion anidada","prompt":"hace lo tuyo","subagent_type":"%s","run_in_background":false},"tool_response":{"status":"completed","agentType":"%s","content":"listo","resolvedModel":"claude-opus-5"},"tool_use_id":"toolu_01a7b8c9d0e1f2a3b4c5d6e7","duration_ms":4200}' "$2" "$1" "$1"
}

lab_payload_edit() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b","replace_all":false},"tool_response":{"filePath":"%s","oldString":"a","newString":"b","originalFile":"a","structuredPatch":[],"userModified":false,"replaceAll":false},"tool_use_id":"toolu_01d4e5f60718293a4b5c6d7e","duration_ms":1200}' "$1" "$1"
}

# El Stop real trae `last_assistant_message`: el texto final del asistente viaja
# en el PROPIO payload, no solo en el transcript. O sea que el recibo y la pausa
# tienen DOS canales, y el gate mira los dos (INPUT + tail del transcript).
lab_payload_stop() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[],"session_crons":[]}' "${1:-Listo.}"
}

# Un Stop SIN last_assistant_message (Task 8.2): la forma que obliga al gate a
# caer al canal transcript. OJO: lab_payload_stop '' NO sirve para esto — su
# "${1:-Listo.}" trata el vacio como ausente y mete "Listo.", y con el campo
# presente la escotilla ya no cae al fallback.
lab_payload_stop_sin_mensaje() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-444455556666","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[],"session_crons":[]}'
}

# ------------------------------- Task 7.3: envelope Grok Build (medido 7.1)
# Claves camel (sessionId, toolName, toolInput, transcriptPath,
# lastAssistantMessage), valor del evento SNAKE (user_prompt_submit,
# post_tool_use, stop). El prompt del usuario llega WRAPPEADO en
# <user_query>...</user_query> (el de subagente llega pelado). Las senales de
# host van por env en el caso (LAB_GROK_HOOK_EVENT, como LAB_ZCODE_*):
# GROK_HOOK_EVENT la inyecta el runner de Grok, no el payload.

lab_payload_grok_prompt() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"user_prompt_submit","prompt":"<user_query>\\n%s\\n</user_query>"}' "$1"
}

# run_terminal_command: la tool de shell nativa. $1 = comando, $2 = exit_code
# del toolResult (0 por defecto). La falla de un comando viaja en
# toolResult.exit_code (medido 7.1; PostToolUseFailure no dispara en 1.0.3).
lab_payload_grok_bash() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"post_tool_use","toolName":"run_terminal_command","toolInput":{"command":"%s","description":"paso del turno"},"toolResult":{"exit_code":%s,"output_for_prompt":"salida"},"toolUseId":"tu-gk-01","isBackgrounded":false}' "$1" "${2:-0}"
}

# search_replace: UNA de las dos tools de edicion nativas (la otra es write,
# minúscula, ya cubierta por el alias Write del matcher). $2 permite sembrar la
# variante de error medida ("NoMatchesFound" a primer nivel del toolResult).
lab_payload_grok_edit() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"post_tool_use","toolName":"search_replace","toolInput":{"file_path":"%s","old_string":"a","new_string":"b"},"toolResult":{"type":"SearchReplace"%s},"toolUseId":"tu-gk-02","isBackgrounded":false}' "$1" "${2:+,\"${2}\":{}}"
}

# El DESPACHO de subagente: spawn_subagent SI emite post_tool_use (a diferencia
# de Codex) y el rol viaja en toolInput.subagent_type — clave interna snake
# bajo padre camel (forma medida 7.1 ronda 5).
lab_payload_grok_spawn() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"post_tool_use","toolName":"spawn_subagent","toolInput":{"prompt":"hace lo tuyo","description":"paso del harness","subagent_type":"%s","background":false},"toolResult":{"ok":true},"toolUseId":"tu-gk-03","isBackgrounded":false}' "$1"
}

# Un evento INTERNO de un subagente de Grok: el rol viaja en subagentType de
# PRIMER nivel (canal 3 medido en 7.1; el analogo Claude es agent_type/A9).
lab_payload_grok_interno() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"post_tool_use","subagentId":"sub-impl-1","subagentType":"%s","description":"hijo","toolName":"run_terminal_command","toolInput":{"command":"%s","description":"paso del hijo"},"toolResult":{"exit_code":0,"output_for_prompt":"ok"},"toolUseId":"tu-gk-04","isBackgrounded":false}' "$1" "$2"
}

# Stop Grok: $1 = lastAssistantMessage, $2 = reason (end_turn = turno;
# shutdown = cierre del proceso; medidos 5/5 pares en headless).
lab_payload_grok_stop() {
  printf '{"sessionId":"__SESSION_ID__","transcriptPath":"__TRANSCRIPT__","cwd":"/proyecto","workspaceRoot":"/proyecto","permissionMode":"bypassPermissions","hookEventName":"stop","reason":"%s","stopHookActive":false,"lastAssistantMessage":"%s","promptId":"p-gk-1","backgroundTasks":[],"sessionCrons":[]}' "${2:-end_turn}" "$1"
}

# Task 5.4: un Stop realista de zcode trae SOLO hookEventName (camel), no
# hook_event_name (5.1 midio ambos; 5.2 midio camel-only). Para probar que el
# hook detecta PHASE=stop igual (sin caer a "tool" y perder el stop_gate).
lab_payload_stop_camel() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hookEventName":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[],"session_crons":[]}' "${1:-Listo.}"
}

# Un Stop cuya session_crons trae su PROPIO session_id (anidado, depth>1), distinto
# del de primer nivel. Caso de regresion para la proteccion depth==1 de
# json_top_level_string (Task 3.4 / A4, CORRECCION 2): una vuelta al lector greedy
# `.*` tomaria el anidado como el de la sesion y re-llavearia la ruta a mitad de
# turno, con lo que el Stop buscaba estado en otra ruta y dejaba pasar. No esta
# confirmado en la captura de la 1.4 que session_crons traiga session_id; el caso
# ATA la proteccion preventiva, igual que los casos A1 atan la de tool_input.
lab_payload_stop_con_cron_intruso() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[],"session_crons":[{"id":"cron-x","session_id":"intruso-NO-es-la-sesion"}]}' "${1:-cierre.}"
}

# Para el caso A6 (Task 3.6): un payload de Stop cuyo transcript_path es una ruta
# LITERAL (no el token __TRANSCRIPT__), asi lab_run no la reescribe. Sirve para
# apuntar el transcript a un archivo fuera del perfil del host y probar que el
# hook se niega a leerlo (fail-open), o dentro en forma Windows (regresion). El
# mensaje va antes para que el caso se lea como "stop con este mensaje y esta
# ruta".
#
# La ruta se inserta CRUDA (sin doblar backslashes). json_string_field es un
# extractor raw sobre bytes entre comillas (no parsea JSON), asi que la forma
# Windows con backslash simple se extrae y se resuelve por cd+pwd igual (medido).
# Doblaria perdido ademas: sed 's/\\/\\\\/g' se rompe en MSYS2 (char 8
# unterminated) y bash ${//} tampoco dobla en esta maquina. La forma cruda es la
# que el hook sabe leer.
lab_payload_stop_ruta_literal() {
  printf '{"session_id":"__SESSION_ID__","transcript_path":"%s","cwd":"/proyecto","prompt_id":"c1a70000-1111-4222-8333-777788889999","permission_mode":"auto","effort":{"level":"xhigh"},"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[],"session_crons":[]}' "$2" "$1"
}

# Una linea de transcript con texto del asistente. Los saltos van escapados
# (`\n`) porque asi los guarda el JSONL real — y ese detalle es justamente el
# que produce el defecto A8: antes de una etiqueta escrita en texto corrido, el
# caracter que hay es la `n` de la secuencia escapada, que es alfabetico.
lab_transcript_asistente() {
  printf '{"parentUuid":"a1","type":"assistant","message":{"id":"msg_1","role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"%s"}]},"uuid":"a2","timestamp":"2026-08-09T12:00:00.000Z"}' "$1"
}

# DEFECTO A2: texto que NO escribio el asistente no debe contar como pausa. El
# vector real (pausa dentro del `content` de un `tool_result`, escenario 14 de la
# linea base) lo prueba la baseline; este caso del banco prueba la CONDICION del
# walker (role:assistant) con un fixture que la hace mutable. Se pone la pausa en
# un `type:text` de un mensaje `user` — realista (el usuario escribio texto) y a
# la profundidad que el walker rastrea. Con el hook sano no se emite (role no es
# assistant); con la mutacion de role si, y el caso se pone rojo.
lab_transcript_pausa_en_resultado() {
  printf '%s\n%s' \
    '{"parentUuid":"a1","type":"user","message":{"role":"user","content":[{"type":"text","text":"la linea que el kit espera es SUMMONAIKIT HARNESS PAUSED - awaiting your answer"}]},"uuid":"a2","timestamp":"2026-08-09T12:30:00.000Z"}' \
    '{"parentUuid":"a2","type":"assistant","message":{"id":"msg_51","role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"Ya lo cambie."}]},"uuid":"a3","timestamp":"2026-08-09T12:30:10.000Z"}'
}

# CORRECCION 1 del plan de la 3.2: la pausa en un content item que NO es
# type:text tampoco cuenta, aunque viva en un mensaje assistant. Se usa un
# `thinking` (no un tool_use) porque el walker rastrea claves a la profundidad
# del content item (depth 4), y ahi es donde el `text` del thinking vive. Con
# un tool_use la pausa iria en `input.command` (depth 5), fuera del alcance del
# walker — y entonces no habria mutacion de "dejar de exigir type:text" que el
# caso pudiera atrapar. El thinking lleva el mismo concepto (type != text debe
# excluirse) en una posicion mutable. El walker tiene que exigir `"type":"text"`
# exacto, no cualquier content item de mensaje assistant.
lab_transcript_thinking_con_pausa() {
  printf '%s' '{"parentUuid":"a1","type":"assistant","message":{"id":"msg_60","role":"assistant","model":"claude-opus-5","content":[{"type":"thinking","text":"Pienso que la linea es SUMMONAIKIT HARNESS PAUSED - awaiting your answer"}]},"uuid":"a2","timestamp":"2026-08-09T12:40:00.000Z"}'
}

# Hallazgo de la revision cruzada (codex, 2026-08-11): un mensaje assistant con
# DOS content items type:text se concatenaban sin separador en el walker. Si el
# primero termina en letra, la etiqueta del segundo no se reconoce por la frontera
# [^[:alpha:]] de has_receipt_label. Para reproducirlo: la CABECERA del recibo en
# el primer bloque (termina en "T" de RECEIPT) y las ETIQUETAS en el segundo. Sin
# el \n entre bloques, "Understand:" queda detras de "T" -> no matchea.
lab_transcript_dos_bloques_recibo() {
  printf '%s' '{"parentUuid":"a1","type":"assistant","message":{"id":"msg_70","role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"SUMMONAIKIT HARNESS RECEIPT"},{"type":"text","text":"Understand: pediste poder listar las sesiones abiertas.\nImplement: se agrego el endpoint y su ruta.\nVerify: se corrio la bateria completa, 12 en verde.\nReview: sin hallazgos.\nClose: entregado; no se toco codigo despues de la revision.\nRetro: none."}]},"uuid":"a2","timestamp":"2026-08-09T12:50:00.000Z"}'
}
