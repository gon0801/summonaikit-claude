#!/usr/bin/env bash
# Contrato de honestidad de docs/guia-usuario.html (CodeRabbit, PR #104).
#
# Por que existe. La guia la lee alguien que NO puede contrastarla contra el
# codigo: es su unica descripcion de lo que el sistema hace. En un solo PR
# (#104) hubo que corregir la MISMA clase de defecto tres veces, cada una
# encontrada por un bot y no por mi:
#   1) el adversary presentado como si entrara siempre, cuando es opt-in;
#   2) el autopilot presentado como si deshiciera "cualquier fallo", cuando
#      solo intentaba el revert ante CI rojo o health-check caido, y se detenia
#      si la rama avanzaba;
#   3) "nada se publica sin que las pruebas esten en verde" — escrito, encima,
#      DENTRO del parrafo que existe para no prometer de mas. El gate deja
#      cerrar un turno que DECLARA que no corrio pruebas.
# Tres veces la misma leccion es la definicion de algo que va a estructura, no
# a la memoria de quien edite el archivo la proxima vez.
#
# Inversion deliberada (18.10, decision del operador del 2026-08-30): la D19
# se redujo a aviso — el postmerge NUNCA revierte solo, ni siquiera lo
# intenta: imprime el bloque PARA REVERTIR y no ejecuta nada
# (tools/saikit-postmerge.sh). La clausula 4 ("intenta deshacerlo") paso a ser
# FALSA y se invirtio a proposito (precedente: Task 3.2): ahora se EXIGE "no
# revierte solo" y se PROHIBE "intenta deshacerlo". Ese diff es la declaracion
# de que el contrato cambio, no una regresion del candado.
#
# Que valida, exactamente. Dos cosas, ninguna de ellas "la guia dice la verdad":
#   A) las clausulas de honestidad siguen ahi (nadie las borro en una reescritura);
#   B) ninguna de las formas de promesa absoluta YA MEDIDAS volvio al archivo.
#
# Que NO valida, dicho para que nadie le pida mas de lo que da: no comprueba
# que la guia sea cierta. Una promesa falsa NUEVA, con palabras que no estan en
# esta lista, pasa limpia. Es un candado contra la regresion conocida, no un
# verificador de veracidad; el juicio sobre una frase nueva sigue siendo del
# lider y de la revision.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
guia_por_defecto="$repo/docs/guia-usuario.html"

fail=0
caso() { printf '  caso: %s\n' "$1"; }
malo() { printf '    FAIL: %s\n' "$1" >&2; fail=1; }

# Frases que TIENEN que estar. Formato: etiqueta|frase literal
DEBEN_ESTAR='limites: la guia se declara ayudante y no candado|ayudante disciplinado, no un candado
limites: dice que ante lo que no puede ver deja pasar|deja pasar en vez de bloquear
adversary: se declara que no siempre entra|no siempre entra
autopilot: el postmerge avisa y no revierte solo|no revierte solo'

# Frases que NO pueden volver. Formato: etiqueta|frase literal|que se corrigio
NO_PUEDEN_ESTAR='autopilot promete deshacer cualquier fallo|se deshace solo|el postmerge reducido solo avisa, nunca ejecuta
autopilot promete que el sistema deshace solo|intenta deshacerlo|D19 reducida: el postmerge solo avisa con el comando listo
el flujo afirma que siempre entran los cuatro roles|Los cuatro de arriba|el adversary es el cuarto y es opt-in
garantia absoluta de pruebas verdes|nada se publica sin|el gate deja cerrar un turno que declara que no corrio pruebas
el gate presentado como bloqueo de cierre|el turno no cierra|el gate es fail-open: ante lo que no observa, deja pasar'

# chequear_guia ARCHIVO -> imprime una linea por violacion, nada si esta bien.
chequear_guia() {
  local archivo="$1" linea etiqueta frase
  while IFS= read -r linea; do
    [ -n "$linea" ] || continue
    etiqueta="${linea%%|*}"; frase="${linea#*|}"
    grep -qF -e "$frase" -- "$archivo" \
      || printf 'falta la clausula [%s]: no aparece "%s"\n' "$etiqueta" "$frase"
  done <<< "$DEBEN_ESTAR"
  while IFS= read -r linea; do
    [ -n "$linea" ] || continue
    etiqueta="${linea%%|*}"; frase="${linea#*|}"; frase="${frase%%|*}"
    grep -qF -e "$frase" -- "$archivo" \
      && printf 'volvio la promesa [%s]: aparece "%s"\n' "$etiqueta" "$frase"
  done <<< "$NO_PUEDEN_ESTAR"
  return 0
}

# ------------------------------------------------------------- sinteticos
# El detector tiene que saber ponerse en rojo: si sus dos mitades estuvieran mal
# escritas, un archivo vacio pasaria y el candado seria decoracion.
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/saikit-guia-XXXXXX")" || exit 1
trap 'rm -rf "$sandbox"' EXIT

caso "un archivo sin ninguna clausula => se reportan las 4 que faltan"
printf '<p>Una guia que no dice nada de sus limites.</p>\n' > "$sandbox/pelado.html"
out="$(chequear_guia "$sandbox/pelado.html")"
n="$(printf '%s\n' "$out" | grep -c 'falta la clausula')"
[ "$n" = 4 ] || malo "esperaba 4 clausulas faltantes, hubo $n: $out"

caso "un archivo con las promesas absolutas => se reportan las 5 que volvieron"
{
  printf 'ayudante disciplinado, no un candado / deja pasar en vez de bloquear\n'
  printf 'no siempre entra / no revierte solo\n'
  printf 'se deshace solo. intenta deshacerlo. Los cuatro de arriba. nada se publica sin pruebas. el turno no cierra.\n'
} > "$sandbox/promete.html"
out="$(chequear_guia "$sandbox/promete.html")"
n="$(printf '%s\n' "$out" | grep -c 'volvio la promesa')"
[ "$n" = 5 ] || malo "esperaba 5 promesas detectadas, hubo $n: $out"
printf '%s\n' "$out" | grep -q 'falta la clausula' && malo "reporto clausulas faltantes que si estaban: $out"

caso "un archivo que cumple las dos mitades => sin violaciones"
{
  printf 'ayudante disciplinado, no un candado; deja pasar en vez de bloquear\n'
  printf 'el adversary no siempre entra; el autopilot no revierte solo y avisa\n'
} > "$sandbox/ok.html"
out="$(chequear_guia "$sandbox/ok.html")"
[ -z "$out" ] || malo "archivo correcto marcado como violacion: $out"

# --------------------------------------------------------- la guia real
caso "docs/guia-usuario.html cumple el contrato de honestidad"
guia="${1:-$guia_por_defecto}"
unknown=0
if [ -r "$guia" ]; then
  out="$(chequear_guia "$guia")"
  if [ -n "$out" ]; then
    while IFS= read -r l; do malo "guia-usuario.html: $l"; done <<< "$out"
  fi
else
  echo "  UNKNOWN: no se pudo leer $guia; no se pudo mirar la guia real" >&2
  unknown=1
fi

if [ "$fail" -ne 0 ]; then
  echo "test_guia_usuario: FAIL" >&2
  exit 1
fi
# Un unknown NO es un OK (contrato de datos del repo: not_observed != absent).
# exit 3 es el codigo que tests/run.sh cuenta aparte como "no se pudo verificar".
if [ "$unknown" -ne 0 ]; then
  echo "test_guia_usuario: unknown" >&2
  exit 3
fi
echo "test_guia_usuario: OK"
