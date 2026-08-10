#!/usr/bin/env bash
# Task 1.5 — resolver QUE archivo se ejercita, en un solo lugar.
#
# El defecto que cierra (revision cruzada de la Phase 1, 2026-08-10): cuando el
# hook vivo no estaba, cada bateria declaraba `unknown` y salia 0 — correcto por
# Core Rule 2 — pero `tests/run.sh` publicaba eso como PASS y cerraba OK. Una
# maquina sin el archivo bajo prueba quedaba ENTERA en verde sin haber
# verificado una sola linea de semantica.
#
# Dos mitades del arreglo. Esta es la primera: desde la Task 2.1 la fuente vive
# en el repo y es el archivo vivo byte a byte mas el marcador de propiedad, asi
# que cuando el vivo no esta hay algo mejor que rendirse — se ejercita la
# fuente, y se dice. `unknown` queda para cuando no hay NINGUNO de los dos.
#
# La segunda mitad es el exit code 3, que run.sh lee para no contar un unknown
# como verificado.

# Exit code que este repo usa para "no se pudo verificar". No es fallo (el
# codigo bajo prueba no dijo nada malo) ni exito (no se probo nada).
SAIKIT_EXIT_UNKNOWN=3

# Uso:
#   . "$here/lib/hook_bajo_prueba.sh"
#   hook="$(resolver_hook_bajo_prueba "$here/..")" || exit $?
#
# Imprime por stdout la ruta a ejercitar. Si no hay ninguna, informa por stderr
# y devuelve SAIKIT_EXIT_UNKNOWN para que el llamador salga con ese codigo.
resolver_hook_bajo_prueba() {
  local repo="$1"
  local etiqueta="${2:-la bateria}"
  local vivo fuente
  vivo="${SAIKIT_HOOK_VIVO:-$HOME/.claude/hooks/summonaikit-harness.sh}"
  fuente="$repo/hooks/summonaikit-harness.sh"

  if [ -r "$vivo" ]; then
    printf '%s' "$vivo"
    return 0
  fi

  if [ -r "$fuente" ]; then
    # Se avisa por stderr, no por stdout: stdout es la ruta.
    printf '%s: el hook vivo no esta; se ejercita la FUENTE DEL REPO (%s).\n' \
           "$etiqueta" "$fuente" >&2
    printf '%s  La Task 2.1 la midio identica al vivo salvo el marcador de la linea 2.\n' \
           "$etiqueta" >&2
    printf '%s' "$fuente"
    return 0
  fi

  printf '%s: unknown — no hay hook vivo (%s) ni fuente en el repo (%s).\n' \
         "$etiqueta" "$vivo" "$fuente" >&2
  printf '%s  No se afirma nada sobre su semantica: no se pudo mirar.\n' "$etiqueta" >&2
  return "$SAIKIT_EXIT_UNKNOWN"
}
