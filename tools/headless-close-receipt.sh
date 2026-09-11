#!/usr/bin/env bash
# headless-close-receipt.sh — escribe recibo de cierre headless (20.16)
#
# El launcher (headless-close.sh) llama a este script al terminar.
# Escribe un JSON en .saikit/close-receipts/<session>.json con:
#   - session_key, timestamp, checkout_sha, hook_sha
#   - close_type: "clean" (Stop disparó) | "forced" (launcher limpió) | "unknown"
#   - rc: exit code del proceso hijo
#   - agents_seen, task_hash, cycle (del estado del harness)
#
# Uso: bash tools/headless-close-receipt.sh <session_key> <close_type> <rc> [task_hash] [agents_seen] [cycle]
set -euo pipefail

SESSION_KEY="${1:?uso: headless-close-receipt.sh <session_key> <close_type> <rc> [task_hash] [agents_seen] [cycle]}"
CLOSE_TYPE="${2:?}"
RC="${3:?}"
TASK_HASH="${4:-unknown}"
AGENTS_SEEN="${5:-}"
CYCLE="${6:-0}"

# Validar close_type
case "$CLOSE_TYPE" in
  clean|forced|unknown) ;;
  *) echo "close_type inválido: $CLOSE_TYPE (esperado: clean|forced|unknown)" >&2; exit 2 ;;
esac

# Validar RC numérico
case "$RC" in
  *[!0-9]*) echo "RC no numérico: $RC" >&2; exit 2 ;;
esac

PROJECT_ROOT="$(pwd)"
RECEIPTS_DIR="$PROJECT_ROOT/.saikit/close-receipts"
mkdir -p "$RECEIPTS_DIR" 2>/dev/null || true

# SHA del checkout
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null | tr -d '\n' || echo 'unknown')"

# SHA del hook instalado
HOOK_SHA="unknown"
for hook_path in "$HOME/.claude/hooks/summonaikit-harness.sh" \
                 "$HOME/.grok/hooks/summonaikit-harness.sh" \
                 "$HOME/.codex/hooks/summonaikit-harness.sh"; do
  if [ -f "$hook_path" ]; then
    HOOK_SHA="$(shasum -a256 "$hook_path" 2>/dev/null | cut -c1-16 || echo 'unknown')"
    break
  fi
done

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"

# Escribir JSON con jq para escaping seguro
RECEIPT_FILE="$RECEIPTS_DIR/$SESSION_KEY.json"
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg sk "$SESSION_KEY" \
    --arg ts "$TIMESTAMP" \
    --arg sha "$HEAD_SHA" \
    --arg hk "$HOOK_SHA" \
    --arg ct "$CLOSE_TYPE" \
    --argjson rc "$RC" \
    --arg th "$TASK_HASH" \
    --arg ag "$AGENTS_SEEN" \
    --argjson cy "$CYCLE" \
    '{session_key:$sk, timestamp:$ts, checkout_sha:$sha, hook_sha:$hk, close_type:$ct, rc:$rc, task_hash:$th, agents_seen:$ag, cycle:$cy}' \
    > "$RECEIPT_FILE"
else
  # Fallback sin jq: sanitizar manualmente
  HEAD_SAFE="$(printf '%s' "$HEAD_SHA" | tr '\n' ' ' | tr -cd '[:alnum:]')"
  HK_SAFE="$(printf '%s' "$HOOK_SHA" | tr '\n' ' ' | tr -cd '[:alnum:]')"
  TH_SAFE="$(printf '%s' "$TASK_HASH" | tr '\n' ' ' | tr -cd '[:alnum:]')"
  AG_SAFE="$(printf '%s' "$AGENTS_SEEN" | tr '\n' ' ')"
  cat > "$RECEIPT_FILE" << JSON
{
  "session_key": "$SESSION_KEY",
  "timestamp": "$TIMESTAMP",
  "checkout_sha": "$HEAD_SAFE",
  "hook_sha": "$HK_SAFE",
  "close_type": "$CLOSE_TYPE",
  "rc": $RC,
  "task_hash": "$TH_SAFE",
  "agents_seen": "$AG_SAFE",
  "cycle": $CYCLE
}
JSON
fi

echo "[close-receipt] escrito: $RECEIPT_FILE (type=$CLOSE_TYPE rc=$RC)" >&2
