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

# Encontrar el proyecto root (donde vive .saikit/)
PROJECT_ROOT="$(pwd)"
if [ ! -d "$PROJECT_ROOT/.saikit" ]; then
  echo "aviso: no hay .saikit/ en $PROJECT_ROOT — el launcher no puede gestionar estado" >&2
fi

# Capturar SHA del checkout
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
echo "[headless-close] checkout: $HEAD_SHA" >&2
echo "[headless-close] host: $HOST bin: $BIN" >&2

# Ejecutar el host con el prompt
RC=0
"$BIN" -p "$PROMPT" || RC=$?

echo "[headless-close] proceso terminó con RC=$RC" >&2

# Buscar estado del harness en .saikit/
STATE_FOUND=""
for state_file in "$PROJECT_ROOT"/.saikit/*/harness-state.env; do
  [ -f "$state_file" ] || continue
  # Solo procesar el estado de esta sesión (buscar por session_key)
  STATE_FOUND="$state_file"
  break
done

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

# Limpiar zona adversary si existe
ADV_ZONE="$PROJECT_ROOT/.saikit/scratch/adversary/$SESSION_KEY"
if [ -d "$ADV_ZONE" ] || [ -L "$ADV_ZONE" ]; then
  rm -rf "$ADV_ZONE" 2>/dev/null || true
  echo "[headless-close] zona adversary limpiada" >&2
fi

# Limpiar estado
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
exit "$RC"
