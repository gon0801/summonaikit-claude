#!/usr/bin/env bash
# headless-close.sh — launcher opt-in (20.15-20.17).
# Observa SOLO su STATE_PATH. close_type sale de la observacion, no del caller.
# Exit 0: leftover + recibo de 6 etiquetas (forced clean) O sin leftover (clean no-op).
# Exit 1: leftover sin recibo completo, o timeout (aunque host rc=0).
# Exit 2: uso / binario ausente.
# Exit 3: session_id ausente o captura no observable.
# Nunca relanza en silencio. Nunca glob.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/headless_close_paths.sh"

usage() {
  echo "uso: headless-close.sh [--host claude|grok] [--timeout SECONDS] [--project-root DIR] -- <prompt>" >&2
}

HOST="claude"
TIMEOUT=""
PROJECT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      [ $# -ge 2 ] || { usage; exit 2; }
      HOST="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || { usage; exit 2; }
      TIMEOUT="$2"; shift 2 ;;
    --project-root)
      [ $# -ge 2 ] || { usage; exit 2; }
      PROJECT_ROOT="$2"; shift 2 ;;
    --close-type)
      echo "headless-close: close_type no se acepta del caller (recibo fabricable)" >&2
      exit 2 ;;
    --)
      shift; break ;;
    -h|--help)
      usage; exit 2 ;;
    *)
      break ;;
  esac
done

PROMPT="$*"
if [ -z "$PROMPT" ]; then
  usage
  exit 2
fi

case "$HOST" in
  claude|grok) ;;
  *) echo "host no soportado: $HOST" >&2; exit 2 ;;
esac

if [ -n "$TIMEOUT" ]; then
  case "$TIMEOUT" in
    ''|*[!0-9]*) echo "timeout invalido: $TIMEOUT" >&2; exit 2 ;;
  esac
fi

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(pwd)"
  if command -v git >/dev/null 2>&1; then
    GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$GIT_ROOT" ]; then PROJECT_ROOT="$GIT_ROOT"; fi
  fi
fi

case "$HOST" in
  claude) BIN="${SAIKIT_CLAUDE_BIN:-claude}" ;;
  grok)   BIN="${SAIKIT_GROK_BIN:-grok}" ;;
esac

bin_ok=0
if [ -x "$BIN" ]; then
  bin_ok=1
elif command -v "$BIN" >/dev/null 2>&1; then
  BIN="$(command -v "$BIN")"
  bin_ok=1
fi
if [ "$bin_ok" -ne 1 ]; then
  echo "binario no encontrado: $BIN" >&2
  exit 2
fi

WORKDIR="${TMPDIR:-/tmp}"
OUT_JSON="$(mktemp "$WORKDIR/saikit-headless-out.XXXXXX")"
ERR_LOG="$(mktemp "$WORKDIR/saikit-headless-err.XXXXXX")"
trap 'rm -f "$OUT_JSON" "$ERR_LOG"' EXIT

run_host() {
  # grok 1.0.25: -p/--single toman el prompt como VALOR (medido 20.17:
  # `grok -p --output-format json "P"` muere en clap con rc=2 sin tocar la
  # red). claude -p es boolean + prompt posicional. No unificar: son argv
  # distintos y el de claude en grok ni parsea.
  case "$HOST" in
    grok) "$BIN" --single "$PROMPT" --output-format json ;;
    *)    "$BIN" -p --output-format json "$PROMPT" ;;
  esac
}

TIMED_OUT=0
HOST_RC=0
if [ -n "$TIMEOUT" ] && [ "$TIMEOUT" -gt 0 ]; then
  run_host >"$OUT_JSON" 2>"$ERR_LOG" &
  child=$!
  elapsed=0
  while kill -0 "$child" 2>/dev/null; do
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      TIMED_OUT=1
      kill "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ "$TIMED_OUT" -eq 0 ]; then
    wait "$child" && HOST_RC=0 || HOST_RC=$?
  else
    HOST_RC=124
  fi
else
  run_host >"$OUT_JSON" 2>"$ERR_LOG" && HOST_RC=0 || HOST_RC=$?
fi

LAUNCH_COUNT_FILE="${SAIKIT_HEADLESS_LAUNCH_COUNT:-}"
if [ -n "$LAUNCH_COUNT_FILE" ]; then
  n=0
  [ -f "$LAUNCH_COUNT_FILE" ] && n="$(cat "$LAUNCH_COUNT_FILE" 2>/dev/null || echo 0)"
  echo $((n + 1)) > "$LAUNCH_COUNT_FILE"
