#!/usr/bin/env bash
# skip_caso.sh — canal de skip POR CASO, categoria aparte (fila 18.19).
#
# CONTRATO (lo candan los casos de test_runner_guards.sh):
#   - `saikit_skip_caso <caso> <razon>` registra `SAIKIT_SKIP_CASO: <caso> --
#     <razon>` en el archivo que el runner pasa en $SAIKIT_SKIPS (uno vacio por
#     test) y lo ecoa a stdout, para que corriendo el archivo suelto tambien
#     se vea.
#   - Lo emite un caso cuyo INSTRUMENTO de medicion no esta disponible. No es
#     verde ni unknown-de-archivo: el archivo sigue con los casos restantes y
#     su exit code refleja solo las aserciones reales.
#   - El runner cuenta los marcadores, anota la linea de resultado y los suma
#     en categoria APARTE (ni PASS, ni FAIL, ni el unknown por exit 3). El
#     skip jamas altera exit codes.
# Idempotente ante doble source: la funcion se redefine igual, no acumula.

saikit_skip_caso() {  # $1 = nombre del caso, $2 = razon (texto libre, una linea)
  local linea="SAIKIT_SKIP_CASO: $1 -- $2"
  if [ -n "${SAIKIT_SKIPS:-}" ] && [ -w "${SAIKIT_SKIPS%/*}" ]; then
    printf '%s\n' "$linea" >> "$SAIKIT_SKIPS"
  fi
  printf '    %s\n' "$linea"
}
