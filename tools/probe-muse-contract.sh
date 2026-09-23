#!/usr/bin/env bash
# probe-muse-contract.sh — probe gratis del contrato de Muse (Task 23.5).
#
# Por que existe: Muse se autoactualiza al arrancar, asi que el contrato que
# el gate necesita puede cambiar sin que nadie lo decida. Este probe lo
# re-mide con el proveedor echo (sin red de modelo, sin costo) y reporta la
# version del binario mas un veredicto por punto:
#   P1 hooks de usuario disparan (SessionStart, UserPromptSubmit, Stop)
#   P2 additionalContext del UserPromptSubmit aparece en el export
#   P3 el Stop bloquea (decision:block) y el turno continua (segunda pasada)
#   P4 los cuatro perfiles (implementer, verifier, reviewer, adversary)
#      entran al catalogo del turno
#
# Todo corre aislado: caja mktemp fuera de un repo git, cinco variables
# (HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME, XDG_CACHE_HOME),
# cwd no-git, y el binario por ruta absoluta resuelta ANTES de aislar (nunca
# el lanzador ~/.local/bin/muse). No lee ni escribe el perfil real, no toca
# hooks/ ni la golden. Los perfiles medidos son los que instala
# tools/install-hook.sh --host muse en la caja (instalacion en dos pasos,
# igual que en produccion); el settings instalado se reescribe con los
# comandos del probe via jq (matchers y timeouts intactos).
#
# Cableado (decidido 23.5): paso del --check SIN host de install-hook.sh
# (no hay comando doctor en tools/). Fail-open: sin binario, o si el
# instalador no mide en la caja, el veredicto es unknown (exit 4) y el check
# no falla; con el contrato roto (exit 1) el check si falla.
#
# Salida: lineas probe-muse: punto=<P1..P4|version> veredicto=<pass|fail|unknown>
# detalle=... Exit: 0 todo pass; 1 algun fail; 4 unknown (sin binario o sin
# medicion). Costuras: SAIKIT_MUSE_BIN (binario o doble), SAIKIT_PROBE_NONCE,
# SAIKIT_PROBE_KEEP=1 (conserva la caja para depurar).
#
# Lo que queda unknown a proposito (lo vivo es del lead): la aceptacion del
# despacho con modelo real (echo no detecta unknown_tool, medido 23.1), la
# semantica exacta del matcher con nombres de Claude, SubagentStop con
# continuacion, y Windows (solo macOS medido).
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

decir() { printf 'probe-muse: %s\n' "$*"; }

# --- binario (via rapida unknown: sin binario no hay medicion) ---
MUSE=""
if [ "${SAIKIT_MUSE_BIN+set}" = "set" ]; then
  [ -n "$SAIKIT_MUSE_BIN" ] && [ -f "$SAIKIT_MUSE_BIN" ] && MUSE="$SAIKIT_MUSE_BIN"
else
  vf="${HOME:-}/.local/bin/.muse-version"
  if [ -f "$vf" ]; then
    ver="$(tr -d '[:space:]' < "$vf")"
    [ -n "$ver" ] && [ -f "${HOME:-}/.local/bin/muse-bin-$ver" ] && MUSE="${HOME:-}/.local/bin/muse-bin-$ver"
  fi
fi
if [ -z "$MUSE" ]; then
  decir "punto=version veredicto=unknown detalle=no hay binario de Muse (corrida del lead)"
  exit 4
fi
command -v jq >/dev/null 2>&1 || { decir "punto=version veredicto=unknown detalle=sin jq no se arma la caja"; exit 4; }

version="$("$MUSE" --version 2>/dev/null | head -1 || true)"
[ -n "$version" ] || { decir "punto=version veredicto=unknown detalle=el binario no reporta version"; exit 4; }
decir "punto=version veredicto=pass detalle=$version"

nonce="${SAIKIT_PROBE_NONCE:-$(date +%s)-$$}"
ctx_marca="SAIKIT-PROBE-CTX-$nonce"
blk_marca="SAIKIT-PROBE-BLOCK-$nonce"

# --- caja aislada ---
caja="$(mktemp -d "${TMPDIR:-/tmp}/saikit-probe-muse-XXXXXX")" || { decir "punto=P1 veredicto=unknown detalle=no se pudo crear la caja"; exit 4; }
if [ "${SAIKIT_PROBE_KEEP:-0}" = "1" ]; then
  decir "punto=caja veredicto=pass detalle=caja conservada en $caja"
