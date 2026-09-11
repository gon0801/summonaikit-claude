#!/usr/bin/env bash
# test_headless_close.sh — tests para tools/headless-close.sh (20.15)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_DIR/tools/headless-close.sh"

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }
nope() { skip=$((skip+1)); printf '  SKIP: %s\n' "$1"; }

tmpdir=""
cleanup() { [ -n "$tmpdir" ] && rm -rf "$tmpdir"; }
trap cleanup EXIT

# --- Test 1: launcher existe y es ejecutable ---
if [ -x "$LAUNCHER" ]; then
  ok "launcher existe y es ejecutable"
else
  bad "launcher no es ejecutable"; exit 1
fi

# --- Test 2: sin argumentos → exit 2 ---
tmpdir="$(mktemp -d)"
if output=$("$LAUNCHER" 2>&1); then
  bad "sin argumentos debería fallar"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "sin argumentos → exit 2"
  else
    bad "sin argumentos → exit $rc (esperado 2)"
  fi
fi

# --- Test 3: host no soportado → exit 2 ---
if output=$("$LAUNCHER" --host fake -- "test" 2>&1); then
  bad "host fake debería fallar"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "host fake → exit 2"
  else
    bad "host fake → exit $rc (esperado 2)"
  fi
fi

# --- Test 4: binario no encontrado → exit 2 ---
if output=$(SAIKIT_CLAUDE_BIN="/nonexistent/claude" "$LAUNCHER" --host claude -- "test" 2>&1); then
  bad "binario inexistente debería fallar"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "binario inexistente → exit 2"
  else
    bad "binario inexistente → exit $rc (esperado 2)"
  fi
fi

# --- Test 5: cleanup de estado sin recibo ---
test_cleanup_sin_recibo() {
  local td="$tmpdir/test5"
  mkdir -p "$td/.saikit/test-session"
  cat > "$td/.saikit/test-session/harness-state.env" << 'ENV'
task_hash=abc123
cycle=1
implemented=1
verified=0
agents_seen=implementer
lane=full
ENV
  # Mock claude que retorna 0
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$td/bin/mock-claude"

  local out
  out=$(cd "$td" && SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test prompt" 2>&1) || true

  if [ ! -f "$td/.saikit/test-session/harness-state.env" ]; then
    ok "cleanup sin recibo: estado borrado"
  else
    bad "cleanup sin recibo: estado persiste"
  fi
}
test_cleanup_sin_recibo

# --- Test 6: cleanup de estado con recibo ---
test_cleanup_con_recibo() {
  local td="$tmpdir/test6"
  mkdir -p "$td/.saikit/test-session"
  cat > "$td/.saikit/test-session/harness-state.env" << 'ENV'
task_hash=def456
cycle=2
implemented=1
verified=1
agents_seen=implementer,verifier,reviewer
lane=full
ENV
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$td/bin/mock-claude"

  local out
  out=$(cd "$td" && SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test prompt" 2>&1) || true

  if [ ! -f "$td/.saikit/test-session/harness-state.env" ]; then
    ok "cleanup con recibo: estado borrado"
  else
    bad "cleanup con recibo: estado persiste"
  fi
}
test_cleanup_con_recibo

# --- Test 7: zona adversary se limpia ---
test_cleanup_adversary_zone() {
  local td="$tmpdir/test7"
  mkdir -p "$td/.saikit/scratch/adversary/test-session"
  echo "test" > "$td/.saikit/scratch/adversary/test-session/owner"
  mkdir -p "$td/.saikit/test-session"
  cat > "$td/.saikit/test-session/harness-state.env" << 'ENV'
task_hash=ghi789
cycle=0
implemented=0
verified=0
agents_seen=
lane=full
ENV
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$td/bin/mock-claude"

  local out
  out=$(cd "$td" && SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test prompt" 2>&1) || true

  if [ ! -d "$td/.saikit/scratch/adversary/test-session" ]; then
    ok "adversary zone: limpiada"
  else
    bad "adversary zone: persiste"
  fi
}
test_cleanup_adversary_zone

# --- Test 8: proceso hijo falla → RC se propaga ---
test_rc_propagation() {
  local td="$tmpdir/test8"
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 42
MOCK
  chmod +x "$td/bin/mock-claude"

  local out rc
  out=$(cd "$td" && SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test" 2>&1) || rc=$?
  if [ "${rc:-0}" -eq 42 ]; then
    ok "RC propagation: exit 42 propagado"
  else
    bad "RC propagation: exit ${rc:-0} (esperado 42)"
  fi
}
test_rc_propagation

# --- Test 9: sin .saikit/ → no-op ---
test_no_saikit_dir() {
  local td="$tmpdir/test9"
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$td/bin/mock-claude"

  local out
  out=$(cd "$td" && SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test" 2>&1) || true

  if echo "$out" | grep -q "sin estado"; then
    ok "sin .saikit/: no-op"
  else
    bad "sin .saikit/: no detectó ausencia"
  fi
}
test_no_saikit_dir

printf '\n=== %d PASS / %d FAIL / %d SKIP ===\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
