#!/usr/bin/env bash
# probe-zcode-output.sh — medir el contrato de SALIDA de zcode (Task 5.2).
#
# Por que existe: el hook emite hoy cuatro formas de stdout y un exit 2, y NINGUNA
# esta verificada contra el validador de esquema de zcode (CLI 3.7.5-11). La guia
# del propio CLI y zcode.z.ai se contradicen sobre si el esquema es estricto
# (clave extra => descartar todo) o si ignora claves desconocidas. Este probe
# emite cada forma, una por turno, y deja una huella independiente del log de
# zcode para que el veredicto sea MEDIDO y no supuesto.
#
# Esto NO implementa el gate en zcode ni toca el hook. Es la medicion que decide
# si 5.3-5.5 son "el mismo hook + otro registro" o un port.
#
# Dos caras, mismo binario (igual que capture-payloads.sh):
#
#   1) MODO HOOK (sin --instalar/--quitar): lee el payload por stdin y emite por
#      stdout la forma pedida. El modo viene de:
#        a) $SAIKIT_PROBE_MODE
#        b) --mode <nombre>
#        c) primera linea de --mode-file <path>  (el operador lo pisa entre turnos)
#      Flags de registro (las pone --instalar; fail-open siempre):
#        --saikit-probe-id 5.2        marker de propiedad (lo ignora el modo hook)
#        --only-cwd <dir>             si pwd -P != pwd -P de <dir>, no emite ni marca
#        --mode-file <path>           fuente del modo en produccion; su dir es donde
#                                     cae probe-ran/<nonce>.ok
#
#   2) --instalar <repo> / --quitar <repo>: registrar/desregistrar el probe.
#      Por defecto (--host zcode) en el USER-CONFIG de zcode
#      (~/.zcode/cli/config.json). Append quirurgico de DOS entradas
#      (UserPromptSubmit + Stop), idempotentes, con backup. No toca 5.1.
#      Con --host grok (Task 7.2): JSON PROPIO en <repo>/.grok/hooks/
#      saikit-probe.json — Grok corre hooks de proyecto con el repo en
#      trusted_folders.toml (medido en 7.1). NADA global, NADA de zcode.
#      El command es PowerShell (`& "<bash.exe>" ...`, medido en 7.1) y las
#      rutas con metacaracteres de PowerShell se rechazan (fail-closed).
#
# Modo hook con --host grok (lo pone el --instalar en el command del JSON):
#   - hookEventName llega camel de CLAVE pero con VALOR snake: los modos UPS
#     disparan sobre "user_prompt_submit", los de Stop sobre "stop".
#   - el .ok agrega la linea reason=<campo reason del payload, o none>.
#   - con reason=end_turn, las formas de Stop se emiten UNA sola vez por
#     ronda: si probe-ran/ ya tiene un .ok VIVO (nombre = <nonce>.ok puro; los
#     cosechados <modo>-<nonce>.ok no cuentan) de ese modo, con reason=end_turn
#     y la MISMA ronda (round= = sessionId, medido en 7.1), la visita se
#     registra pero no se emite (hallazgo 2 del cross-review: un block aceptado
#     re-bloquearia la continuacion hasta el tope de Grok). Sin identidad de
#     ronda en el payload ni en el env, NO se suprime. reason=shutdown emite
#     SIEMPRE (que se emita y se ignore es la DoD (2)).
#
# Modos y salida EXACTA (el texto del mensaje es el literal PROBE):
#
#   mode     evento que emite   stdout                                                          exit
#   context  UserPromptSubmit   {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit",...}}  0
#   extra    UserPromptSubmit   igual a context + "saikitProbe":true (clave extra)              0
#   block0   Stop               {"decision":"block","reason":"PROBE-BLOCK-<nonce>"}             0 (no 2)
#   budget   Stop               {"continue":false,"stopReason":"PROBE-BUDGET-<nonce>"}          0
#   notice   Stop               {"systemMessage":"PROBE-NOTICE-<nonce>"}                        0
#   exit2    Stop               (vacio) + stderr "PROBE-EXIT2-<nonce>"                          2
#   empty    (control)          (vacio)                                                         0
#   basura/ausente              (vacio)                                                         0   fail-open
#
# block0 usa exit 0 a proposito: el hook vivo manda el JSON de forma 2 con exit 2,
# y en 3.7.5-11 ese JSON con exit 2 NO se parsea (va por la rama del stderr). Para
# medir si el esquema acepta el JSON de forma 2 hace falta que lo parsee, o sea
# exit 0. El efecto del vivo (JSON+exit2) se mide aparte con el modo exit2.
#
# Side-channel probe-ran/<nonce>.ok: en TODOS los modos reales (incluido exit2 y
# empty) el probe escribe <dir-de-mode-file>/probe-ran/<nonce>.ok ANTES de salir.
# Razon (hallazgo 2 de la ronda 2 del plan): un hook OK no deja stdout/stderr en
# el log diario de zcode, y transcript_path es un tmp que cleanup() borra; la
# ausencia de PROBE en el log NO prueba que no corrio. El .ok si. No se escribe
# cuando el evento no es el del modo (no ensucia la medicion del otro evento) ni
# cuando falla --only-cwd (sesion ajena).
#
# Nonce: inyectable via $SAIKIT_PROBE_NONCE (tests byte-exactos); generado si no.
# Esta en el mensaje, en stderr y en el nombre del .ok para que GLM lo halle.
set -u

