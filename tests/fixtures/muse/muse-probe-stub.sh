#!/usr/bin/env bash
# muse-probe-stub.sh — doble del binario de Muse para el probe 23.5 y su test.
#
# Emula SOLO el contrato que tools/probe-muse-contract.sh necesita, con el
# proveedor echo (sin red, sin costo): --version, exec (dispara los hooks del
# settings con bash -c y emula que un Stop con decision:block continua con
# una segunda pasada) y export (documento JSON con el contexto inyectado, la
# evidencia del Stop y el catalogo de agentes).
#
# Modos rojos via SAIKIT_STUB_MODE (cada uno rompe UN punto del contrato):
#   normal      todo pasa (verde)
#   no-hooks    exec no corre ningun hook (binario que ignora el registro)
#   no-ctx      el export no trae el contexto inyectado
#   no-continue el Stop bloquea pero no hay segunda pasada
#   no-catalog  el export omite un perfil (frontmatter rechazado en silencio)
#   ctx-fuera-de-campo la marca del contexto sale cruda sin entrar al
#      additionalContext (P2 en campo ajeno; vuelta 1 de revision)
#   block-ignorado el turno hace dos pasadas pero ignora decision:block
#      (P3 sin bloqueo efectivo; vuelta 1 de revision)
#   perfil-fuera-de-catalogo un perfil falta del catalogo y su nombre sale
#      en una nota (P4 en campo ajeno; vuelta 1 de revision)
#   catalogo-imitado el catalogo real omite un perfil y una nota anterior
#      imita la lista completa (P4 fuera del evento; vuelta 2 de revision)
#   campo-auxiliar-catalogo el text del evento omite un perfil y un campo
#      auxiliar del mismo evento imita la lista (P4 fuera del text; vuelta 3)
set -u

mode="${SAIKIT_STUB_MODE:-normal}"
xdg="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
settings="$xdg/muse/settings.json"
evdir="${XDG_CACHE_HOME:-${HOME:-}/.cache}/saikit-probe"

cmd="${1:-}"
case "$cmd" in
  --version|-v|version)
    printf 'Muse Code 9.9.9-stub (muse-probe-stub-23.5)\n'
    exit 0
    ;;
  exec)
    shift
    [ -f "$settings" ] || { printf 'malformed settings file at %s: missing settings file\n' "$settings" >&2; exit 1; }
    jq -e . "$settings" >/dev/null 2>&1 || { printf 'malformed settings file at %s: invalid JSON\n' "$settings" >&2; exit 1; }
    [ "$(jq -r '.schema_version // empty' "$settings")" = "1" ] || { printf 'malformed settings file at %s: missing field `schema_version`\n' "$settings" >&2; exit 1; }
    mkdir -p "$evdir"
    : > "$evdir/fired.log"
    : > "$evdir/ups-out.txt"
    : > "$evdir/stop-out.txt"
    printf '1' > "$evdir/stop-runs.txt"
    prompt="${*: -1}"
    # Deriva 23.5: la validacion del instalador (--no-session-log, era de
    # instalacion) siempre dispara; el modo rojo solo rompe el turno del
    # probe (el binario se autoactualizo despues de instalar).
    era_instalacion=0
    case " $* " in *" --no-session-log "*) era_instalacion=1 ;; esac
    [ "$era_instalacion" -eq 1 ] && mode="normal"
    comandos_de() { jq -r --arg ev "$1" '.hooks[$ev][]?.hooks[]?.command // empty' "$settings" 2>/dev/null; }
    correr() { bash -c "$1" >/dev/null 2>&1 || true; }
    if [ "$mode" != "no-hooks" ]; then
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        printf 'SessionStart\n' >> "$evdir/fired.log"
        correr "$c"
      done < <(comandos_de SessionStart)
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        printf 'UserPromptSubmit\n' >> "$evdir/fired.log"
        out="$(bash -c "$c" 2>/dev/null || true)"
        printf '%s' "$out" >> "$evdir/ups-out.txt"
      done < <(comandos_de UserPromptSubmit)
      pasa=1
      while [ "$pasa" -le 2 ]; do
        while IFS= read -r c; do
          [ -n "$c" ] || continue
          printf 'Stop\n' >> "$evdir/fired.log"
          out="$(bash -c "$c" 2>/dev/null || true)"
          printf '%s' "$out" >> "$evdir/stop-out.txt"
        done < <(comandos_de Stop)
        printf '%s' "$pasa" > "$evdir/stop-runs.txt"
        if [ "$pasa" -eq 1 ] && [ "$mode" != "no-continue" ] && grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' "$evdir/stop-out.txt" 2>/dev/null; then
          pasa=2
        else
          break
        fi
      done
    fi
    printf 'echo: %s\n' "$prompt"
    exit 0
    ;;
  export)
    shift
    out=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --out) out="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$out" ] || { printf 'muse-probe-stub: export requiere --out\n' >&2; exit 2; }
    mkdir -p "$evdir"
    ctx=""
    if [ "$mode" != "no-ctx" ] && [ "$mode" != "ctx-fuera-de-campo" ] && [ -f "$evdir/ups-out.txt" ]; then
      ctx="$(grep -o 'SAIKIT-PROBE-CTX-[A-Za-z0-9-]*' "$evdir/ups-out.txt" | head -1 || true)"
    fi
    decoy_ctx=""
    if [ "$mode" = "ctx-fuera-de-campo" ] && [ -f "$evdir/ups-out.txt" ]; then
      decoy_ctx="$(grep -o 'SAIKIT-PROBE-CTX-[A-Za-z0-9-]*' "$evdir/ups-out.txt" | head -1 || true)"
    fi
    blk=""
    runs="0"
    [ -f "$evdir/stop-runs.txt" ] && runs="$(cat "$evdir/stop-runs.txt")"
    [ "$mode" = "no-hooks" ] && runs="0"
    if [ "$mode" != "block-ignorado" ] && [ -f "$evdir/stop-out.txt" ]; then
      blk="$(grep -o 'SAIKIT-PROBE-BLOCK-[A-Za-z0-9-]*' "$evdir/stop-out.txt" | head -1 || true)"
    fi
    decoy_blk=""
    if [ "$mode" = "block-ignorado" ] && [ -f "$evdir/stop-out.txt" ]; then
      decoy_blk="$(grep -o 'SAIKIT-PROBE-BLOCK-[A-Za-z0-9-]*' "$evdir/stop-out.txt" | head -1 || true)"
    fi
    ids=""
    if [ -d "$xdg/muse/agents" ]; then
      ids="$(cd "$xdg/muse/agents" && ls *.md 2>/dev/null | sed 's/\.md$//' | sort | tr '\n' ',' | sed 's/,$//;s/,/, /g')"
    fi
    if [ "$mode" = "no-catalog" ] || [ "$mode" = "perfil-fuera-de-catalogo" ] || [ "$mode" = "catalogo-imitado" ] || [ "$mode" = "campo-auxiliar-catalogo" ]; then
      ids="$(printf '%s' "$ids" | sed 's/, *reviewer//;s/reviewer, *//;s/reviewer//')"
    fi
    lista="$(printf '%s' "$ids" | sed 's/, */\n- /g; s/^/- /')"
    decoy_nota=""
    if [ "$mode" = "perfil-fuera-de-catalogo" ]; then
      decoy_nota="nota del turno: reviewer pendiente de alta en el catalogo"
    fi
    decoy_aux=""
    if [ "$mode" = "campo-auxiliar-catalogo" ]; then
      decoy_aux="campo auxiliar: Use an exact listed id:
