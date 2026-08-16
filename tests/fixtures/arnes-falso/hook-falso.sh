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
# Task 6.6: espejo de D2 (6.4) — la senal explicita de codex va PRIMERO, como
# en el hook vivo; sin esta rama el caso estado_host de codex seria vacuo
# (caeria en other), la misma trampa que 5.5 ya arreglo para zcode. ROJO
# medido: neutralizada esta linea, el caso 'estado_host: codex' se pone rojo.
[ "${SUMMONAIKIT_HOOK_TARGET:-}" = "codex" ] && HOST=codex
# Task 7.6: espejo de D2 (7.3) — grok va por SETNESS de GROK_HOOK_EVENT (una
# senal exportada VACIA cuenta; el valor no decide identidad). El falso
# encadena asignaciones sueltas, no if/elif: grok gana sobre codex/zcode por
# ser la ULTIMA asignacion, no la primera — el orden compuesto resultante
# (grok > codex > zcode > other) es el mismo del hook vivo. Sin esta rama el
# caso estado_host de grok seria vacuo (caeria en other), la misma trampa que
# 6.6 cerro para codex. ROJO medido: neutralizada esta linea, el caso
# 'estado_host: grok' se pone rojo.
[ "${GROK_HOOK_EVENT+x}" = "x" ] && HOST=grok
mkdir -p "$DIR/state/$HOST/$KEY"
{
  printf 'phase=%s\n' "${SUMMONAIKIT_HOOK_PHASE:-<sin-fase>}"
  printf 'target=%s\n' "${SUMMONAIKIT_HOOK_TARGET:-<sin-target>}"
  printf 'zcode_session=%s\n' "${ZCODE_SESSION_ID:-<sin-zcode>}"
  printf 'zcode_project=%s\n' "${ZCODE_PROJECT_DIR:-<sin-zcode-project>}"
  printf 'grok_event=%s\n' "${GROK_HOOK_EVENT:-<sin-grok>}"
  printf 'grok_session=%s\n' "${GROK_SESSION_ID:-<sin-grok-sesion>}"
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