modo_operacion=""
destino=""
mode_flag=""
mode_file=""
only_cwd=""
probe_id=""
host=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instalar) modo_operacion="instalar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --quitar)   modo_operacion="quitar";   destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    # El valor se valida EN EL PARSEO, en cualquier modo (hallazgo H3 del ciclo
    # 2, cross-review Codex): `--host --instalar <repo>` tragaba --instalar
    # como valor, el modo_operacion quedaba vacio y el script caia al MODO HOOK
    # con stdin vacio — exit 0 sin instalar nada, y encima escribia un .ok de
    # control en el cwd. El comando registrado lo genera el instalador, siempre
    # con valor valido; el fail-open del modo hook cubre host AUSENTE en
    # runtime, no un flag mal parseado.
    --host)
      case "${2:-}" in
        zcode|grok) host="$2" ;;
        *) echo "probe-zcode-output: --host requiere 'zcode' o 'grok' (dio '${2:-}')" >&2
           exit 2 ;;
      esac
      shift 2 ;;
    --mode)     mode_flag="${2:-}";        [ $# -ge 2 ] && shift 2 || shift ;;
    --mode-file) mode_file="${2:-}";       [ $# -ge 2 ] && shift 2 || shift ;;
    --only-cwd) only_cwd="${2:-}";         [ $# -ge 2 ] && shift 2 || shift ;;
    --saikit-probe-id) probe_id="${2:-}";  [ $# -ge 2 ] && shift 2 || shift ;;
    -h|--help)  sed -n '2,75p' "$0"; exit 0 ;;
    *)          shift ;;
  esac
done

# ---------------------------------------------------- utilidades compartidas
# Nonce unico por invocacion. /dev/urandom si esta; si no, timestamp+PID+RANDOM.
gen_nonce() {
  if [ -r /dev/urandom ]; then
    local h
    h="$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' 2>/dev/null)"
    [ -n "$h" ] && { printf '%s' "$h"; return 0; }
  fi
  printf '%s%05d' "$(date +%s 2>/dev/null || echo 0)" "${RANDOM:-0}$$"
}

# hook_event_name del payload de stdin: snake primero, camel de fallback. zcode
# emite hook_event_name (snake) Y/O hookEventName (camel) — 5.1 vio ambos; esta
# medicion vio SOLO camel en Stop. grep -o agarra el PRIMER match (leftmost) y el
# strip deja el valor. Por que NO sed con .* greedy: en C.UTF-8 con GNU sed 4.9,
# sobre un responseText con UTF-8 multibyte (acentos/emoji/backticks), el bracket
# [^"]* cruzaba comillas y capturaba basura ("Stopï\n\nEstoy..." en vez de "Stop")
# — defecto propio hallado en el auto-test del modo empty. grep -o no padece eso.
extract_hook_event() {
  local m
  m="$(printf '%s' "$1" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1)"
  [ -n "$m" ] || m="$(printf '%s' "$1" | grep -o '"hookEventName"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1)"
  [ -n "$m" ] || return 0   # devuelve vacío
  # m = '"hook_event_name":"Stop"' => valor entre el ': "' y el '"' final.
  printf '%s' "$m" | sed 's/^.*:[[:space:]]*"//; s/"$//'
}

# Resolver un bash.exe de Windows para registrar en el user-config de zcode.
# NUNCA persistir /usr/bin/bash ni la salida cruda de `command -v bash`: en
# MSYS son rutas virtuales que Node resuelve con ENOENT. (Leccion 5.1.)
zcode_bash_win() {
  local cand b bw
  for cand in \
    "C:/Program Files/Git/bin/bash.exe" \
    "C:/Program Files (x86)/Git/bin/bash.exe" \
    "C:/Program Files/Git/usr/bin/bash.exe"; do
    if [ -f "$cand" ]; then printf '%s' "$cand"; return 0; fi
  done
  if b="$(command -v bash 2>/dev/null)" && [ -n "$b" ] && command -v cygpath >/dev/null 2>&1; then
    bw="$(cygpath -w "$b" 2>/dev/null)" && [ -n "$bw" ] && { printf '%s' "$bw"; return 0; }
  fi
  return 1
}

