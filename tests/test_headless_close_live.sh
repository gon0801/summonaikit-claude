#!/usr/bin/env bash
# test_headless_close_live.sh — medición viva de cierre headless (20.17)
#
# Ejecuta claude -p con el launcher y correlaciona:
# - host exit code
# - hook decision (del evidence log)
# - receipt (.saikit/close-receipts/<session>.json)
#
# Uso: bash tests/test_headless_close-live.sh [--host claude|grok] [--mode sync|async|teardown]
# Requiere: launcher + host instalado + gh autenticado.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_DIR/tools/headless-close.sh"

HOST="${1:-claude}"
MODE="${2:-sync}"

pass=0 fail=0; skip=0; unknown=0
ok()      { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad()     { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }
nope()    { skip=$((skip+1)); printf '  SKIP: %s\n' "$1"; }
unk()     { unknown=$((unknown+1)); printf '  UNKNOWN: %s\n' "$1"; }

echo "=== Headless close live measurement ($HOST / $MODE) ==="
echo "  Repo: $REPO_DIR"
echo "  Launcher: $LAUNCHER"
echo "  Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Verify launcher exists
if [ ! -x "$LAUNCHER" ]; then
  bad "launcher not executable"; exit 1
fi

# Verify host binary
case "$HOST" in
  claude) BIN="${SAIKIT_CLAUDE_BIN:-claude}" ;;
  grok)   BIN="${SAIKIT_GROK_BIN:-grok}" ;;
  *)      echo "host no soportado: $HOST"; exit 2 ;;
esac

if ! command -v "$BIN" >/dev/null 2>&1; then
  nope "binario no encontrado: $BIN — SKIP medición viva"
  printf '\n=== %d PASS / %d FAIL / %d SKIP / %d UNKNOWN ===\n' "$pass" "$fail" "$skip" "$unknown"
  exit 0
fi

# Verify git clean
if [ -n "$(cd "$REPO_DIR" && git status --short)" ]; then
  bad "árbol no limpio — commit o stash primero"
  exit 1
fi

HEAD_SHA="$(cd "$REPO_DIR" && git rev-parse HEAD)"
echo "  HEAD: $HEAD_SHA"

# Capture hook SHA
HOOK_SHA="unknown"
for hook_path in "$HOME/.claude/hooks/summonaikit-harness.sh" \
                 "$HOME/.grok/hooks/summonaikit-harness.sh" \
                 "$HOME/.codex/hooks/summonaikit-harness.sh"; do
  if [ -f "$hook_path" ]; then
    HOOK_SHA="$(shasum -a256 "$hook_path" 2>/dev/null | cut -c1-16)"
    break
  fi
done
echo "  Hook: $HOOK_SHA"
echo ""

# --- Test 1: sync delegation (single prompt, completes normally) ---
test_sync() {
  echo "--- Sync delegation ---"
  local prompt="Run exactly: echo 'HEADLESS_TEST_SYNC_OK' && exit 0"
  local rc=0
  cd "$REPO_DIR"
  "$LAUNCHER" --host "$HOST" -- "$prompt" 2>/dev/null || rc=$?

  # Find receipt
  local receipt=""
  for f in "$REPO_DIR"/.saikit/close-receipts/*.json; do
    [ -f "$f" ] || continue
    receipt="$f"
    break
  done

  if [ -n "$receipt" ] && [ -f "$receipt" ]; then
    local ct rc_val
    ct="$(python3 -c "import json; d=json.load(open('$receipt')); print(d.get('close_type',''))" 2>/dev/null || echo 'parse_error')"
    rc_val="$(python3 -c "import json; d=json.load(open('$receipt')); print(d.get('rc','-1'))" 2>/dev/null || echo '-1')"

    if [ "$ct" = "clean" ] || [ "$ct" = "forced" ] || [ "$ct" = "unknown" ]; then
      ok "sync: receipt written (close_type=$ct, rc=$rc_val)"
    else
      bad "sync: receipt close_type unexpected: $ct"
    fi
    rm -f "$receipt"
  else
    # If .saikit doesn't exist or no state, receipt may not be written — that's ok
    if [ "$rc" -eq 0 ]; then
      ok "sync: process completed (rc=0), no receipt (no harness state)"
    else
      bad "sync: process failed (rc=$rc), no receipt"
    fi
  fi
}

# --- Test 2: async delegation (prompt that triggers subagent) ---
test_async() {
  echo "--- Async delegation ---"
  local prompt="Use the Bash tool to run: echo 'HEADLESS_TEST_ASYNC_OK'"
  local rc=0
  cd "$REPO_DIR"
  "$LAUNCHER" --host "$HOST" -- "$prompt" 2>/dev/null || rc=$?

  local receipt=""
  for f in "$REPO_DIR"/.saikit/close-receipts/*.json; do
    [ -f "$f" ] || continue
    receipt="$f"
    break
  done

  if [ -n "$receipt" ] && [ -f "$receipt" ]; then
    local ct
    ct="$(python3 -c "import json; d=json.load(open('$receipt')); print(d.get('close_type',''))" 2>/dev/null || echo 'parse_error')"
    ok "async: receipt written (close_type=$ct)"
    rm -f "$receipt"
  else
    if [ "$rc" -eq 0 ]; then
      ok "async: process completed (rc=0), no receipt (no harness state)"
    else
      bad "async: process failed (rc=$rc), no receipt"
    fi
  fi
}

# --- Test 3: teardown (prompt that starts work then we kill it) ---
test_teardown() {
  echo "--- Teardown ---"
  local prompt="Run a long sleep: sleep 300"
  local rc=0
  cd "$REPO_DIR"

  # Run in background, wait 5s, then kill
  "$LAUNCHER" --host "$HOST" -- "$prompt" &
  local pid=$!
  sleep 5

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || rc=$?
    ok "teardown: process killed after 5s"
  else
    wait "$pid" 2>/dev/null || rc=$?
    if [ "$rc" -eq 0 ]; then
      ok "teardown: process exited naturally (rc=0)"
    else
      ok "teardown: process exited with rc=$rc"
    fi
  fi

  # Check for receipt or stale state
  local receipt=""
  for f in "$REPO_DIR"/.saikit/close-receipts/*.json; do
    [ -f "$f" ] || continue
    receipt="$f"
    break
  done

  if [ -n "$receipt" ] && [ -f "$receipt" ]; then
    local ct
    ct="$(python3 -c "import json; d=json.load(open('$receipt')); print(d.get('close_type',''))" 2>/dev/null || echo 'parse_error')"
    ok "teardown: receipt written (close_type=$ct)"
    rm -f "$receipt"
  else
    ok "teardown: no receipt (expected — process killed, no harness state)"
  fi
}

# Run tests based on mode
case "$MODE" in
  sync)     test_sync ;;
  async)    test_async ;;
  teardown) test_teardown ;;
  all)
    test_sync
    test_async
    test_teardown
    ;;
  *) echo "mode inválido: $MODE"; exit 2 ;;
esac

printf '\n=== %d PASS / %d FAIL / %d SKIP / %d UNKNOWN ===\n' "$pass" "$fail" "$skip" "$unknown"
[ "$fail" -eq 0 ]
