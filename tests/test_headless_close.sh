#!/usr/bin/env bash
# test_headless_close.sh — 20.15/20.16 TDD: sin glob, 6 etiquetas, aislamiento,
# timeout, binario ausente, close_type no fabricable, agents_seen no acredita.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_DIR/tools/headless-close.sh"
. "$REPO_DIR/tools/lib/headless_close_paths.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }

tmpdir=""
cleanup() { [ -n "$tmpdir" ] && rm -rf "$tmpdir"; }
trap cleanup EXIT
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/saikit-test-hc.XXXXXX")"

SIX='SUMMONAIKIT HARNESS RECEIPT
Understand: pedido de prueba
Implement: sin cambios
Verify: not run — mock
Review: no findings
Close: TRAIL SKIP: mock
Retro: none
'

make_mock() {
  cat > "$1" << 'MOCK'
#!/usr/bin/env python3
import json, os, pathlib, sys, time
sid = os.environ.get("SAIKIT_MOCK_SESSION_ID", "sess-a")
state = os.environ.get("SAIKIT_MOCK_STATE_PATH", "")
if state:
    p = pathlib.Path(state)
    p.parent.mkdir(parents=True, exist_ok=True)
    agents = os.environ.get("SAIKIT_MOCK_AGENTS", "implementer,verifier,reviewer")
    p.write_text("task_hash=abc\ncycle=1\nagents_seen=%s\n" % agents, encoding="utf-8")
    ev = os.environ.get("SAIKIT_MOCK_EVIDENCE", "none")
    log = p.parent / "harness-evidence.log"
    if ev == "complete":
        log.write_text(os.environ.get("SAIKIT_MOCK_SIX", ""), encoding="utf-8")
    elif ev == "incomplete":
        log.write_text("agents only, no labels\n", encoding="utf-8")
if os.environ.get("SAIKIT_MOCK_JSON", "ok") == "ok":
    sys.stdout.write(json.dumps({"session_id": sid, "result": "mock"}) + "\n")
else:
    sys.stdout.write("not-json\n")
sys.stdout.flush()
time.sleep(float(os.environ.get("SAIKIT_MOCK_SLEEP", "0") or "0"))
sys.exit(int(os.environ.get("SAIKIT_MOCK_RC", "0") or "0"))
MOCK
  chmod +x "$1"
}

run_l() {
  ( cd "$td" && "$@" )
}

if [ -x "$LAUNCHER" ]; then ok "launcher ejecutable"; else bad "launcher no ejecutable"; fi

if "$LAUNCHER" >/dev/null 2>&1; then bad "sin args debería ser 2"
else rc=$?; [ "$rc" -eq 2 ] && ok "sin args → 2" || bad "sin args → $rc"; fi

if "$LAUNCHER" --host fake -- "x" >/dev/null 2>&1; then bad "host fake debería ser 2"
else rc=$?; [ "$rc" -eq 2 ] && ok "host fake → 2" || bad "host fake → $rc"; fi

if SAIKIT_CLAUDE_BIN="/nonexistent/claude" "$LAUNCHER" --host claude -- "x" >/dev/null 2>&1; then
  bad "binario ausente no debe ser 0"
else
  rc=$?; [ "$rc" -eq 2 ] && ok "binario ausente → 2" || bad "binario ausente → $rc"
fi

if "$LAUNCHER" --close-type forced -- "x" >/dev/null 2>&1; then bad "--close-type debería rechazarse"
else rc=$?; [ "$rc" -eq 2 ] && ok "--close-type rechazado" || bad "--close-type → $rc"; fi

td="$tmpdir/proj"
hook="$tmpdir/hooks"
mkdir -p "$td" "$hook" "$td/bin"
make_mock "$td/bin/mock-claude"
export SAIKIT_HOOK_DIR="$hook"
export SAIKIT_CLAUDE_BIN="$td/bin/mock-claude"
export SAIKIT_MOCK_SIX="$SIX"

sid="abc-123"
state="$(headless_state_path claude "$td" "$sid")"

