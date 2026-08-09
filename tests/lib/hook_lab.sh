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
# La ruta del estado NO se recalcula (es un cksum de la ruta del proyecto): se
# DESCUBRE armando un turno en `lab_init` y mirando donde quedo. Recalcularla
# seria adivinar — si el hook cambiara de esquema, los casos sembrados
# escribirian en un archivo que nadie lee y quedarian verdes por vacio.
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

# Cambia el archivo bajo prueba conservando el banco (y por lo tanto la ruta de
# estado ya descubierta, que depende solo de la ruta del proyecto). Lo usa la
# bateria de mutaciones, que ejercita decenas de copias del mismo hook.
lab_hook_swap() {
  cp "$1" "$LAB/hooks/summonaikit-harness.sh" || return 1
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
  printf '%s' "$lab_payload" | sed "s|__TRANSCRIPT__|$lab_tr|g" > "$lab_entrada"

  lab_cmd=(env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE -u SUMMONAIKIT_HOOK_TARGET
           HOME="$LAB/home" USERPROFILE="$LAB/home")
  [ "$lab_fase" != "auto" ]   && lab_cmd+=(SUMMONAIKIT_HOOK_PHASE="$lab_fase")
  [ "$lab_target" != "auto" ] && lab_cmd+=(SUMMONAIKIT_HOOK_TARGET="$lab_target")

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
# Forma tomada de payloads reales de Claude Code. El hook no parsea JSON (usa
# `sed` sobre el texto crudo), asi que lo que importa es que los campos existan
# con la forma real, no que el JSON sea estricto.
lab_payload_prompt() {
  printf '{"session_id":"ses-13","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","permission_mode":"default","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"
}

# El payload de SessionStart NO trae campo `prompt`: el hook cae al INPUT entero
# como texto del prompt. Por eso el sentinel, si aparece, aparece en otro campo
# (un resumen de sesion reanudada, por ejemplo).
lab_payload_session() {
  printf '{"session_id":"ses-13","hook_event_name":"SessionStart","source":"resume","cwd":"/proyecto","summary":"%s"}' "$1"
}

lab_payload_task() {
  printf '{"session_id":"ses-13","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","hook_event_name":"PostToolUse","tool_name":"Task","tool_input":{"subagent_type":"%s","description":"paso del harness","prompt":"hace lo tuyo"},"tool_response":{"content":"listo"}}' "$1"
}

lab_payload_bash() {
  printf '{"session_id":"ses-13","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"exitCode":%s,"stdout":"salida"}}' "$1" "$2"
}

lab_payload_edit() {
  printf '{"session_id":"ses-13","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"tool_response":{"filePath":"%s","userModified":false}}' "$1" "$1"
}

lab_payload_stop() {
  printf '{"session_id":"ses-13","transcript_path":"__TRANSCRIPT__","cwd":"/proyecto","hook_event_name":"Stop","stop_hook_active":false}'
}

# Una linea de transcript con texto del asistente. Los saltos van escapados
# (`\n`) porque asi los guarda el JSONL real — y ese detalle es justamente el
# que produce el defecto A8: antes de una etiqueta escrita en texto corrido, el
# caracter que hay es la `n` de la secuencia escapada, que es alfabetico.
lab_transcript_asistente() {
  printf '{"parentUuid":"a1","type":"assistant","message":{"id":"msg_1","role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"%s"}]},"uuid":"a2","timestamp":"2026-08-09T12:00:00.000Z"}' "$1"
}
