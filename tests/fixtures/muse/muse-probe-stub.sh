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
    if [ "$mode" != "no-ctx" ] && [ -f "$evdir/ups-out.txt" ]; then
      ctx="$(grep -o 'SAIKIT-PROBE-CTX-[A-Za-z0-9-]*' "$evdir/ups-out.txt" | head -1 || true)"
    fi
    blk=""
    runs="0"
    [ -f "$evdir/stop-runs.txt" ] && runs="$(cat "$evdir/stop-runs.txt")"
    if [ -f "$evdir/stop-out.txt" ]; then
      blk="$(grep -o 'SAIKIT-PROBE-BLOCK-[A-Za-z0-9-]*' "$evdir/stop-out.txt" | head -1 || true)"
    fi
    ids=""
    if [ -d "$xdg/muse/agents" ]; then
      ids="$(cd "$xdg/muse/agents" && ls *.md 2>/dev/null | sed 's/\.md$//' | sort | tr '\n' ',' | sed 's/,$//;s/,/, /g')"
    fi
    if [ "$mode" = "no-catalog" ]; then
      ids="$(printf '%s' "$ids" | sed 's/, *reviewer//;s/reviewer, *//;s/reviewer//')"
    fi
    activa="false"
    [ "$runs" -ge 2 ] 2>/dev/null && activa="true"
    jq -n --arg ctx "$ctx" --arg blk "$blk" --argjson runs "${runs:-0}" \
      --argjson sha "$activa" --arg ids "$ids" --arg mode "$mode" \
      '{export_schema_version: 1,
        probe_stub_mode: $mode,
        context_block_updated: (if $ctx == "" then [] else [{source: "runtime_hook", text: $ctx}] end),
        stop_evidence: {reason: $blk, passes: $runs, stop_hook_active: $sha},
        catalog: ("Use an exact listed id: " + $ids)}' > "$out"
    printf '%s\n' "$out"
    exit 0
    ;;
  *)
    printf 'muse-probe-stub: comando desconocido: %s\n' "$cmd" >&2
    exit 2
    ;;
esac