rc=0
SAIKIT_MOCK_SESSION_ID="$sid" SAIKIT_MOCK_STATE_PATH="$state" SAIKIT_MOCK_EVIDENCE=complete \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "prompt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$state" ]; then ok "leftover + 6 etiquetas → 0 y limpia"
else bad "leftover completo rc=$rc"; fi

state="$(headless_state_path claude "$td" "$sid")"
rc=0
SAIKIT_MOCK_SESSION_ID="$sid" SAIKIT_MOCK_STATE_PATH="$state" SAIKIT_MOCK_EVIDENCE=incomplete \
SAIKIT_MOCK_AGENTS="implementer,verifier,reviewer" \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "prompt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && [ ! -f "$state" ]; then ok "agents_seen no acredita → 1 y limpia"
else bad "mutante agents_seen rc=$rc"; fi

rc=0
out="$(SAIKIT_MOCK_SESSION_ID="$sid" SAIKIT_MOCK_STATE_PATH="" SAIKIT_MOCK_EVIDENCE=none \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "prompt" 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'close_type=clean'; then ok "sin leftover → 0 clean"
else bad "sin leftover rc=$rc"; fi

sid_a="sess-A"; sid_b="sess-B"
state_a="$(headless_state_path claude "$td" "$sid_a")"
state_b="$(headless_state_path claude "$td" "$sid_b")"
mkdir -p "$(dirname "$state_b")"
printf 'orphan=1\n' > "$state_b"
rc=0
SAIKIT_MOCK_SESSION_ID="$sid_a" SAIKIT_MOCK_STATE_PATH="$state_a" SAIKIT_MOCK_EVIDENCE=incomplete \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "prompt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ] && [ ! -f "$state_a" ] && [ -f "$state_b" ]; then ok "aislamiento: sibling intacta"
else bad "aislamiento rc=$rc a=$( [ -f "$state_a" ] && echo live || echo gone ) b=$( [ -f "$state_b" ] && echo live || echo gone )"; fi

printf 'keep=1\n' > "$state_b"
rc=0
SAIKIT_MOCK_JSON=bad SAIKIT_MOCK_SESSION_ID="$sid_a" SAIKIT_MOCK_STATE_PATH="" \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "prompt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 3 ] && [ -f "$state_b" ]; then ok "json no observable → 3 y no glob"
else bad "unknown json rc=$rc sibling=$( [ -f "$state_b" ] && echo live || echo gone )"; fi

state="$(headless_state_path claude "$td" "$sid")"
rc=0
SAIKIT_MOCK_SESSION_ID="$sid" SAIKIT_MOCK_STATE_PATH="$state" SAIKIT_MOCK_SLEEP=5 \
SAIKIT_MOCK_EVIDENCE=incomplete SAIKIT_MOCK_JSON=ok \
run_l "$LAUNCHER" --host claude --project-root "$td" --timeout 1 -- "prompt" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then ok "timeout → 1 (host rc0 no acredita)"
else bad "timeout rc=$rc"; fi

got="$(headless_state_path claude "$td" "hello/../x")"
key="$(headless_session_key "hello/../x")"
pk="$(headless_project_key "$td")"
exp="$hook/state/claude/$pk/$key/harness-state.env"
if [ "$got" = "$exp" ]; then ok "STATE_PATH fórmula del hook"
else bad "path $got != $exp"; fi

argvdir="$tmpdir/argv"
mkdir -p "$argvdir"
cat > "$argvdir/recorder" << 'REC'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SAIKIT_ARGV_LOG:?}"
printf '{"session_id":"argv-probe","result":"ok"}\n'
exit 0
REC
chmod +x "$argvdir/recorder"

SAIKIT_ARGV_LOG="$argvdir/claude.argv"
export SAIKIT_ARGV_LOG
SAIKIT_CLAUDE_BIN="$argvdir/recorder" \
run_l "$LAUNCHER" --host claude --project-root "$td" -- "hola mundo" >/dev/null 2>&1 || true
if printf -- '-p\n--output-format\njson\nhola mundo\n' | diff - "$argvdir/claude.argv" >/dev/null; then
  ok "argv claude: -p booleano + prompt posicional"
