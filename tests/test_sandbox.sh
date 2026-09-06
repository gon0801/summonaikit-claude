#!/usr/bin/env bash
# `lib/sandbox.sh` cumple Core Rule 4: HOME y temporal redirigidos adentro del
# sandbox, directorio de hooks listo, y limpieza al salir.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
home_previo="$HOME"
tmp_previo="${TMPDIR:-}"

. "$here/lib/sandbox.sh"
. "$here/lib/skip_caso.sh"
sandbox_init

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

caso "HOME queda adentro del sandbox y deja de ser el del invocador"
case "$HOME" in
  "$SANDBOX"/*) ;;
  *) malo "HOME no quedo adentro del sandbox: $HOME" ;;
esac
[ "$HOME" != "$home_previo" ] || malo "HOME no se redirigio (sigue en $home_previo)"

caso "el directorio de hooks y su state estan creados"
[ -d "$HOOKS_DIR" ] || malo "falta el directorio de hooks: $HOOKS_DIR"
[ -d "$STATE_DIR" ] || malo "falta el state dir: $STATE_DIR"
case "$HOOKS_DIR" in
  "$HOME"/.claude/hooks) ;;
  *) malo "HOOKS_DIR no cuelga del HOME aislado: $HOOKS_DIR" ;;
esac

caso "el temporal del proceso tambien cae adentro del sandbox"
[ "${TMPDIR:-}" != "$tmp_previo" ] || malo "TMPDIR no se redirigio"
case "${TMPDIR:-}" in
  "$SANDBOX"/*) ;;
  *) malo "TMPDIR no quedo adentro del sandbox: ${TMPDIR:-vacio}" ;;
esac
t="$(mktemp -d "$TMPDIR/probe-XXXXXX")"
case "$t" in
  "$SANDBOX"/*) ;;
  *) malo "mktemp CON template cayo fuera del sandbox: $t" ;;
esac
t="$(mktemp -d)"
case "$t" in
  "$SANDBOX"/*) ;;
  *)
    # 18.22: el mktemp de BSD SIN template ignora el TMPDIR exportado (cae en
    # el confstr de Darwin, /var/folders/...; medido) — el instrumento de esta
    # sub-asercion no existe en esta plataforma. Skip declarado por el canal
    # de la 18.19 con la herramienta nombrada; NO es un verde.
    saikit_skip_caso sandbox-mktemp-bare 'GNU mktemp ausente: BSD mktemp sin template ignora TMPDIR (cae en /var/folders)'
    ;;
esac

caso "un ~/.claude/hooks/... escrito por descuido no toca el perfil vivo"
printf 'echo plantado\n' > "$HOME/.claude/hooks/plantado.sh"
[ ! -e "$home_previo/.claude/hooks/plantado.sh" ] || malo "CONTENCION ROTA: escribio en $home_previo"

caso "sandbox_cleanup borra el sandbox al salir del proceso"
sub="$(bash -c '. "$1/lib/sandbox.sh"; sandbox_init; printf %s "$SANDBOX"' _ "$here")"
[ -n "$sub" ] || malo "el subproceso no reporto su SANDBOX"
[ -n "$sub" ] && [ ! -d "$sub" ] || malo "sandbox_cleanup no borro $sub al salir"

if [ "$fail" -ne 0 ]; then
  echo "test_sandbox: FAIL" >&2
  exit 1
fi
echo "test_sandbox: OK"
