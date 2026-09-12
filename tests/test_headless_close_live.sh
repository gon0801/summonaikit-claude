#!/usr/bin/env bash
# tests/test_headless_close_live.sh — 20.17 medicion viva + mocks.
#
# Dos carriles: mocks (siempre corren, con SAIKIT_HOOK_DIR al sandbox) y
# medicion viva (solo con perfil real: binario presente + SAIKIT_HOOK_DIR AUSENTE
# + hook instalado bajo el HOME actual). Sin binario (o sin hook, p.ej. bajo
# tests/run.sh donde el HOME es una caja): saikit_skip_caso, nunca PASS.
#
# Por que el prerequisito del hook: el hook instalado calcula su directorio
# desde su propia ruta, asi que con SAIKIT_HOOK_DIR a un sandbox el launcher
# miraria donde el hook nunca escribe y saldria clean siempre — una cadena
# falsa (medido 20.17). La medicion viva usa directorio de proyecto
# desechable: el PROJECT_KEY es el cksum de esa ruta, el estado aterriza bajo
# el state root real en su propio subdirectorio, y al terminar se borra ese
# subdirectorio (solo el propio) y se declara.
#
# Nota de argv: el prompt NUNCA empieza con `-` (medido 20.17: claude trata un
# prompt liderado por `-saikit:` como flag desconocido y muere con rc=1 sin
# JSON). El sentinel va tras "Task ". Para grok el prompt es valor de
# --single (1.0.25); ver el caso argv en tests/test_headless_close.sh.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
. "$here/lib/skip_caso.sh"
# El HOME real se captura ANTES del sandbox: los mocks corren aislados, pero
# la medicion viva exige el perfil real (el hook instalado calcula su
# directorio desde su propia ruta). Bajo tests/run.sh REAL_HOME es la caja
# (sin hook) y los 6 casos vivos skipean; suelto con perfil real, miden.
REAL_HOME="$HOME"
sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }
ok()   { printf '    ok: %s\n' "$1"; }

LAUNCHER="$repo/tools/headless-close.sh"
. "$repo/tools/lib/headless_close_paths.sh"

SYNC_P='Task -saikit: reply with exactly the word pong on the first line. Then emit the harness receipt block exactly in this shape, one label per line, values brief: SUMMONAIKIT HARNESS RECEIPT / Understand: trivial echo request / Implement: no changes made / Verify: not run / Review: no findings / Close: pong delivered / Retro: none. Do not use any tools. Keep the whole reply under 15 lines.'
ASYNC_P='Task -saikit: use the Task tool to dispatch exactly one subagent to compute the product of 37 by 41 and report back just the number. Use Task only, do not compute it yourself. When the subagent answers, reply with exactly this first line: delegated:<the number it reported>. Then emit the harness receipt block exactly in this shape, one label per line, values brief: SUMMONAIKIT HARNESS RECEIPT / Understand: async delegation of a multiplication / Implement: dispatched one Task subagent, reported its answer / Verify: subagent answer matches delegated:<number> / Review: no findings / Close: async delegation complete / Retro: none. Keep the whole reply under 20 lines.'
TEARDOWN_P='Task -saikit: count from 1 to 3000, one number per line, nothing else. Do not use any tools.'

MOCKHOOK="$SANDBOX/mockhooks"
mkdir -p "$MOCKHOOK/state" "$SANDBOX/bin" "$SANDBOX/proj"
PROJECT_ROOT="$SANDBOX/proj"
mkdir -p "$PROJECT_ROOT"

caso "mock positivo: leftover+recibo => 0 forced (cadena host/hook/supervisor/estado)"
export SAIKIT_CLAUDE_BIN="$SANDBOX/bin/mock-live"
sid="live-pos"
sp="$(SAIKIT_HOOK_DIR="$MOCKHOOK" headless_state_path claude "$PROJECT_ROOT" "$sid")"
mkdir -p "$(headless_state_dir_of "$sp")"
printf 'cycle=1\n' > "$sp"
cat > "$(headless_state_dir_of "$sp")/harness-evidence.log" << 'LOG'
SUMMONAIKIT HARNESS RECEIPT
Understand: live
Implement: live
Verify: live
Review: live
Close: live
Retro: live
LOG
cat > "$SAIKIT_CLAUDE_BIN" << MOCK
#!/usr/bin/env bash
printf '%s\n' '{"session_id":"live-pos","result":"ok"}'
exit 0
MOCK
chmod +x "$SAIKIT_CLAUDE_BIN"
out="$(SAIKIT_HOOK_DIR="$MOCKHOOK" bash "$LAUNCHER" --host claude --project-root "$PROJECT_ROOT" -- hi 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "live-shaped positivo rc=$rc $out"
[ ! -f "$sp" ] || malo "estado vivo no limpiado"