else bad "argv claude: $(tr '\n' ' ' < "$argvdir/claude.argv")"; fi

SAIKIT_ARGV_LOG="$argvdir/grok.argv"
SAIKIT_GROK_BIN="$argvdir/recorder" \
run_l "$LAUNCHER" --host grok --project-root "$td" -- "hola mundo" >/dev/null 2>&1 || true
if printf -- '--single\nhola mundo\n--output-format\njson\n' | diff - "$argvdir/grok.argv" >/dev/null; then
  ok "argv grok: prompt como valor de --single (1.0.25)"
else bad "argv grok: $(tr '\n' ' ' < "$argvdir/grok.argv")"; fi

# ---- 20.16: mutantes de fuente (el mutante de fuente que faltaba) ----
# Idioma de tests/test_saikit_merge.sh:1302 (mut_sed + correr_mutacion): cmp
# canda la mutacion vacua (un sed que no ata acredita en falso), bash -n que
# el mutante parsee, control sano primero (un caso siempre-rojo atraparia por
# la razon equivocada) y el caso tiene que ponerse rojo contra el mutado por
# COMPORTAMIENTO del codigo bajo prueba, no por no poder correr.
#
# La copia mutada vive en $MUT_LAUNCH_DIR con lib/ como symlink al repo: el
# launcher resuelve su lib desde su propio SCRIPT_DIR y una copia suelta en
# TMPDIR moriria en el source — un mutado que no corre no prueba nada (misma
# trampa que documenta mut_sed del merge). El chmod es porque el redirect de
# sed no conserva el bit ejecutable y el launcher se ejecuta directo.
MUT_LAUNCH_DIR="$tmpdir/mut"
mkdir -p "$MUT_LAUNCH_DIR/lib"
ln -s "$REPO_DIR/tools/lib/headless_close_paths.sh" "$MUT_LAUNCH_DIR/lib/headless_close_paths.sh"

MUTADO=""
HC="$LAUNCHER"
CASO_ROJO=0

mut_sed() {  # $1=sed-expr, aplica sobre el fuente y deja el mutado en $MUTADO
  MUTADO="$MUT_LAUNCH_DIR/headless-close-mut.sh"
  sed "$1" "$LAUNCHER" > "$MUTADO"
  chmod +x "$MUTADO"
}

# Caso de aislamiento con la hermana MAS NUEVA: el glob por mtime tiene que
# elegirla a ella. touch -t en vez de sleep para orden determinista.
mc_aislamiento() {
  CASO_ROJO=0
  local mtd="$tmpdir/mut-aisla" mhook="$tmpdir/mut-aisla-hooks"
  rm -rf "$mtd" "$mhook"
  mkdir -p "$mtd" "$mhook" "$mtd/bin"
  make_mock "$mtd/bin/mock-claude"
  local sid_a="mut-sess-A" sid_b="mut-sess-B" sa sb rc
  sa="$(SAIKIT_HOOK_DIR="$mhook" headless_state_path claude "$mtd" "$sid_a")"
  sb="$(SAIKIT_HOOK_DIR="$mhook" headless_state_path claude "$mtd" "$sid_b")"
  mkdir -p "$(dirname "$sa")" "$(dirname "$sb")"
  printf 'task_hash=abc\ncycle=1\nagents_seen=implementer\n' > "$sa"
  printf 'orphan=1\n' > "$sb"
  touch -t 202001010000 "$sa"
  touch -t 203001010000 "$sb"
  rc=0
  ( cd "$mtd" && SAIKIT_HOOK_DIR="$mhook" SAIKIT_CLAUDE_BIN="$mtd/bin/mock-claude" \
    SAIKIT_MOCK_SIX="$SIX" SAIKIT_MOCK_SESSION_ID="$sid_a" SAIKIT_MOCK_STATE_PATH="" \
    SAIKIT_MOCK_EVIDENCE=none \
    "$HC" --host claude --project-root "$mtd" -- "prompt" >/dev/null 2>&1 ) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -f "$sa" ] && [ -f "$sb" ]; then
    return 0
  fi
  CASO_ROJO=1
  return 0
}