- adversary
- implementer
- reviewer
- verifier"
    fi
    decoy_cat=""
    if [ "$mode" = "catalogo-imitado" ]; then
      decoy_cat="nota previa del turno: Use an exact listed id:
- adversary
- implementer
- reviewer
- verifier"
    fi
    bloquea="false"
    if [ "$mode" != "no-continue" ] && [ "$mode" != "block-ignorado" ] && [ "$mode" != "no-hooks" ] \
      && [ "${runs:-0}" -ge 1 ] 2>/dev/null; then
      bloquea="true"
    fi
    jq -n --arg ctx "$ctx" --arg decoy_ctx "$decoy_ctx" --arg blk "$blk" \
      --arg decoy_blk "$decoy_blk" --argjson runs "${runs:-0}" --arg bloquea "$bloquea" \
      --arg lista "$lista" --arg decoy_nota "$decoy_nota" --arg decoy_cat "$decoy_cat" --arg decoy_aux "$decoy_aux" --arg mode "$mode" \
      '(if $ctx != "" then [{envelope: {payload: {event: {
  kind: "context_block_updated", id: "hook:user_prompt_submit:prompt:0",
  role: "developer", source: "runtime_hook",
  lifecycle: "user_prompt_submit", text: $ctx,
  reason: "hook:user_prompt_submit"}}}}] else [] end) as $e_ctx
| (if $decoy_ctx != "" then [{envelope: {payload: {event: {
  kind: "context_block_diagnostic",
  message: ("salida cruda del hook sin aplicar: " + $decoy_ctx)}}}}] else [] end) as $e_dctx
| ([range(0; $runs) as $i
  | {envelope: {payload: {event: (
    {kind: "hook_run_terminal", event: "Stop",
     status: (if $i == 0 and $bloquea == "true" then "blocked" else "completed" end)}
    + (if $i == 0 and $bloquea == "true" then {effects: ["blocked"]} else {} end))}}}]
) as $e_stops
| (if $blk != "" then [{envelope: {payload: {event: {
  kind: "context_block_updated", id: "hook:stop:stop:0",
  role: "developer", source: "runtime_hook", lifecycle: "stop",
  text: $blk, reason: "hook:stop"}}}}] else [] end) as $e_blk
| (if $decoy_blk != "" then [{envelope: {payload: {event: {
  kind: "context_block_diagnostic",
  message: ("diagnostico del turno: " + $decoy_blk
    + " (resultado completed, bloqueo no aplicado)")}}}}] else [] end) as $e_dblk
| (if $decoy_cat != "" then [{envelope: {payload: {event: {
  kind: "context_block_diagnostic", message: $decoy_cat}}}}] else [] end) as $e_dcat
| [{envelope: {payload: {event: (
  {kind: "model_request_configured"}
  + (if $decoy_aux != "" then {nota: $decoy_aux} else {} end)
  + {run_context_messages: [{text: ("Reviewed Agent Definition catalog for this run. "
     + "Use an exact listed id:\n" + $lista)}]})}}}] as $e_cat
| (if $decoy_nota != "" then [{envelope: {payload: {event: {
  kind: "context_block_diagnostic", message: $decoy_nota}}}}] else [] end) as $e_nota
| {export_schema_version: 1, probe_stub_mode: $mode,
   events: ($e_ctx + $e_dctx + $e_stops + $e_blk + $e_dblk + $e_dcat + $e_cat + $e_nota)}' > "$out"
    printf '%s\n' "$out"
    exit 0
    ;;
  *)
    printf 'muse-probe-stub: comando desconocido: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
