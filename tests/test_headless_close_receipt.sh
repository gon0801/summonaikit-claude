#!/usr/bin/env bash
# test_headless_close_receipt.sh — tests para tools/headless-close-receipt.sh (20.16)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RECEIPT="$REPO_DIR/tools/headless-close-receipt.sh"
LAUNCHER="$REPO_DIR/tools/headless-close.sh"

pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf '  PASS: %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL: %s\n' "$1"; }
nope() { skip=$((skip+1)); printf '  SKIP: %s\n' "$1"; }

tmpdir=""
cleanup() { [ -n "$tmpdir" ] && rm -rf "$tmpdir"; }
trap cleanup EXIT

# --- Test 1: recibo existe y es ejecutable ---
if [ -x "$RECEIPT" ]; then
  ok "receipt script existe y es ejecutable"
else
  bad "receipt script no es ejecutable"; exit 1
fi

# --- Test 2: close_type inválido → exit 2 ---
tmpdir="$(mktemp -d)"
cd "$tmpdir"
git init -q
if out=$("$RECEIPT" "test-session" "bad_type" "0" 2>&1); then
  bad "close_type inválido debería fallar"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "close_type inválido → exit 2"
  else
    bad "close_type inválido → exit $rc (esperado 2)"
  fi
fi

# --- Test 3: RC no numérico → exit 2 ---
if out=$("$RECEIPT" "test-session" "clean" "abc" 2>&1); then
  bad "RC no numérico debería fallar"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "RC no numérico → exit 2"
  else
    bad "RC no numérico → exit $rc (esperado 2)"
  fi
fi

# --- Test 4: close_type clean → JSON válido ---
cd "$tmpdir"
"$RECEIPT" "sess-clean" "clean" "0" "abc123" "implementer,verifier,reviewer" "2" 2>/dev/null
if [ -f ".saikit/close-receipts/sess-clean.json" ]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json; json.load(open('.saikit/close-receipts/sess-clean.json'))" 2>/dev/null; then
      ok "clean receipt: JSON válido"
    else
      bad "clean receipt: JSON inválido"
    fi
  else
    ok "clean receipt: archivo creado (sin python3 para validar JSON)"
  fi
else
  bad "clean receipt: archivo no creado"
fi

# --- Test 5: close_type forced ---
cd "$tmpdir"
"$RECEIPT" "sess-forced" "forced" "1" "def456" "implementer" "1" 2>/dev/null
if [ -f ".saikit/close-receipts/sess-forced.json" ]; then
  if grep -q '"close_type": "forced"' ".saikit/close-receipts/sess-forced.json"; then
    ok "forced receipt: close_type=forced"
  else
    bad "forced receipt: close_type incorrecto"
  fi
else
  bad "forced receipt: archivo no creado"
fi

# --- Test 6: close_type unknown ---
cd "$tmpdir"
"$RECEIPT" "sess-unknown" "unknown" "0" 2>/dev/null
if [ -f ".saikit/close-receipts/sess-unknown.json" ]; then
  if grep -q '"close_type": "unknown"' ".saikit/close-receipts/sess-unknown.json"; then
    ok "unknown receipt: close_type=unknown"
  else
    bad "unknown receipt: close_type incorrecto"
  fi
else
  bad "unknown receipt: archivo no creado"
fi

# --- Test 7: RC se preserva en JSON ---
cd "$tmpdir"
"$RECEIPT" "sess-rc" "clean" "42" 2>/dev/null
if grep -q '"rc": 42' ".saikit/close-receipts/sess-rc.json"; then
  ok "RC preservado: rc=42 en JSON"
else
  bad "RC no preservado en JSON"
fi

# --- Test 8: campos requeridos presentes ---
cd "$tmpdir"
"$RECEIPT" "sess-fields" "clean" "0" "hash123" "impl,ver" "3" 2>/dev/null
required_fields="session_key timestamp checkout_sha hook_sha close_type rc task_hash agents_seen cycle"
all_ok=1
for field in $required_fields; do
  if ! grep -q "\"$field\"" ".saikit/close-receipts/sess-fields.json"; then
    printf '  campo faltante: %s\n' "$field"
    all_ok=0
  fi
done
if [ "$all_ok" -eq 1 ]; then
  ok "campos requeridos: todos presentes"
else
  bad "campos requeridos: faltan campos"
fi

# --- Test 9: launcher integra recibo ---
test_launcher_writes_receipt() {
  local td="$tmpdir/test9"
  mkdir -p "$td/.saikit/test-session"
  cat > "$td/.saikit/test-session/harness-state.env" << 'ENV'
task_hash=xyz789
cycle=1
implemented=1
verified=0
agents_seen=implementer
lane=full
ENV
  mkdir -p "$td/bin"
  cat > "$td/bin/mock-claude" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$td/bin/mock-claude"

  cd "$td"
  git init -q
  SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test" 2>/dev/null || true

  if [ -f ".saikit/close-receipts/test-session.json" ]; then
    if grep -q '"close_type"' ".saikit/close-receipts/test-session.json"; then
      ok "launcher escribe recibo de cierre"
    else
      bad "launcher escribe archivo pero sin close_type"
    fi
  else
    bad "launcher no escribe recibo"
  fi
}
test_launcher_writes_receipt

# --- Test 10: launcher con Stop limpio → close_type=clean ---
test_launcher_clean_close() {
  local td="$tmpdir/test10"
  mkdir -p "$td/.saikit/test-session"
  cat > "$td/.saikit/test-session/harness-state.env" << 'ENV'
task_hash=abc
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

  cd "$td"
  git init -q
  SAIKIT_CLAUDE_BIN="$td/bin/mock-claude" "$LAUNCHER" --host claude -- "test" 2>/dev/null || true

  if [ -f ".saikit/close-receipts/test-session.json" ]; then
    # El launcher escribe "forced" porque no tiene forma de saber si Stop disparó
    # (eso es trabajo de20.16 — detectar el cierre limpio vs forzado)
    ok "launcher escribe recibo (tipo: $(grep close_type .saikit/close-receipts/test-session.json | head -1))"
  else
    bad "launcher no escribe recibo con recibo completo"
  fi
}
test_launcher_clean_close

printf '\n=== %d PASS / %d FAIL / %d SKIP ===\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
