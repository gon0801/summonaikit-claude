#!/usr/bin/env bash
# Aislamiento por test — Core Rule 4: ningun test corre contra el estado real.
#
# `sandbox_init` crea un directorio propio y redirige ahi el HOME y el temporal
# del proceso. Un `~/.claude/hooks/...` escrito por descuido cae adentro del
# sandbox en vez de sobre el perfil vivo, que es exactamente el archivo que
# gatea cada turno.
#
# Uso:
#   . "$here/lib/sandbox.sh"
#   sandbox_init
#   # a partir de aca: $SANDBOX, $HOME, $HOOKS_DIR, $STATE_DIR
#
# El test que lo use NO debe instalar su propio `trap ... EXIT`: pisaria la
# limpieza. Si necesita uno, que llame a `sandbox_cleanup` desde ahi.
#
# Segunda capa: `tests/run.sh` ya redirige HOME/TMPDIR por test antes de
# invocarlo, asi que un test que se olvide de esta lib igual queda contenido.
# Esta lib existe para que el test siga aislado cuando se lo corre suelto.

sandbox_init() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/saikit-sandbox-XXXXXX")" || return 1
  mkdir -p "$SANDBOX/home/.claude/hooks/state" "$SANDBOX/tmp" || return 1

  HOME="$SANDBOX/home"
  HOOKS_DIR="$HOME/.claude/hooks"
  STATE_DIR="$HOOKS_DIR/state"
  TMPDIR="$SANDBOX/tmp"
  TMP="$TMPDIR"
  TEMP="$TMPDIR"
  export HOME TMPDIR TMP TEMP

  # Windows: varias herramientas leen USERPROFILE y no HOME. Se exporta en
  # forma nativa cuando se puede, para que no quede apuntando al perfil vivo.
  if command -v cygpath >/dev/null 2>&1; then
    USERPROFILE="$(cygpath -w "$HOME")"
  else
    USERPROFILE="$HOME"
  fi
  export USERPROFILE

  trap 'sandbox_cleanup' EXIT
}

sandbox_cleanup() {
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
  return 0
}
