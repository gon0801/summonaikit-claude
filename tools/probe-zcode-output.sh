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
#   2) --instalar <repo> / --quitar <repo>: registrar/desregistrar el probe en el
#      USER-CONFIG de zcode (~/.zcode/cli/config.json). Append quirurgico de DOS
#      entradas (UserPromptSubmit + Stop), idempotentes, con backup. No toca 5.1.
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
while [ $# -gt 0 ]; do
  case "$1" in
    --instalar) modo_operacion="instalar"; destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --quitar)   modo_operacion="quitar";   destino="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
    --mode)     mode_flag="${2:-}";        [ $# -ge 2 ] && shift 2 || shift ;;
    --mode-file) mode_file="${2:-}";       [ $# -ge 2 ] && shift 2 || shift ;;
    --only-cwd) only_cwd="${2:-}";         [ $# -ge 2 ] && shift 2 || shift ;;
    --saikit-probe-id) probe_id="${2:-}";  [ $# -ge 2 ] && shift 2 || shift ;;
    -h|--help)  sed -n '2,60p' "$0"; exit 0 ;;
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

  # Evento del stdin. zcode emite hook_event_name (snake) Y hookEventName (camel);
  # snake primero (la que el hook lee), camel de fallback (5.1).
  payload="$(cat 2>/dev/null)"
  evento="$(printf '%s' "$payload" \
    | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "$evento" ]; then
    evento="$(printf '%s' "$payload" \
      | sed -n 's/.*"hookEventName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
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
    context|extra)        [ "$evento" = "UserPromptSubmit" ] && ok="1" ;;
    block0|budget|notice|exit2) [ "$evento" = "Stop" ] && ok="1" ;;
    empty)                ok="1" ;;
    *)                    ok="0" ;;
  esac

  # Side-channel ANTES de emitir. Fail-open: si no se puede escribir, se emite
  # igual (el turno del operador no se rompe por el side-channel).
  if [ "$ok" = "1" ]; then
    mkdir -p "$ran_dir" 2>/dev/null || true
    printf 'mode=%s event=%s nonce=%s\n' "$mode" "${evento:-none}" "$nonce" \
      > "$ran_dir/$nonce.ok" 2>/dev/null || true
  fi

  # stderr de diagnostico (NO entra al esquema de stdout). exit2 lleva el nonce.
  case "$mode" in
    context)
      if [ "$evento" = "UserPromptSubmit" ]; then
        printf 'PROBE mode=context event=%s exit=0\n' "$evento" >&2
        printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-CONTEXT-%s"}}\n' "$nonce"
        exit 0
      fi ;;
    extra)
      if [ "$evento" = "UserPromptSubmit" ]; then
        printf 'PROBE mode=extra event=%s exit=0\n' "$evento" >&2
        printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-EXTRA-%s"},"saikitProbe":true}\n' "$nonce"
        exit 0
      fi ;;
    block0)
      if [ "$evento" = "Stop" ]; then
        printf 'PROBE mode=block0 event=%s exit=0\n' "$evento" >&2
        printf '{"decision":"block","reason":"PROBE-BLOCK-%s"}\n' "$nonce"
        exit 0
      fi ;;
    budget)
      if [ "$evento" = "Stop" ]; then
        printf 'PROBE mode=budget event=%s exit=0\n' "$evento" >&2
        printf '{"continue":false,"stopReason":"PROBE-BUDGET-%s"}\n' "$nonce"
        exit 0
      fi ;;
    notice)
      if [ "$evento" = "Stop" ]; then
        printf 'PROBE mode=notice event=%s exit=0\n' "$evento" >&2
        printf '{"systemMessage":"PROBE-NOTICE-%s"}\n' "$nonce"
        exit 0
      fi ;;
    exit2)
      if [ "$evento" = "Stop" ]; then
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
  "$home_real"|"$home_real"/.claude*|"$home_real"/.zcode*)
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

case "$modo_operacion" in
  instalar) probe_instalar ;;
  quitar)   probe_quitar ;;
esac
