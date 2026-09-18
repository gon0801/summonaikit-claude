#!/usr/bin/env bash
# Imita Muse 1.3.0-R3401.1 contra settings.json (validacion-settings.txt /
# validacion-pareada.txt). SAIKIT_MUSE_BIN apunta aca en CI.
# Medido el 2026-09-18 con el binario real: evento no arreglo, grupo no objeto,
# .hooks no arreglo y handler no objeto dan MalformedConfig y apagan TODOS los
# hooks (0 runnable, ninguna marca), igual que un grupo sin hooks.
set -u

settings="${XDG_CONFIG_HOME:-${HOME:-}/.config}/muse/settings.json"

malformed() {
  printf 'malformed settings file at %s: %s\n' "$settings" "$1" >&2
  exit 1
}

if [ ! -f "$settings" ] || [ ! -r "$settings" ]; then
  malformed "missing settings file"
fi

if ! jq -e . "$settings" >/dev/null 2>&1; then
  malformed "invalid JSON"
fi

sv="$(jq -r '.schema_version // empty' "$settings" 2>/dev/null || true)"
if [ -z "$sv" ]; then
  malformed "missing field \`schema_version\`"
fi
if [ "$sv" != "1" ]; then
  malformed "unsupported settings schema version $sv"
fi

# Eventos que 23.1 midio como reconocidos. Cualquier otra clave bajo hooks
# es UnsupportedEvent. La clave top-level "Hooks" (mayuscula) no se mira:
# el binario real la ignora y no registra nada.
soportados='SessionStart SessionEnd UserPromptSubmit PreToolUse PostToolUse Stop SubagentStart SubagentStop Notification PostToolUseFailure'

detalle=()
n_runnable=0
m_warning=0
abortar_todo=0
cmds_ss=()
cmds_ups=()
cmds_stop=()

es_soportado() {
  local e="$1" s
  for s in $soportados; do
    [ "$e" = "$s" ] && return 0
  done
  return 1
}

n_eventos="$(jq -r '(.hooks // {} | keys | length)' "$settings")"
idx=0
while [ "$idx" -lt "$n_eventos" ]; do
  evento="$(jq -r --argjson i "$idx" '(.hooks // {} | keys)[$i]' "$settings")"
  idx=$((idx + 1))
  if ! es_soportado "$evento"; then
    detalle+=("muse:   settings.json: UnsupportedEvent: unsupported hook event \`$evento\`")
    m_warning=$((m_warning + 1))
    continue
  fi
  ev_tipo="$(jq -r --arg ev "$evento" '.hooks[$ev] | type' "$settings")"
  if [ "$ev_tipo" != "array" ]; then
    detalle+=("muse:   settings.json: MalformedConfig: hook event \`$evento\` must be an array")
    m_warning=$((m_warning + 1))
    abortar_todo=1
    continue
  fi
  n_grupos="$(jq -r --arg ev "$evento" '(.hooks[$ev] // []) | length' "$settings")"
  g=0
  while [ "$g" -lt "$n_grupos" ]; do
    grupo_json="$(jq -c --arg ev "$evento" --argjson gi "$g" '(.hooks[$ev] // [])[$gi]' "$settings")"
    g=$((g + 1))
    g_tipo="$(printf '%s' "$grupo_json" | jq -r 'type')"
    if [ "$g_tipo" != "object" ]; then
      detalle+=("muse:   settings.json: MalformedConfig: hook matcher group must be an object, found a $g_tipo")
      m_warning=$((m_warning + 1))
      abortar_todo=1
      continue
    fi
    extra="$(printf '%s' "$grupo_json" | jq -r 'keys[] | select(. != "matcher" and . != "hooks")' 2>/dev/null || true)"
    if [ -n "$extra" ]; then
      campo="$(printf '%s' "$extra" | head -1)"
      detalle+=("muse:   settings.json: UnsupportedHandler: D66: unknown matcher-group field \`$campo\` may narrow execution, so this group is skipped")
      m_warning=$((m_warning + 1))
      continue
    fi
    tiene_hooks="$(printf '%s' "$grupo_json" | jq -r 'has("hooks")')"
    if [ "$tiene_hooks" != "true" ]; then
      detalle+=("muse:   settings.json: MalformedConfig: hook matcher group must declare \`hooks\`")
      m_warning=$((m_warning + 1))
      abortar_todo=1
      continue
    fi
    h_tipo="$(printf '%s' "$grupo_json" | jq -r '.hooks | type')"
    if [ "$h_tipo" != "array" ]; then
      detalle+=("muse:   settings.json: MalformedConfig: hook matcher group \`hooks\` must be an array, found a $h_tipo")
      m_warning=$((m_warning + 1))
      abortar_todo=1
      continue
    fi
    malo_h="$(printf '%s' "$grupo_json" | jq -r '[.hooks[] | select(type != "object") | type][0] // empty')"
    if [ -n "$malo_h" ]; then
      detalle+=("muse:   settings.json: MalformedConfig: hook handler must be an object, found a $malo_h")
      m_warning=$((m_warning + 1))
      abortar_todo=1
      continue
    fi
    n_cmds="$(printf '%s' "$grupo_json" | jq -r '(.hooks // []) | length')"
    n_runnable=$((n_runnable + n_cmds))
    c=0
    while [ "$c" -lt "$n_cmds" ]; do
      cmd="$(printf '%s' "$grupo_json" | jq -r --argjson ci "$c" '.hooks[$ci].command // empty')"
      c=$((c + 1))
      [ -n "$cmd" ] || continue
      case "$evento" in
        SessionStart) cmds_ss+=("$cmd") ;;
        UserPromptSubmit) cmds_ups+=("$cmd") ;;
        Stop) cmds_stop+=("$cmd") ;;
      esac
    done
  done
done

if [ "$m_warning" -gt 0 ]; then
  printf 'muse: Hooks: %s runnable · %s warning\n' "$n_runnable" "$m_warning" >&2
  for line in "${detalle[@]+"${detalle[@]}"}"; do
    printf '%s\n' "$line" >&2
  done
fi
printf 'muse: Agent delegation: auto unavailable: workspace is untrusted.\n' >&2

# El binario real ejecuta .mcpServers[].command al arrancar. El falso tambien,
# para que un candidato que no borre mcpServers deje marcas y el caso lo vea.
if jq -e '.mcpServers | type == "object"' "$settings" >/dev/null 2>&1; then
  while IFS= read -r mcp_cmd; do
    [ -n "$mcp_cmd" ] || continue
    bash -c "$mcp_cmd" >/dev/null 2>&1 || true
  done < <(jq -r '.mcpServers[]?.command // empty' "$settings")
fi

if [ "$abortar_todo" -eq 1 ]; then
  exit 0
fi

correr() {
  local cmd="$1"
  [ -n "$cmd" ] || return 0
  bash -c "$cmd" >/dev/null 2>&1 || true
}

for cmd in "${cmds_ss[@]+"${cmds_ss[@]}"}"; do correr "$cmd"; done
for cmd in "${cmds_ups[@]+"${cmds_ups[@]}"}"; do correr "$cmd"; done
for cmd in "${cmds_stop[@]+"${cmds_stop[@]}"}"; do correr "$cmd"; done
exit 0