caso "mock falta de recibo: host rc=0 => close exit 1 (NO ok)"
sid="live-miss"
sp="$(SAIKIT_HOOK_DIR="$MOCKHOOK" headless_state_path claude "$PROJECT_ROOT" "$sid")"
mkdir -p "$(headless_state_dir_of "$sp")"
printf 'cycle=1\n' > "$sp"
printf 'sin recibo\n' > "$(headless_state_dir_of "$sp")/harness-evidence.log"
cat > "$SAIKIT_CLAUDE_BIN" << MOCK
#!/usr/bin/env bash
printf '%s\n' '{"session_id":"live-miss","result":"host ok"}'
exit 0
MOCK
chmod +x "$SAIKIT_CLAUDE_BIN"
out="$(SAIKIT_HOOK_DIR="$MOCKHOOK" bash "$LAUNCHER" --host claude --project-root "$PROJECT_ROOT" -- hi 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "falta recibo debe FAIL close rc=$rc $out"
printf '%s' "$out" | grep -q 'close_type=incomplete' || malo "faltaba incomplete: $out"

caso "replay determinista: leftover genuino-sin-recibo + session_id observada => 1 incomplete y limpia"
sid="replay-sess"
sp="$(SAIKIT_HOOK_DIR="$MOCKHOOK" headless_state_path claude "$PROJECT_ROOT" "$sid")"
mkdir -p "$(headless_state_dir_of "$sp")"
printf 'task_hash=abc\ncycle=0\nagents_seen=\n' > "$sp"
printf 'prompt task started: abc\n' > "$(headless_state_dir_of "$sp")/harness-evidence.log"
cat > "$SANDBOX/bin/replayer" << MOCK
#!/usr/bin/env bash
printf '%s\n' '{"session_id":"replay-sess","result":"killed before Stop, no receipt"}'
exit 137
MOCK
chmod +x "$SANDBOX/bin/replayer"
export SAIKIT_HEADLESS_LAUNCH_COUNT="$SANDBOX/launch-count"
printf '0\n' > "$SANDBOX/launch-count"
out="$(SAIKIT_HOOK_DIR="$MOCKHOOK" SAIKIT_CLAUDE_BIN="$SANDBOX/bin/replayer" \
  bash "$LAUNCHER" --host claude --project-root "$PROJECT_ROOT" -- replay 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "replay debe dar 1, dio $rc: $out"
printf '%s' "$out" | grep -q 'close_type=incomplete' || malo "replay sin incomplete: $out"
[ ! -f "$sp" ] || malo "replay no limpio el leftover"
[ "$(cat "$SANDBOX/launch-count")" = "1" ] || malo "replay relanzo: $(cat "$SANDBOX/launch-count")"
unset SAIKIT_HEADLESS_LAUNCH_COUNT

caso "async no es un prompt bash: ni el launcher ni los prompts fingen delegacion"
if grep -Eiq 'async.*bash|prompt bash|fake async' "$LAUNCHER" "$repo/tests/test_headless_close.sh"; then
  malo "async fingido via bash en launcher o test base"
fi
if printf '%s\n' "$SYNC_P" "$ASYNC_P" "$TEARDOWN_P" | grep -Eiq 'bash|shell|sh -c'; then
  malo "un prompt vivo instruye shell en vez de delegacion por el canal del host"
fi

caso "invocacion directa del host queda fuera de garantia (documentada en contrato)"
[ -f "$repo/docs/spec/headless-close-contract.md" ] || malo "falta contrato"
grep -q 'fuera de garantia' "$repo/docs/spec/headless-close-contract.md" \
  || grep -qi 'fuera de garantía' "$repo/docs/spec/headless-close-contract.md" \
  || malo "contrato no declara invocacion directa fuera de garantia"

