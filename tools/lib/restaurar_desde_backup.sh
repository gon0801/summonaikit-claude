# restaurar_desde_backup.sh — rollback atomico del hook DEST.
# Se carga con `. tools/lib/restaurar_desde_backup.sh`.
#
# tmp en el mismo dir + cmp + mv -f. El dest nunca se trunca: o queda
# el anterior o el backup entero. Si mv falla, se borra el tmp.
#
# SAIKIT_RESTORE_ABORT=1 es costura de test (R2): aborta despues del
# cmp, antes del mv. No es un flag de produccion.

restaurar_desde_backup() {  # $1=bak $2=dest
  local bak="$1" dest="$2" dir tmp
  # restore: tmp+cmp+mv (no truncar dest)
  dir="$(dirname "$dest")"
  [ -f "$bak" ] && [ -n "$dest" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$(mktemp "$dir/.saikit-restore-XXXXXX")" || return 1
  if ! cp "$bak" "$tmp" || ! cmp -s "$bak" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if [ -n "${SAIKIT_RESTORE_ABORT:-}" ]; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi
}