# ===================================================================== MODO HOOK
if [ -z "$modo_operacion" ]; then
  # El host lo pone --instalar en el command registrado; sin flag, zcode (el
  # comportamiento historico no se mueve).
  host="${host:-zcode}"
  # --only-cwd: contencion por host. El user-config de zcode es global, asi que
  # el probe dispara en TODAS las sesiones; si el proceso no esta en el repo
  # descartable, no emite ni marca (no filtra/interfiere un turno ajeno).
  if [ -n "$only_cwd" ]; then
    aqui="$(pwd -P 2>/dev/null)"
    want="$(cd "$only_cwd" 2>/dev/null && pwd -P)"
    if [ -z "$want" ] || [ "$aqui" != "$want" ]; then
      exit 0
    fi
  fi

  # Modo: env > --mode > primera linea de --mode-file > empty.
  mode="${SAIKIT_PROBE_MODE:-}"
  [ -n "$mode" ] || mode="$mode_flag"
  if [ -z "$mode" ] && [ -n "$mode_file" ] && [ -f "$mode_file" ]; then
    mode="$(head -n 1 "$mode_file" 2>/dev/null)"
  fi
  # Normalizar: primer token, sin CR de Windows.
  mode="$(printf '%s' "$mode" | tr -d '\r' 2>/dev/null | awk '{print $1}')"
  [ -n "$mode" ] || mode="empty"

  nonce="${SAIKIT_PROBE_NONCE:-}"
  [ -n "$nonce" ] || nonce="$(gen_nonce)"

  # Evento del stdin. zcode emite hook_event_name (snake) Y/O hookEventName
  # (camel); snake primero, camel de fallback (extract_hook_event — ver por que
  # no sed greedy). stderr diagnostico no entra al esquema.
  payload="$(cat 2>/dev/null)"
  evento="$(extract_hook_event "$payload")"

  # Tabla de eventos por host (Task 7.2, medido en 7.1): Grok manda la clave
  # camel (hookEventName, ya la lee extract_hook_event) pero el VALOR en snake:
  # user_prompt_submit / stop. zcode manda UserPromptSubmit / Stop.
  ev_ups="UserPromptSubmit"
  ev_stop="Stop"
  reason=""
  ronda=""
  if [ "$host" = "grok" ]; then
    ev_ups="user_prompt_submit"
    ev_stop="stop"
    # reason del payload (DoD (2): distinguir end_turn de shutdown). Solo se
    # extrae en grok: en zcode no se midio y el .ok queda byte a byte igual.
    # Hallazgo 3 (ciclo de revision 1): grep -o | head -1 puede leer un
    # "reason" embebido en lastAssistantMessage antes del campo real. Grok
    # documenta exactamente dos literales; cualquier otro valor se descarta
    # como none: no se topa una ronda ni se declara shutdown por basura.
    reason="$(printf '%s' "$payload" \
      | grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 \
      | sed 's/^.*:[[:space:]]*"//; s/"$//')"
    case "$reason" in
      end_turn|shutdown) ;;
      *) reason="" ;;
    esac
    # Identidad de la ronda (hallazgo H2 del ciclo 2, cross-review Codex): el
    # tope de una emision por ronda tiene que distinguir la CONTINUACION tras
    # un block aceptado de una ronda NUEVA. Medido en 7.1
    # (docs/task-7.1-captura.md): el envelope trae sessionId (camel) y el
    # runner inyecta GROK_SESSION_ID en el env; cada `grok -p` es una sesion
    # nueva y la continuacion comparte sesion. "Ronda" = sessionId del
    # payload, fallback GROK_SESSION_ID del env, fallback promptId del
    # payload. Si NO hay identidad, el tope NO suprime: preferible emitir de
    # mas en un caso no medido (Grok topa solo en 8 continuaciones) que un
    # falso "ignored" por un .ok de una ronda vieja abortada sin cosechar.
    ronda="$(printf '%s' "$payload" \
      | grep -o '"sessionId"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 \
      | sed 's/^.*:[[:space:]]*"//; s/"$//')"
    [ -n "$ronda" ] || ronda="${GROK_SESSION_ID:-}"
    if [ -z "$ronda" ]; then
      ronda="$(printf '%s' "$payload" \
        | grep -o '"promptId"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 \
        | sed 's/^.*:[[:space:]]*"//; s/"$//')"
    fi
  fi

  # probe-ran/ cae junto al mode-file (el dest en produccion); si no hay mode-file,
  # junto al cwd. Ahi vive el side-channel <nonce>.ok.
  ran_dir=""
  if [ -n "$mode_file" ]; then
    ran_dir="$(cd "$(dirname "$mode_file")" 2>/dev/null && pwd -P)"
  fi
  [ -n "$ran_dir" ] || ran_dir="$(pwd -P)"
  ran_dir="$ran_dir/probe-ran"

  # El probe "corrio su emision" (merece .ok) cuando:
  #   - empty: siempre (control de "corrio", sin stdout); o
  #   - modo real Y evento es el de ese modo.
  # Modo basura/ausente: no (fail-open, no ensucia probe-ran).
  ok="0"
  case "$mode" in
    context|extra)        [ "$evento" = "$ev_ups" ] && ok="1" ;;
    block0|budget|notice|exit2) [ "$evento" = "$ev_stop" ] && ok="1" ;;
    empty)                ok="1" ;;
    *)                    ok="0" ;;
  esac

  # Tope de UNA emision de bloqueo por ronda (Task 7.2, hallazgo 2 del
  # cross-review con Codex): si un block aceptado continua el turno, la
  # continuacion vuelve a disparar el probe y re-bloquearia hasta el limite
  # interno de Grok (8). Con reason=end_turn, si probe-ran/ ya tiene un .ok de
  # ESTE modo, con reason=end_turn y la MISMA ronda (round= = sessionId), la
  # visita se registra (su .ok se escribe igual) pero NO se vuelve a emitir.
  # reason=shutdown emite siempre: el proceso ya esta saliendo, y que la
  # decision se emita y se ignore es justo lo que la DoD (2) mide. Se mira
  # ANTES de escribir el .ok propio, si no la primera visita se suprimiria a
  # si misma.
  suprimir="0"
  if [ "$host" = "grok" ] && [ "$ok" = "1" ] && [ "$evento" = "$ev_stop" ] && [ "$reason" = "end_turn" ] && [ -n "$ronda" ]; then
    case "$mode" in
      block0|budget|notice|exit2)
        for f in "$ran_dir"/*.ok; do
          [ -f "$f" ] || continue
          # Hallazgo 1 (ciclo de revision 1): la cosecha del plan (§C) renombra
          # los .ok a <modo>-<nonce>.ok EN ESTE MISMO DIR. Si el glob los
          # tomara, en una re-medicion la primera visita end_turn encontraria
          # los cosechados y no emitiria: veredicto falso "ignored". Los .ok
          # vivos se llaman <nonce>.ok PURO (el nonce generado — urandom hex o
          # timestamp+PID+RANDOM — nunca lleva guion). Convencion, no guard:
          # un $SAIKIT_PROBE_NONCE inyectado CON guion crearia un .ok vivo que
          # este skip tomaria por cosechado; los tests no lo hacen.
          case "$(basename "$f")" in *-*) continue ;; esac
          # H2 (ciclo 2): el .ok previo solo cuenta si es de ESTA ronda
          # (round= = sessionId, ver el bloque de extraccion). Un .ok vivo de
          # otra sesion (ronda abortada sin cosechar) no suprime nada.
          if grep -q "^mode=$mode " "$f" 2>/dev/null && grep -q '^reason=end_turn$' "$f" 2>/dev/null \
             && grep -Fxq "round=$ronda" "$f" 2>/dev/null; then
            suprimir="1"; break
          fi
        done ;;
    esac
  fi

  # Side-channel ANTES de emitir. Fail-open: si no se puede escribir, se emite
  # igual (el turno del operador no se rompe por el side-channel).
  if [ "$ok" = "1" ]; then
    mkdir -p "$ran_dir" 2>/dev/null || true
    printf 'mode=%s event=%s nonce=%s\n' "$mode" "${evento:-none}" "$nonce" \
      > "$ran_dir/$nonce.ok" 2>/dev/null || true
    # grok: la linea reason= es la evidencia de la DoD (2) y, junto con round=
    # (la identidad de la ronda, H2 ciclo 2), el insumo del tope.
    if [ "$host" = "grok" ]; then
      printf 'reason=%s\n' "${reason:-none}" >> "$ran_dir/$nonce.ok" 2>/dev/null || true
      printf 'round=%s\n' "${ronda:-none}" >> "$ran_dir/$nonce.ok" 2>/dev/null || true
    fi
  fi

  # La visita quedo registrada en su .ok; la emision ya se hizo en esta ronda.
  [ "$suprimir" = "1" ] && exit 0

  # stderr de diagnostico (NO entra al esquema de stdout). exit2 lleva el nonce.
  case "$mode" in
    context)
      if [ "$evento" = "$ev_ups" ]; then
        printf 'PROBE mode=context event=%s exit=0\n' "$evento" >&2
        printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-CONTEXT-%s"}}\n' "$nonce"
        exit 0
      fi ;;
    extra)
      if [ "$evento" = "$ev_ups" ]; then
        printf 'PROBE mode=extra event=%s exit=0\n' "$evento" >&2
        printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-EXTRA-%s"},"saikitProbe":true}\n' "$nonce"
        exit 0
      fi ;;
    block0)
      if [ "$evento" = "$ev_stop" ]; then
        printf 'PROBE mode=block0 event=%s exit=0\n' "$evento" >&2
        printf '{"decision":"block","reason":"PROBE-BLOCK-%s"}\n' "$nonce"
        exit 0
      fi ;;
    budget)
      if [ "$evento" = "$ev_stop" ]; then
        printf 'PROBE mode=budget event=%s exit=0\n' "$evento" >&2
        printf '{"continue":false,"stopReason":"PROBE-BUDGET-%s"}\n' "$nonce"
        exit 0
      fi ;;
    notice)
      if [ "$evento" = "$ev_stop" ]; then
        printf 'PROBE mode=notice event=%s exit=0\n' "$evento" >&2
        printf '{"systemMessage":"PROBE-NOTICE-%s"}\n' "$nonce"
        exit 0
      fi ;;
    exit2)
      if [ "$evento" = "$ev_stop" ]; then
        printf 'PROBE-EXIT2-%s\n' "$nonce" >&2
        exit 2
      fi ;;
    empty)
      printf 'PROBE mode=empty event=%s exit=0\n' "${evento:-none}" >&2
      exit 0 ;;
  esac

  # Evento incorrecto para el modo, o modo basura: silencio + exit 0.
  exit 0
fi

# ================================================================ validar dest
# El VALOR de --host ya se valido en el parseo (H3 ciclo 2); aca solo queda el
# default para cuando el flag no se paso (el modo historico es zcode).
host="${host:-zcode}"

if [ -z "$destino" ]; then
  echo "probe-zcode-output: falta el repo descartable destino" >&2
  exit 2
fi
destino_real="$(cd "$destino" 2>/dev/null && pwd -P)"
home_real="$(cd "$HOME" 2>/dev/null && pwd -P)"
if [ -z "$destino_real" ]; then
  echo "probe-zcode-output: el destino no existe o no se puede entrar: $destino" >&2
  exit 2
fi
case "$destino_real" in
  "$home_real"|"$home_real"/.claude*|"$home_real"/.zcode*|"$home_real"/.grok*)
    echo "probe-zcode-output: me niego a tocar el perfil real." >&2
    echo "                   pedido: $destino" >&2
    echo "                   resuelve a: $destino_real" >&2
    echo "                   El probe va en un repo descartable, no donde vive el gate/config." >&2
    exit 2 ;;
esac

aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
probe="$aqui/probe-zcode-output.sh"

# ============================ filtros jq para el user-config (idempotentes) ===
# ours/has_probe por ENTRADA (no por conteo): si UPS tiene el probe y Stop no,
# agrega solo Stop. ours510 no se toca: --quitar saca solo saikit-probe-id 5.2,
# respeta 5.1, SessionStart y tokentracker. 5[.]2 (punto literal) para no mezclar
# escapes de bash y jq.
JQ_PROBE_INSTALL='
def has_probe(ev):
  any( (.hooks.events[ev] // [])[] ;
       any( (.hooks // [])[] ; ((.command // "") | test("saikit-probe-id 5[.]2")) ) );
def add_unless(ev; cmd):
  if has_probe(ev) then .
  else .hooks.events[ev] = ((.hooks.events[ev] // []) +
    [ { hooks: [ { type: "command", command: cmd, timeout: 15 } ] } ])
  end;
add_unless("UserPromptSubmit"; $cmd)
| add_unless("Stop"; $cmd)
'
JQ_PROBE_QUITAR='
def ours: any((.hooks // [])[]; ((.command // "") | test("saikit-probe-id 5[.]2")));
def strip(arr): ((arr // []) | map(select(ours | not)));
if ((.hooks // {}) | has("events")) then
  .hooks.events.UserPromptSubmit = strip(.hooks.events.UserPromptSubmit)
  | .hooks.events.Stop = strip(.hooks.events.Stop)
else . end
'

# Comando de hook para el probe: bash.exe de Windows + probe + flags del modo hook.
# type: command (no process): es la forma que usa el 100% de los hooks del config
# real de zcode, y stdin llega confirmado bajo type:command (medido en Task 5.1,
# capture-payloads.sh). El plan §A3 pedia type:process; se cambio a type:command
# porque es lo MEDIDO en 3.7.5-11 — type:process no esta verificado y un registro
# que no corre vuelve toda la medicion `unknown`. El side-channel .ok lo hace
# auto-correctivo: si el registro no dispara, todo da unknown y se reinstala.
zcode_probe_cmd() {  # $1=bash_win
  printf '"%s" "%s" --saikit-probe-id 5.2 --only-cwd "%s" --mode-file "%s"' \
    "$1" "$probe" "$destino_real" "$destino_real/probe-mode.txt"
}

probe_instalar() {
  command -v jq >/dev/null 2>&1 || {
    echo "probe-zcode-output: --instalar requiere jq (no encontrado)" >&2; exit 2; }
  local user_config bash_win uc_dir ts bak cmd tmp_new
  user_config="${SAIKIT_ZCODE_USER_CONFIG:-$HOME/.zcode/cli/config.json}"
  [ -f "$user_config" ] || {
    echo "probe-zcode-output: no existe el user-config de zcode ($user_config)." >&2
    echo "                   No lo creo de cero: el operador ya tiene uno." >&2
    exit 2; }
  bash_win="$(zcode_bash_win)" || {
    echo "probe-zcode-output: no encontre un bash.exe de Windows para registrar el probe" >&2
    exit 2; }

  umask 077
  # 1) repo descartable: mode-file inicial + marca de propiedad.
  mkdir -p "$destino_real/.zcode" 2>/dev/null || true
  printf 'empty\n' > "$destino_real/probe-mode.txt" || exit 2
  mkdir -p "$destino_real/probe-ran" 2>/dev/null || true
  printf 'owner=tools/probe-zcode-output.sh\ntask=5.2\nuser_config=%s\ncwd=%s\ninstalled=%s\n' \
    "$user_config" "$destino_real" "$(date +%Y%m%d-%H%M%S)" \
    > "$destino_real/.zcode/.probe-zcode-owned" || exit 2

  # 2) backup FUERA del dest git, hermano del user-config.
  uc_dir="$(cd "$(dirname "$user_config")" 2>/dev/null && pwd -P)"
  [ -n "$uc_dir" ] || uc_dir="$(dirname "$user_config")"
  mkdir -p "$uc_dir/saikit-backups" || {
    echo "probe-zcode-output: no pude crear $uc_dir/saikit-backups" >&2; exit 2; }
  ts="$(date +%Y%m%d-%H%M%S)"
  bak="$uc_dir/saikit-backups/config.$ts.bak"
  cp "$user_config" "$bak" || { echo "probe-zcode-output: fallo el backup" >&2; exit 2; }
  cmp -s "$user_config" "$bak" || {
    echo "probe-zcode-output: el backup no calza con el original; no toco el config" >&2
    exit 2; }

  # 3) aviso fuerte si los hooks no estan habilitados (no lo reescribo: es suyo).
  if ! jq -e '.hooks.enabled == true' "$user_config" >/dev/null 2>&1; then
    echo "probe-zcode-output: ADVERTENCIA: .hooks.enabled != true en $user_config" >&2
    echo "                   El probe NO va a correr hasta arreglarlo." >&2
  fi

  # 4) append idempotente de 2 entradas (UPS + Stop). jq solo escribe JSON
  # valido; si falla, no se hace mv y el vivo queda intacto (temp en mismo dir).
  cmd="$(zcode_probe_cmd "$bash_win")"
  tmp_new="$(mktemp)" || { echo "probe-zcode-output: no pude crear tmp" >&2; exit 2; }
  if ! jq --arg cmd "$cmd" "$JQ_PROBE_INSTALL" "$user_config" > "$tmp_new"; then
    echo "probe-zcode-output: jq fallo al appendear; el config original queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  # Validacion extra: el temp debe ser JSON parseable antes del mv.
  if ! jq -e . "$tmp_new" >/dev/null 2>&1; then
    echo "probe-zcode-output: el temp no es JSON valido; el config original queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$user_config" || {
    echo "probe-zcode-output: no pude escribir $user_config" >&2; exit 2; }

  echo "Probe registrado en el user-config: $user_config"
  echo "  2 entradas con --saikit-probe-id 5.2: UserPromptSubmit + Stop (sin matcher)."
  echo "  Repo descartable: $destino_real (probe-ran/ ahi)"
  echo "  Mode-file: $destino_real/probe-mode.txt (ahora: empty)"
  echo "  Backup: $bak"
  echo "  Sesion NUEVA de zcode en $destino_real; un modo por turno (pisa probe-mode.txt)."
}

probe_quitar() {
  command -v jq >/dev/null 2>&1 || {
    echo "probe-zcode-output: --quitar requiere jq (no encontrado)" >&2; exit 2; }
  local marca user_config tmp_new n_antes n_despues
  marca="$destino_real/.zcode/.probe-zcode-owned"
  [ -f "$marca" ] || {
    echo "probe-zcode-output: no hay marca de probe en $marca (nada que quitar)" >&2
    exit 2; }
  user_config="${SAIKIT_ZCODE_USER_CONFIG:-$(grep '^user_config=' "$marca" 2>/dev/null | cut -d= -f2-)}"
  [ -n "$user_config" ] || user_config="$HOME/.zcode/cli/config.json"
  [ -f "$user_config" ] || {
    echo "probe-zcode-output: no existe el user-config ($user_config)" >&2; exit 2; }

  n_antes="$(grep -c 'saikit-probe-id 5\.2' "$user_config" 2>/dev/null || true)"
  tmp_new="$(mktemp)" || exit 2
  if ! jq "$JQ_PROBE_QUITAR" "$user_config" > "$tmp_new"; then
    echo "probe-zcode-output: jq fallo al quitar; el config queda intacto" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$user_config" || {
    echo "probe-zcode-output: no pude escribir $user_config" >&2; exit 2; }
  n_despues="$(grep -c 'saikit-probe-id 5\.2' "$user_config" 2>/dev/null || true)"
  rm -f "$marca"
  echo "Quitadas entradas del probe (saikit-probe-id 5.2) de $user_config"
  echo "  antes: $n_antes   despues: $n_despues   (5.1, SessionStart y tokentracker quedan intactos)"
}

# ====================================================== Task 7.2: grok ======
# Registro a nivel PROYECTO: <repo>/.grok/hooks/saikit-probe.json, archivo
# PROPIO (no append a un config ajeno). Grok corre los hooks de proyecto con el
# repo en trusted_folders.toml (medido en 7.1; NO existe --trust ni
# GROK_FOLDER_TRUST que cargue hooks). NADA global: ni ~/.grok/hooks/, ni
# config.toml, ni el user-config de zcode.
#
# El command es un string de PowerShell: 7.1 midio que el shell de hooks de
# Grok 1.0.3 en Windows es powershell.exe, y la forma zcode ("exe" "script")
# muere con exit 1 sin correr nada. La que invoca al bash.exe correcto sin
# depender del PATH es el call operator: & "<bash.exe>" "<probe>" args.
grok_probe_json()  { printf '%s/.grok/hooks/saikit-probe.json' "$destino_real"; }
grok_probe_marca() { printf '%s/.grok/.probe-grok-owned' "$destino_real"; }

# Escape minimo para meter el command dentro del JSON (lleva comillas dobles
# alrededor de las rutas, como bash.exe en Program Files).
grok_json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Fail-closed (hallazgo 4 del cross-review con Codex): el command se interpola
# en un string PowerShell de comillas dobles; una ruta con `"`, backtick o `$`
# ejecutaria EXPRESIONES al dispararse el hook. Las rutas reales de esta
# maquina no los tienen; si aparecen, se declara y se pasa a comillas simples
# medidas, no se escribe igual.
grok_rechaza_metacaracteres() {
  local v
  for v in "$@"; do
    case "$v" in
      *\"*|*\`*|*\$*)
        echo "probe-zcode-output: ruta con metacaracteres de PowerShell: $v" >&2
        echo "                   El command se interpola en comillas dobles y esa ruta" >&2
        echo "                   ejecutaria expresiones. No se registra." >&2
        exit 2 ;;
    esac
  done
}

# Identidad "es nuestro" del JSON de registro (hallazgo H1 del ciclo 2,
# cross-review Codex): grepear el TEXTO --saikit-probe-id 7.2 alcanzaba con que
# un archivo ajeno lo mencionara en una nota y el install lo sobrescribia.
# Identidad estricta: la clave top-level "saikit_probe" (grepeada COMO clave,
# con el ':' despues) Y la marca .probe-grok-owned. Sin AMBAS => desconocido:
# no se pisa, no se borra, se reporta y exit != 0.
grok_json_es_nuestro() {  # $1=json  $2=marca
  [ -f "$2" ] || return 1
  grep -q '"saikit_probe"[[:space:]]*:' "$1" 2>/dev/null
}

grok_probe_instalar() {
  local json marca bash_win cmd tmp_new
  json="$(grok_probe_json)"
  marca="$(grok_probe_marca)"
  bash_win="$(zcode_bash_win)" || {
    echo "probe-zcode-output: no encontre un bash.exe de Windows para registrar el probe" >&2
    exit 2; }
  grok_rechaza_metacaracteres "$bash_win" "$probe" "$destino_real"
  if [ -e "$json" ] && ! grok_json_es_nuestro "$json" "$marca"; then
    echo "probe-zcode-output: $json existe y no es mio (falta la clave saikit_probe" >&2
    echo "                   o la marca .probe-grok-owned) — no lo toco." >&2
    exit 2; fi
  umask 077
  mkdir -p "$(dirname "$json")" || exit 2
  # Mode-file inicial + dir del side-channel, igual que el modo zcode.
  printf 'empty\n' > "$destino_real/probe-mode.txt" || exit 2
  mkdir -p "$destino_real/probe-ran" 2>/dev/null || true

  # El command lleva --host grok: sin eso el modo hook esperaria los literales
  # UserPromptSubmit/Stop de zcode y nunca emitiria (7.1: Grok manda snake).
  cmd="& \"$bash_win\" \"$probe\" --saikit-probe-id 7.2 --host grok --only-cwd \"$destino_real\" --mode-file \"$destino_real/probe-mode.txt\""
  cmd="$(grok_json_esc "$cmd")"
  tmp_new="$(mktemp)" || { echo "probe-zcode-output: no pude crear tmp" >&2; exit 2; }
  cat > "$tmp_new" <<JSON
{
  "saikit_probe": "7.2",
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "$cmd", "timeout": 30 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$cmd", "timeout": 30 } ] }
    ]
  }
}
JSON
  # Red de seguridad: un JSON que no parsea dejaria el registro roto en un repo
  # donde Grok lo lee en cada turno. Se valida si hay jq; si no, la plantilla
  # es fija y el test la valida en el sandbox. Nunca se hace mv de basura.
  if command -v jq >/dev/null 2>&1 && ! jq -e . "$tmp_new" >/dev/null 2>&1; then
    echo "probe-zcode-output: el JSON generado no parsea; no toco el destino" >&2
    rm -f "$tmp_new"; exit 2
  fi
  mv -f "$tmp_new" "$json" || {
    echo "probe-zcode-output: no pude escribir $json" >&2; rm -f "$tmp_new"; exit 2; }
  printf 'owner=tools/probe-zcode-output.sh\nhost=grok\ntask=7.2\ncwd=%s\ninstalled=%s\n' \
    "$destino_real" "$(date +%Y%m%d-%H%M%S)" > "$marca" || exit 2
  echo "Probe grok registrado en $json"
  echo "  2 entradas con --saikit-probe-id 7.2: UserPromptSubmit + Stop (sin matcher)."
  echo "  Repo descartable: $destino_real (probe-ran/ ahi; mode-file probe-mode.txt, ahora: empty)"
  echo "  Falta el trust del folder (entrada en ~/.grok/trusted_folders.toml) y un turno por modo."
}

grok_probe_quitar() {
  local json marca
  json="$(grok_probe_json)"
  marca="$(grok_probe_marca)"
  [ -f "$marca" ] || {
    echo "probe-zcode-output: no hay marca de probe grok en $marca (nada que quitar)" >&2
    exit 2; }
  if [ -e "$json" ]; then
    # Misma identidad estricta que el install (H1 ciclo 2): la marca sola no
    # alcanza — el JSON tiene que llevar la clave top-level saikit_probe.
    grep -q '"saikit_probe"[[:space:]]*:' "$json" 2>/dev/null || {
      echo "probe-zcode-output: $json no lleva la clave saikit_probe — no lo borro." >&2
      echo "                   Alguien lo cambio despues del install; revisarlo a mano." >&2
      exit 2; }
    rm -f "$json" || { echo "probe-zcode-output: no pude borrar $json" >&2; exit 2; }
  fi
  rm -f "$marca"
  echo "Quitado el registro del probe grok ($json) y la marca."
  echo "  probe-mode.txt y probe-ran/ quedan (la evidencia no se borra)."
  echo "  Recorda el restore quirurgico del trust: sacar SOLO la entrada del repo de"
  echo "  ~/.grok/trusted_folders.toml (no pisar el archivo con el backup)."
}

case "$modo_operacion" in
  instalar)
    if [ "$host" = "grok" ]; then grok_probe_instalar; else probe_instalar; fi ;;
  quitar)
    if [ "$host" = "grok" ]; then grok_probe_quitar; else probe_quitar; fi ;;
esac
