#!/usr/bin/env bash
# Hook FALSO — existe solo para probar el arnes de salida dorada.
#
# No es un hook: es el minimo que ejercita todo lo que el arnes tiene que
# grabar bien — stdout, stderr, exit code distinto de 0, estado en disco, un
# timestamp y una ruta absoluta (las dos cosas que cambian entre corridas y que
# el arnes normaliza). Que el arnes se pruebe contra ESTO y no contra el hook
# vivo es lo que hace que `test_golden_harness` corra igual en una maquina
# donde el hook vivo no existe.
ESTADO_NOMBRE=falso.env
INPUT="$(cat)"
DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="$(pwd | cksum | cut -d ' ' -f 1)"
# Task 5.5: el falso escribe state/<host>/<key>/ para que el arnes pueda afirmar
# el HOST del target zcode (host_del_estado lee el segmento host sin normalizar).
# Mismo criterio que el hook vivo (5.3): zcode si ZCODE_* esta seteada, other si
# no. Antes escribia state/<key>/ sin host: el caso estado_host era vacuo.
HOST=other
[ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ] && HOST=zcode
mkdir -p "$DIR/state/$HOST/$KEY"
{
  printf 'phase=%s\n' "${SUMMONAIKIT_HOOK_PHASE:-<sin-fase>}"
  printf 'target=%s\n' "${SUMMONAIKIT_HOOK_TARGET:-<sin-target>}"
  printf 'zcode_session=%s\n' "${ZCODE_SESSION_ID:-<sin-zcode>}"
  printf 'zcode_project=%s\n' "${ZCODE_PROJECT_DIR:-<sin-zcode-project>}"
  printf 'ts=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'cwd=%s\n' "$(pwd)"
  printf 'bytes_entrada=%s\n' "${#INPUT}"
} > "$DIR/state/$HOST/$KEY/$ESTADO_NOMBRE"

case "${SUMMONAIKIT_HOOK_PHASE:-}" in
  stop)
    printf '{"decision":"block"}\n'
    printf 'bloqueado por el hook falso\n' >&2
    exit 2
    ;;
  *)
    printf '{"ok":true}\n'
    exit 0
    ;;
esac
