#!/usr/bin/env bash
# tests/test_headless_close_live.sh — 20.17 medicion. Mocks siempre corren.
# Host vivo: saikit_skip_caso, nunca PASS por binario ausente.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/sandbox.sh"
. "$here/lib/skip_caso.sh"
sandbox_init
fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

LAUNCHER="$repo/tools/headless-close.sh"
. "$repo/tools/lib/headless_close_paths.sh"
export SAIKIT_HOOK_DIR="$HOME/.claude/hooks"
mkdir -p "$SAIKIT_HOOK_DIR/state" "$SANDBOX/bin" "$SANDBOX/proj"
PROJECT_ROOT="$SANDBOX/proj"
mkdir -p "$PROJECT_ROOT"

caso "mock positivo: leftover+recibo => 0 forced (cadena host/hook/supervisor/estado)"
export SAIKIT_CLAUDE_BIN="$SANDBOX/bin/mock-live"
sid="live-pos"
sp="$(headless_state_path claude "$PROJECT_ROOT" "$sid")"
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
out="$(bash "$LAUNCHER" --host claude --project-root "$PROJECT_ROOT" -- hi 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || malo "live-shaped positivo rc=$rc $out"
[ ! -f "$sp" ] || malo "estado vivo no limpiado"

caso "mock falta de recibo: host rc=0 => close exit 1 (NO ok)"
sid="live-miss"
sp="$(headless_state_path claude "$PROJECT_ROOT" "$sid")"
mkdir -p "$(headless_state_dir_of "$sp")"
printf 'cycle=1\n' > "$sp"
printf 'sin recibo\n' > "$(headless_state_dir_of "$sp")/harness-evidence.log"
cat > "$SAIKIT_CLAUDE_BIN" << MOCK
#!/usr/bin/env bash
printf '%s\n' '{"session_id":"live-miss","result":"host ok"}'
exit 0
MOCK
chmod +x "$SAIKIT_CLAUDE_BIN"
out="$(bash "$LAUNCHER" --host claude --project-root "$PROJECT_ROOT" -- hi 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || malo "falta recibo debe FAIL close rc=$rc $out"
printf '%s' "$out" | grep -q 'close_type=incomplete' || malo "faltaba incomplete: $out"

caso "async no es un prompt bash: launcher no finge delegacion"
if grep -Eiq 'async.*bash|prompt bash|fake async' "$LAUNCHER" "$repo/tests/test_headless_close.sh"; then
  malo "async fingido via bash"
fi

caso "invocacion directa del host queda fuera de garantia (documentada en contrato)"
[ -f "$repo/docs/spec/headless-close-contract.md" ] || malo "falta contrato"
grep -q 'fuera de garantia' "$repo/docs/spec/headless-close-contract.md" \
  || grep -qi 'fuera de garantía' "$repo/docs/spec/headless-close-contract.md" \
  || malo "contrato no declara invocacion directa fuera de garantia"

caso "host vivo claude -p json (skip, no PASS, si no hay binario)"
live_bin=""
if [ -x /Users/dn/.local/bin/claude ]; then
  live_bin=/Users/dn/.local/bin/claude
elif command -v claude >/dev/null 2>&1; then
  live_bin="$(command -v claude)"
fi
if [ -z "$live_bin" ]; then
  saikit_skip_caso "live-claude-session-id" "binario claude ausente; skip no es PASS"
else
  # medicion corta; si COMPANION_APP_UNAVAILABLE el caso documenta, no reintenta
  unset SAIKIT_CLAUDE_BIN
  export SAIKIT_CLAUDE_BIN="$live_bin"
  out="$(bash "$LAUNCHER" --host claude --timeout 20 --project-root "$PROJECT_ROOT" -- 'Reply with the single word pong and a SUMMONAIKIT HARNESS RECEIPT with Understand: pong Implement: n/a Verify: n/a Review: n/a Close: n/a Retro: n/a' 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out"
  case "$rc" in
    0|1|3) printf '    live rc=%s (0 clean/forced, 1 leftover incompleto, 3 unknown)\n' "$rc" ;;
    2) malo "live rc=2 usage/bin — binario estaba presente" ;;
    *) malo "live rc inesperado $rc" ;;
  esac
fi

if [ "$fail" -ne 0 ]; then
  echo "test_headless_close_live: FAIL" >&2
  exit 1
fi
echo "test_headless_close_live: OK"
exit 0