# ---- medicion viva (perfil real o skip) ----
# Prerequisitos por host; cada ausencia es skip con razon, nunca PASS.
# El orden importa: el override se rechaza aunque haya binario y hook.
# Deja el binario en $LIVE_BIN (NO se captura su salida: el aviso de skip va
# a stdout y una sustitucion $(...) se lo tragaría en silencio).
LIVE_BIN=""
live_prereq() {  # $1=host, $2=modo; 0 con $LIVE_BIN, 1 tras skip visible
  local host="$1" modo="$2" bin hookf
  case "$host" in
    claude)
      if [ -x /Users/dn/.local/bin/claude ]; then bin=/Users/dn/.local/bin/claude;
      elif command -v claude >/dev/null 2>&1; then bin="$(command -v claude)";
      else bin=""; fi ;;
    grok)
      if [ -x /opt/homebrew/bin/grok ]; then bin=/opt/homebrew/bin/grok;
      elif command -v grok >/dev/null 2>&1; then bin="$(command -v grok)";
      else bin=""; fi ;;
  esac
  if [ -z "$bin" ]; then
    saikit_skip_caso "live-$host-$modo" "binario $host ausente; skip no es PASS"
    return 1
  fi
  if [ -n "${SAIKIT_HOOK_DIR:-}" ]; then
    saikit_skip_caso "live-$host-$modo" "SAIKIT_HOOK_DIR fijado ($SAIKIT_HOOK_DIR); la medicion viva exige cadena verdadera sin override"
    return 1
  fi
  hookf="$REAL_HOME/.$host/hooks/summonaikit-harness.sh"
  if [ ! -f "$hookf" ]; then
    saikit_skip_caso "live-$host-$modo" "hook instalado ausente ($hookf; HOME de invocacion no es perfil real); skip no es PASS"
    return 1
  fi
  LIVE_BIN="$bin"
  return 0
}

# Limpieza del subdir propio (state/<host>/<pk>); solo el de esta corrida.
# Barre en el root del host Y en el de claude: medido 20.17, grok arma en
# AMBOS roots en cada corrida (doble disparo: la copia registrada .grok mas
# otra via que ejecuta la copia .claude con env de grok; mecanismo no
# determinado, ver evidencia 20.17). La llave es del proyecto desechable de
# esta corrida, asi que ningun turno ajeno puede vivir ahi.
live_cleanup() {  # $1=host, $2=pk
  rm -rf "$REAL_HOME/.$1/hooks/state/$1/$2" 2>/dev/null || true
  rm -rf "$REAL_HOME/.claude/hooks/state/$1/$2" 2>/dev/null || true
  printf '    subdir propio borrado: state/%s/%s (+ espejo claude)\n' "$1" "$2"
}

# Reporte tabular del modo: lo que la DoD pide citar por modo.
live_reporte() {  # $1=host $2=modo $3=host_rc $4=session $5=statepath $6=leftover $7=close $8=exit $9=count
  printf '    live %s/%s: host_rc=%s session=%s\n' "$1" "$2" "$3" "$4"
  printf '    live %s/%s: state=%s leftover=%s close=%s exit=%s lanzamientos=%s\n' \
    "$1" "$2" "$5" "$6" "$7" "$8" "$9"
}

