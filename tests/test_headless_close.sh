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

printf '\n=== %d PASS / %d FAIL ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