else
  trap 'rm -rf "$caja"' EXIT
fi
home="$caja/home"; work="$caja/work"; xdg="$caja/xdg"
mkdir -p "$home" "$work" "$xdg/muse" "$caja/data" "$caja/state" "$caja/cache" "$caja/marks"
marks="$caja/marks"

# Hook del probe: deja huella en $marks y emite el contrato que se mide.
# Heredoc citado: nada se expande al escribir; el nonce llega por entorno.
phook="$caja/probe-hook.sh"
cat > "$phook" <<'HOOKEOF'
#!/usr/bin/env bash
set -u
M="${SAIKIT_PROBE_MARKS:-}"
MODE="${SAIKIT_PROBE_MODE:-x}"
N="${SAIKIT_PROBE_NONCE:-x}"
inp="$(cat)"
n=0
while [ -f "$M/$MODE-$n.json" ]; do n=$((n + 1)); done
[ -n "$M" ] && [ -d "$M" ] && { printf '%s' "$inp" > "$M/$MODE-$n.json"; touch "$M/$MODE"; }
case "$MODE" in
  ups) printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"SAIKIT-PROBE-CTX-%s"}}' "$N"; exit 0 ;;
  stop)
    if [ ! -f "$M/stop-blocked" ]; then
      touch "$M/stop-blocked"
      printf '{"decision":"block","reason":"SAIKIT-PROBE-BLOCK-%s"}' "$N"; exit 0
    fi
    printf '{}'; exit 0 ;;
  *) printf '{}'; exit 0 ;;
esac
HOOKEOF
chmod +x "$phook"

E="HOME=$home XDG_CONFIG_HOME=$xdg XDG_DATA_HOME=$caja/data XDG_STATE_HOME=$caja/state XDG_CACHE_HOME=$caja/cache SAIKIT_MUSE_BIN=$MUSE PATH=/opt/homebrew/bin:/usr/bin:/bin"

# --- perfiles + registro via el instalador (dos pasos, como en produccion) ---
# shellcheck disable=SC2086
if ! env $E bash "$repo/tools/install-hook.sh" >/dev/null 2>&1; then
  decir "punto=P1 veredicto=unknown detalle=el instalador no dejo la copia en la caja (corrida del lead)"
  exit 4
fi
# shellcheck disable=SC2086
if ! env $E bash "$repo/tools/install-hook.sh" --host muse >/dev/null 2>&1; then
  decir "punto=P1 veredicto=unknown detalle=--host muse no instalo en la caja (corrida del lead)"
  exit 4
fi

# --- reescribir los comandos con los del probe (matchers/timeouts intactos) ---
settings="$xdg/muse/settings.json"
[ -f "$settings" ] || { decir "punto=P1 veredicto=unknown detalle=sin settings en la caja"; exit 4; }
swap() { # $1=evento $2=modo
  jq --arg ev "$1" --arg cmd "SAIKIT_PROBE_MODE=$2 SAIKIT_PROBE_MARKS=$marks SAIKIT_PROBE_NONCE=$nonce $phook" \
    '.hooks[$ev] |= map(.hooks |= map(if (.command // "") != "" then .command = $cmd else . end))' \
    "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
}
true_cmd="/usr/bin/true"
jq --arg t "$true_cmd" \
  '.hooks["PreToolUse"] |= map(.hooks |= map(.command = $t)) | .hooks["PostToolUse"] |= map(.hooks |= map(.command = $t))' \
  "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
swap SessionStart ss
swap UserPromptSubmit ups
swap Stop stop

# --- turno echo + export ---
# shellcheck disable=SC2086
if ! env $E "$MUSE" exec --provider echo --json "hola probe 23.5 $nonce" >/dev/null 2>&1; then
  decir "punto=P1 veredicto=unknown detalle=el turno echo no corrio (corrida del lead)"
  exit 4
fi
exp="$caja/export.json"
# shellcheck disable=SC2086
if ! env $E "$MUSE" export --last --out "$exp" >/dev/null 2>&1 || [ ! -f "$exp" ]; then
  decir "punto=P2 veredicto=unknown detalle=sin export del turno (corrida del lead)"
  exit 4
fi

# --- veredictos ---
fallo=0
v() { # $1=punto $2=pass|fail $3=detalle
  decir "punto=$1 veredicto=$2 detalle=$3"
  [ "$2" = "fail" ] && fallo=1
  return 0
}