# sync/async vivos: un lanzamiento, veredicto del supervisor sobre cadena real.
# rc=0 => exito con cadena (un lanzamiento, sin leftover); rc=3 => unknown del
# host (cuota/caida) declarado con salida literal, nunca PASS; otro rc => FAIL.
vivo_simple() {  # $1=host $2=modo $3=prompt
  local host="$1" modo="$2" prompt="$3" bin proj pk countf out rc close session sp
  live_prereq "$host" "$modo" || return 0
  bin="$LIVE_BIN"
  proj="$(mktemp -d "${TMPDIR:-/tmp}/saikit-live-XXXXXX")"
  # El PROJECT_ROOT tiene que viajar byte-identico por la cadena (medido
  # 20.17: el hook normaliza `//` a `/` y con TMPDIR con slash final el mktemp
  # deja `T//saikit-...`; sin squeeze el launcher mira una llave y el hook
  # escribe otra — clean accidental, cadena falsa).
  proj="$(printf '%s' "$proj" | tr -s /)"
  pk="$(printf '%s' "$proj" | cksum | cut -d ' ' -f 1)"
  countf="$proj/launch-count"
  printf '0\n' > "$countf"
  caso "vivo $host/$modo (proyecto desechable $proj)"
  if [ "$host" = "grok" ]; then
    out="$(cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      SAIKIT_GROK_BIN="$bin" SAIKIT_HEADLESS_LAUNCH_COUNT="$countf" \
      bash "$LAUNCHER" --host grok --project-root "$proj" --timeout 120 -- "$prompt" 2>&1)" && rc=0 || rc=$?
  else
    out="$(cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      SAIKIT_CLAUDE_BIN="$bin" SAIKIT_HEADLESS_LAUNCH_COUNT="$countf" \
      bash "$LAUNCHER" --host claude --project-root "$proj" --timeout 240 -- "$prompt" 2>&1)" && rc=0 || rc=$?
  fi
  close="$(printf '%s' "$out" | grep -o 'close_type=[a-z]*' | head -n 1)"
  session="$(printf '%s' "$out" | grep -o 'session=[A-Za-z0-9_-]*' | head -n 1)"
  [ -n "$session" ] || session="session=desconocida"
  sp="$REAL_HOME/.$host/hooks/state/$host/$pk"
  leftover="no"
  [ -z "$(find "$sp" -type f 2>/dev/null)" ] || leftover="si"
  live_reporte "$host" "$modo" "n/a (launcher)" "$session" "$sp" "$leftover" "$close" "$rc" "$(cat "$countf")"
  case "$rc" in
    0)
      [ "$(cat "$countf")" = "1" ] || malo "$host/$modo relanzo: $(cat "$countf")"
      [ "$leftover" = "no" ] || malo "$host/$modo dejo leftover"
      case "$close" in close_type=clean|close_type=forced) ok "$host/$modo cadena ok ($close)" ;;
        *) malo "$host/$modo close inesperado: $close" ;; esac ;;
    3) printf '    unknown declarado (salida literal):\n%s\n' "$out" ;;
    *) malo "$host/$modo rc=$rc: $out" ;;
  esac
  live_cleanup "$host" "$pk"
  rm -rf "$proj"
}