# Caso de leftover sin recibo: host rc=0 no acredita, agents_seen tampoco.
mc_leftover() {
  CASO_ROJO=0
  local mtd="$tmpdir/mut-left" mhook="$tmpdir/mut-left-hooks"
  rm -rf "$mtd" "$mhook"
  mkdir -p "$mtd" "$mhook" "$mtd/bin"
  make_mock "$mtd/bin/mock-claude"
  local sid="mut-leftover" sp rc
  sp="$(SAIKIT_HOOK_DIR="$mhook" headless_state_path claude "$mtd" "$sid")"
  rc=0
  ( cd "$mtd" && SAIKIT_HOOK_DIR="$mhook" SAIKIT_CLAUDE_BIN="$mtd/bin/mock-claude" \
    SAIKIT_MOCK_SIX="$SIX" SAIKIT_MOCK_SESSION_ID="$sid" SAIKIT_MOCK_STATE_PATH="$sp" \
    SAIKIT_MOCK_EVIDENCE=incomplete SAIKIT_MOCK_AGENTS="implementer,verifier,reviewer" \
    "$HC" --host claude --project-root "$mtd" -- "prompt" >/dev/null 2>&1 ) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -f "$sp" ]; then
    return 0
  fi
  CASO_ROJO=1
  return 0
}

correr_mutacion() {  # $1=nombre, $2=sed-expr, $3=funcion de caso
  local nombre="$1" expr="$2" fun="$3" ctrl
  mut_sed "$expr"
  if cmp -s "$LAUNCHER" "$MUTADO"; then
    bad "mutacion $nombre no cambio nada — el sed quedo obsoleto"
    return 0
  fi
  if ! bash -n "$MUTADO" 2>/dev/null; then
    bad "mutacion $nombre no parsea; asi no prueba nada"
    return 0
  fi
  ctrl="$MUTADO.control"
  HC="$LAUNCHER"
  CASO_ROJO=0
  "$fun" >"$ctrl" 2>&1
  if [ "$CASO_ROJO" -ne 0 ]; then
    bad "mutacion $nombre: control sano fallo — el caso ya esta rojo contra el fuente SANO; NO acredita mutante"
    cat "$ctrl"
    rm -f "$ctrl" "$MUTADO"
    HC="$LAUNCHER"
    return 0
  fi
  rm -f "$ctrl"
  HC="$MUTADO"
  CASO_ROJO=0
  "$fun" >"$ctrl" 2>&1
  if [ "$CASO_ROJO" -ne 0 ]; then
    ok "mutacion $nombre atrapada por $fun"
  else
    bad "ningun caso detecto la mutacion [$nombre]"
  fi
  rm -f "$ctrl" "$MUTADO"
  HC="$LAUNCHER"
  return 0
}

# Mutante 1: volver al glob por mtime — la hermana mas nueva se borra.
correr_mutacion "glob-mtime" \
  's#STATE_PATH="$(headless_state_path "$HOST" "$PROJECT_ROOT" "$SESSION_ID")"#STATE_PATH="$(ls -t "$(headless_hook_dir "$HOST")/state/$HOST/$(headless_project_key "$PROJECT_ROOT")"/*/harness-state.env 2>/dev/null | head -n 1)"#' \
  mc_aislamiento

# Mutante 2: aceptar agents_seen como recibo — el leftover sin recibo deja exit 1.
correr_mutacion "agents-seen" \
  's#if has_six_labels "$blob"; then COMPLETE=1; fi#if has_six_labels "$blob" || grep -Eq "agents_seen=.*implementer" "$STATE_PATH" 2>/dev/null; then COMPLETE=1; fi#' \
  mc_leftover

# Mutante 3: contar host_rc=0 como exito ignorando el leftover — rojo en el mismo caso.
correr_mutacion "host-rc0" \
  's#if \[ "$COMPLETE" -eq 1 \]; then#if [ "$COMPLETE" -eq 1 ] || [ "$HOST_RC" -eq 0 ]; then#' \
  mc_leftover

printf '\n=== %d PASS / %d FAIL ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