if [ -f "$marks/ss" ] && [ -f "$marks/ups" ] && [ -f "$marks/stop" ]; then
  v P1 pass "hooks disparan (SessionStart, UserPromptSubmit, Stop dejan marca)"
else
  v P1 fail "faltan marcas: ss=$([ -f "$marks/ss" ] && echo si || echo no) ups=$([ -f "$marks/ups" ] && echo si || echo no) stop=$([ -f "$marks/stop" ] && echo si || echo no)"
fi

# P2: la marca solo vale dentro del additionalContext que inyecto el hook
# (context_block_updated de source runtime_hook). Buscarla en todo el
# documento aceptaria un contrato roto (vuelta 1 de revision).
if jq -e --arg m "$ctx_marca"   'any(.events[]?;
    (.envelope.payload.event.kind == "context_block_updated")
    and (.envelope.payload.event.source == "runtime_hook")
    and ((.envelope.payload.event.text // "") | contains($m)))'   "$exp" >/dev/null 2>&1; then
  v P2 pass "additionalContext del hook aparece en el export (context_block_updated de runtime_hook)"
else
  v P2 fail "ningun context_block_updated de runtime_hook trae $ctx_marca"
fi

# P3: bloqueo efectivo + motivo en su campo + segunda pasada. Contar dos
# invocaciones y buscar la razon en todo el documento aceptaria un host que
# ignora decision:block (vuelta 1 de revision).
stops=0
[ -f "$marks/stop-blocked" ] && stops="$(ls "$marks"/stop-*.json 2>/dev/null | wc -l | tr -d ' ')"
stop_terms="$(jq '[.events[]?
  | select(.envelope.payload.event.kind == "hook_run_terminal"
    and .envelope.payload.event.event == "Stop")] | length'   "$exp" 2>/dev/null || echo 0)"
bloqueo=0
jq -e '.events[]?
  | select(.envelope.payload.event.kind == "hook_run_terminal"
    and .envelope.payload.event.event == "Stop"
    and .envelope.payload.event.status == "blocked")'   "$exp" >/dev/null 2>&1 && bloqueo=1
motivo=0
jq -e --arg b "$blk_marca"   'any(.events[]?;
    (.envelope.payload.event.kind == "context_block_updated")
    and (.envelope.payload.event.source == "runtime_hook")
    and ((.envelope.payload.event.text // "") | contains($b)))'   "$exp" >/dev/null 2>&1 && motivo=1
if [ "$bloqueo" -eq 1 ] && [ "$motivo" -eq 1 ] && [ "${stop_terms:-0}" -ge 2 ] 2>/dev/null; then
  v P3 pass "el Stop bloquea (terminal blocked) y el turno continua ($stop_terms pasadas de Stop)"
else
  v P3 fail "bloqueo=$bloqueo motivo=$motivo pasadas=${stop_terms:-0} (se espera 1/1/>=2)"
fi

# P4: cada perfil como item "- <rol>" del mensaje del catalogo ("Use an
# exact listed id"). Buscar el nombre en todo el documento aceptaria un
# perfil ausente del catalogo con su nombre en un campo ajeno (vuelta 1).
# El catalogo vive en el evento model_request_configured: tomar el primer
# texto coincidente de todo el documento aceptaria una nota que imite la
# lista (vuelta 2 de revision).
catalogo="$(jq -r '[.events[]? | .envelope.payload.event
  | select(.kind == "model_request_configured")
  | .. | strings | select(contains("Use an exact listed id"))] | first // empty' \
  "$exp" 2>/dev/null)"
roles_ok=1
for r in implementer verifier reviewer adversary; do
  printf '%s\n' "$catalogo" | grep -q -- "- $r$" || { roles_ok=0; break; }
done
if [ "$roles_ok" -eq 1 ]; then
  v P4 pass "los cuatro perfiles entran al catalogo del turno"
else
  v P4 fail "el catalogo del export no lista los cuatro perfiles"
fi

decir "punto=despacho veredicto=unknown detalle=la aceptacion del despacho con modelo real la mide el lead (echo no detecta unknown_tool)"
decir "punto=matcher veredicto=unknown detalle=mecanismo del matcher con nombres de Claude no medido (el registro usa nombres de Muse)"

if [ "$fallo" -eq 1 ]; then
  decir "veredicto=fallo detalle=el contrato cambio: ver puntos con fail"
  exit 1
fi
decir "veredicto=ok detalle=version [$version], cuatro puntos en pass"
exit 0