# teardown vivo: fase A mata el host antes del Stop; fase B observa el
# leftover genuino con la session_id vista en disco (replay, exit 137).
# Sin leftover (host muerto al arrancar, p.ej. 402): skip, el kill no aplica.
vivo_teardown() {  # $1=host
  local host="$1" bin proj pk pdir hpid hit waited skey hrc rep out rc kill_info
  live_prereq "$host" "teardown" || return 0
  bin="$LIVE_BIN"
  proj="$(mktemp -d "${TMPDIR:-/tmp}/saikit-live-XXXXXX")"
  # Ver nota del squeeze en vivo_simple: sin esto, cadena falsa por `//`.
  proj="$(printf '%s' "$proj" | tr -s /)"
  pk="$(printf '%s' "$proj" | cksum | cut -d ' ' -f 1)"
  pdir="$REAL_HOME/.$host/hooks/state/$host/$pk"
  caso "vivo $host/teardown (proyecto desechable $proj)"
  if [ "$host" = "grok" ]; then
    ( cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      "$bin" --single "$TEARDOWN_P" --output-format json >"$proj/host-out.log" 2>&1 ) &
  else
    ( cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      "$bin" -p --output-format json "$TEARDOWN_P" >"$proj/host-out.log" 2>&1 ) &
  fi
  hpid=$!
  hit=""
  waited=0
  while [ "$waited" -lt 60 ]; do
    sleep 1
    waited=$((waited + 1))
    hit="$(find "$pdir" -maxdepth 2 -name 'harness-state.env' 2>/dev/null | head -n 1)"
    [ -n "$hit" ] && break
    kill -0 "$hpid" 2>/dev/null || break
  done
  if [ -z "$hit" ]; then
    wait "$hpid" 2>/dev/null; hrc=$?
    printf '    host termino sin leftover observable (host_rc=%s); kill no aplica\n' "$hrc"
    printf '    salida literal del host:\n'; head -c 600 "$proj/host-out.log"; printf '\n'
    saikit_skip_caso "live-$host-teardown" "sin leftover (host_rc=$hrc); nada que matar ni observar"
    live_cleanup "$host" "$pk"
    rm -rf "$proj"
    return 0
  fi
  sleep 2
  if kill -9 "$hpid" 2>/dev/null; then kill_info="SIGKILL al host";
  else kill_info="host ya habia terminado al matar"; fi
  wait "$hpid" 2>/dev/null; hrc=$?
  skey="$(basename "$(dirname "$hit")")"
  printf '    teardown: %s (host_rc=%s), session observada=%s\n' "$kill_info" "$hrc" "$skey"
  if grep -Eq 'SUMMONAIKIT HARNESS RECEIPT|Understand:|Implement:|Verify:|Review:|Close:|Retro:' \
      "$pdir/$skey/harness-evidence.log" 2>/dev/null; then
    malo "$host/teardown: el leftover ya trae recibo; el kill llego tarde"
  fi
  cat > "$proj/replayer" << MOCK
#!/usr/bin/env bash
printf '%s\n' '{"session_id":"$skey","result":"killed before Stop, no receipt"}'
exit 137
MOCK
  chmod +x "$proj/replayer"
  printf '0\n' > "$proj/launch-count"
  if [ "$host" = "grok" ]; then
    out="$(cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      SAIKIT_GROK_BIN="$proj/replayer" SAIKIT_HEADLESS_LAUNCH_COUNT="$proj/launch-count" \
      bash "$LAUNCHER" --host grok --project-root "$proj" -- replay 2>&1)" && rc=0 || rc=$?
  else
    out="$(cd "$proj" && HOME="$REAL_HOME" USERPROFILE="$REAL_HOME" \
      SAIKIT_CLAUDE_BIN="$proj/replayer" SAIKIT_HEADLESS_LAUNCH_COUNT="$proj/launch-count" \
      bash "$LAUNCHER" --host claude --project-root "$proj" -- replay 2>&1)" && rc=0 || rc=$?
  fi
  live_reporte "$host" "teardown" "$hrc" "session=$skey" "$pdir/$skey/harness-state.env" \
    "si (fase A)" "$(printf '%s' "$out" | grep -o 'close_type=[a-z]*' | head -n 1)" "$rc" "$(cat "$proj/launch-count")"
  [ "$rc" -eq 1 ] || malo "$host/teardown fase B rc=$rc: $out"
  printf '%s' "$out" | grep -q 'close_type=incomplete' || malo "$host/teardown sin incomplete: $out"
  [ ! -f "$pdir/$skey/harness-state.env" ] || malo "$host/teardown no limpio la sesion"
  [ "$(cat "$proj/launch-count")" = "1" ] || malo "$host/teardown relanzo"
  live_cleanup "$host" "$pk"
  rm -rf "$proj"
}

# Foco para corridas caras: SAIKIT_LIVE_ONLY=claude/teardown corre solo ese
# modo (vacio = los seis). Bajo tests/run.sh no se fija nunca.
solo="${SAIKIT_LIVE_ONLY:-}"
[ -n "$solo" ] && printf '  foco vivo: %s\n' "$solo"
run_simple() { [ -z "$solo" ] || [ "$solo" = "$1/$2" ] || return 0; vivo_simple "$1" "$2" "$3"; }
run_teardown() { [ -z "$solo" ] || [ "$solo" = "$1/teardown" ] || return 0; vivo_teardown "$1"; }
run_simple claude sync "$SYNC_P"
run_simple claude async "$ASYNC_P"
run_teardown claude
run_simple grok sync "$SYNC_P"
run_simple grok async "$ASYNC_P"
run_teardown grok

if [ "$fail" -ne 0 ]; then
  echo "test_headless_close_live: FAIL" >&2
  exit 1
fi
echo "test_headless_close_live: OK"
exit 0