fi

PARSE_PY="$WORKDIR/saikit-headless-parse.py"
cat > "$PARSE_PY" << 'PY'
import json, sys, base64
path = sys.argv[1]
raw = open(path, "rb").read()
if not raw.strip():
    print("SESSION=")
    print("RESULT_B64=")
    sys.exit(0)
text = raw.decode("utf-8", "replace").strip()
obj = None
lines = text.splitlines()
cands = [text]
if lines:
    cands.append(lines[-1].strip())
for candidate in cands:
    candidate = candidate.strip()
    if not candidate:
        continue
    try:
        obj = json.loads(candidate)
        break
    except Exception:
        obj = None
if obj is None:
    start = text.find("{")
    if start >= 0:
        depth = 0
        in_str = False
        esc = False
        for i, ch in enumerate(text[start:], start):
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(text[start:i+1])
                    except Exception:
                        obj = None
                    break
if not isinstance(obj, dict):
    print("SESSION=")
    print("RESULT_B64=")
    sys.exit(0)
sid = obj.get("session_id") or obj.get("sessionId") or ""
if not isinstance(sid, str):
    sid = ""
result = obj.get("result") or ""
if not isinstance(result, str):
    result = json.dumps(result)
print("SESSION=" + sid.replace("\n", " "))
print("RESULT_B64=" + base64.b64encode(result.encode("utf-8")).decode("ascii"))
PY

PARSE_OUT="$(python3 "$PARSE_PY" "$OUT_JSON" 2>/dev/null || true)"
rm -f "$PARSE_PY"

SESSION_ID=""
RESULT_TEXT=""
while IFS= read -r line; do
  case "$line" in
    SESSION=*) SESSION_ID="${line#SESSION=}" ;;
    RESULT_B64=*)
      b64="${line#RESULT_B64=}"
      if [ -n "$b64" ]; then
        RESULT_TEXT="$(printf '%s' "$b64" | python3 -c 'import sys,base64; print(base64.b64decode(sys.stdin.read().strip() or b"").decode("utf-8","replace"))' 2>/dev/null || true)"
      fi
      ;;
  esac
done <<EOF
$PARSE_OUT
EOF

if [ -z "$SESSION_ID" ]; then
  echo "[headless-close] unknown: sin session_id en JSON del host (captura no observable)" >&2
  echo "close_type=unknown" >&2
  exit 3
fi

STATE_PATH="$(headless_state_path "$HOST" "$PROJECT_ROOT" "$SESSION_ID")"
STATE_DIR="$(headless_state_dir_of "$STATE_PATH")"
EVIDENCE="$STATE_DIR/harness-evidence.log"

has_six_labels() {
  local blob="$1"
  printf '%s' "$blob" | grep -Eiq 'SUMMONAIKIT HARNESS RECEIPT' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Understand:' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Implement:' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Verify:' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Review:' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Close:' || return 1
  printf '%s' "$blob" | grep -Eq '(^|[[:space:][:punct:]])Retro:' || return 1
  return 0
}

blob=""
[ -f "$EVIDENCE" ] && blob="$(cat "$EVIDENCE" 2>/dev/null || true)"
blob="${blob}
${RESULT_TEXT}"

COMPLETE=0
if has_six_labels "$blob"; then COMPLETE=1; fi

forced_clean() {
  rm -f "$STATE_PATH" 2>/dev/null || true
  rm -f "$EVIDENCE" 2>/dev/null || true
  rm -f "$STATE_DIR/receta_alias" 2>/dev/null || true
  rmdir "$STATE_DIR" 2>/dev/null || true
}

if [ "$TIMED_OUT" -eq 1 ]; then
  echo "[headless-close] timeout=${TIMEOUT}s host_rc=$HOST_RC state=$STATE_PATH" >&2
  if [ -f "$STATE_PATH" ]; then
    forced_clean
  fi
  echo "close_type=timeout" >&2
  exit 1
fi

if [ -f "$STATE_PATH" ]; then
  if [ "$COMPLETE" -eq 1 ]; then
    echo "[headless-close] leftover+recibo completo — forced clean $STATE_PATH" >&2
    forced_clean
    echo "close_type=forced" >&2
    exit 0
  fi
  echo "[headless-close] leftover sin recibo de 6 etiquetas (host_rc=$HOST_RC) — no exito" >&2
  forced_clean
  echo "close_type=incomplete" >&2
  exit 1
fi

echo "[headless-close] sin leftover — clean no-op session=$SESSION_ID" >&2
echo "close_type=clean" >&2
exit 0
