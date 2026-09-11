#!/usr/bin/env bash
# headless-close.sh — launcher opt-in para cierre headless observable (20.15)
#
# Envuelve `claude -p` (o `grok -p`). Al terminar, asegura limpieza de estado
# del harness incluso si el host no disparó Stop.
#
# Uso: bash tools/headless-close.sh [--host claude|grok] -- <prompt>
# Salida: RC del proceso hijo + diagnóstico de limpieza en stderr.
#
# Limitaciones:
# - Solo protege sesiones iniciadas vía este launcher.
# - No intercepta señales del proceso hijo (SIGKILL escapa).
# - Si el host dispara Stop normalmente, el launcher hace no-op.

set -euo pipefail

HOST="claude"
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

PROMPT="$*"
if [ -z "$PROMPT" ]; then
  echo "uso: headless-close.sh [--host claude|grok] -- <prompt>" >&2
  exit 2
fi

# Determinar binario del host
case "$HOST" in
  claude) BIN="${SAIKIT_CLAUDE_BIN:-claude}" ;;
  grok)   BIN="${SAIKIT_GROK_BIN:-grok}" ;;
  *)      echo "host no soportado: $HOST" >&2; exit 2 ;;
esac

# Verificar que el binario existe
if ! command -v "$BIN" >/dev/null 2>&1; then
  echo "binario no encontrado: $BIN" >&2
  exit 2
fi

# Encontrar el proyecto root
PROJECT_ROOT="$(pwd)"

# Capturar SHA del checkout
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
echo "[headless-close] checkout: $HEAD_SHA" >&2
echo "[headless-close] host: $HOST bin: $BIN" >&2

# Ejecutar el host con el prompt
RC=0
"$BIN" -p "$PROMPT" || RC=$?

echo "[headless-close] proceso terminó con RC=$RC" >&2

# ═══════════════════════════════════════════════════════════════════
# Buscar estado del harness en el DIRECTORIO REAL del hook.
#
# El hook guarda en:
#   $HOOK_DIR/state/$HOST/$PROJECT_KEY/$SESSION_KEY/harness-state.env
# donde:
#   HOOK_DIR  = ~/.claude/hooks (claude) o ~/.grok/hooks (grok)
#   PROJECT_KEY = cksum de la ruta del proyecto
#   SESSION_KEY = session_id saneado (UUID → legible)
#
# Ver hooks/summonaikit-harness.sh:901-923.
# ═══════════════════════════════════════════════════════════════════

# SAIKIT_STATE_ROOT: override for tests to avoid $HOME mismatch
if [ -n "${SAIKIT_STATE_ROOT:-}" ]; then
  STATE_ROOT="$SAIKIT_STATE_ROOT"
else
  case "$HOST" in
    claude) HOOK_DIR="${SAIKIT_CLAUDE_HOOKS_DIR:-$HOME/.claude/hooks}" ;;
    grok)   HOOK_DIR="${SAIKIT_GROK_HOOKS_DIR:-$HOME/.grok/hooks}" ;;
    *)      echo "host no soportado: $HOST" >&2; exit 2 ;;
  esac
  STATE_ROOT="$HOOK_DIR/state"
fi
PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
HOST_STATE_DIR="$STATE_ROOT/$HOST/$PROJECT_KEY"

# Encontrar el harness-state.env más reciente para este proyecto+host
STATE_FOUND=""
if [ -d "$HOST_STATE_DIR" ]; then
  newest_mtime=0
  for candidate in "$HOST_STATE_DIR"/*/harness-state.env; do
    [ -f "$candidate" ] || continue
    case "$(uname -s)" in
      Darwin) mtime="$(stat -f '%m' "$candidate" 2>/dev/null || echo 0)" ;;
      *)      mtime="$(stat -c '%Y' "$candidate" 2>/dev/null || echo 0)" ;;
    esac
    if [ "$mtime" -gt "$newest_mtime" ] 2>/dev/null; then
      newest_mtime="$mtime"
      STATE_FOUND="$candidate"
    fi
  done
fi

if [ -z "$STATE_FOUND" ]; then
  echo "[headless-close] sin estado de harness — no-op" >&2
  exit "$RC"
fi

STATE_DIR="$(dirname "$STATE_FOUND")"
SESSION_KEY="$(basename "$STATE_DIR")"

# Leer valores del estado
read_state() {
  grep "^${1}=" "$STATE_FOUND" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

AGENTS_SEEN="$(read_state agents_seen)"
TASK_HASH="$(read_state task_hash)"
CYCLE="$(read_state cycle)"

echo "[headless-close] estado: session=$SESSION_KEY task=$TASK_HASH cycle=$CYCLE agents=$AGENTS_SEEN" >&2

# ¿Tiene recibo completo? (implementer + verifier + reviewer vistos)
HAS_RECEIPT=0
case ",$AGENTS_SEEN," in
  *,implementer,*|*,verifier,*|*,reviewer,*) HAS_RECEIPT=1 ;;
esac

# Limpiar zona adversary si existe (en el proyecto, no en el hook)
ADV_ZONE="$PROJECT_ROOT/.saikit/scratch/adversary/$SESSION_KEY"
if [ -d "$ADV_ZONE" ] || [ -L "$ADV_ZONE" ]; then
  rm -rf "$ADV_ZONE" 2>/dev/null || true
  echo "[headless-close] zona adversary limpiada" >&2
fi

# Limpiar estado del harness (en el directorio del hook)
if [ "$HAS_RECEIPT" = "1" ]; then
  echo "[headless-close] recibo detectado — limpieza normal" >&2
else
  echo "[headless-close] sin recibo — limpieza forzada" >&2
fi

rm -f "$STATE_FOUND" 2>/dev/null || true
rm -f "$STATE_DIR/harness-evidence.log" 2>/dev/null || true
rm -f "$STATE_DIR/receta_alias" 2>/dev/null || true
rmdir "$STATE_DIR" 2>/dev/null || true

echo "[headless-close] limpieza completada" >&2

# Escribir recibo de cierre (20.16)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECEIPT_SCRIPT="$SCRIPT_DIR/headless-close-receipt.sh"
if [ -x "$RECEIPT_SCRIPT" ] || [ -f "$RECEIPT_SCRIPT" ]; then
  CLOSE_TYPE="unknown"
  if [ -n "$STATE_FOUND" ]; then
    if [ "$HAS_RECEIPT" = "1" ]; then
      CLOSE_TYPE="clean"
    else
      CLOSE_TYPE="forced"
    fi
  fi
  bash "$RECEIPT_SCRIPT" "$SESSION_KEY" "$CLOSE_TYPE" "$RC" "$TASK_HASH" "$AGENTS_SEEN" "$CYCLE" 2>/dev/null || true
fi
exit "$RC"
