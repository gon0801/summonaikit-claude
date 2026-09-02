# Patrones de triage de bot — `.saikit/triage-patrones.md`

Rúbrica y patrones aprendidos para adjudicar los hallazgos de los bots
(Greptile, CodeRabbit y similares) cuando se usa la receta `cuidar-pr`. Este
archivo acumula patrones a medida que se aprenden: cada patrón nuevo se
escribe acá (con un ejemplo real y el resultado), y la receta lo lee en la
próxima vez. No es una especificación de cómo deberían comportarse los bots;
es un registro de lo que se observó.

## Rúbrica: fix / dismiss / ask

- **fix** → el hallazgo es válido y toca lo que se está construyendo. Se arregla
  (con la prueba que falla antes del fix, si aplica).
- **dismiss** → el hallazgo es inválido. Se descarta y se explica por qué, con
  la evidencia (una medición o un contraejemplo), no con una opinión.
- **ask** → no alcanza a decidir. Se pregunta al operador. Ni se arregla ni se
  descarta a ciegas.

Antes de decidir, siempre: leer el hallazgo exacto, mirar el código/la evidencia
que señala, y recién ahí clasificar. Un "dismiss" que no cita evidencia se
rechaza.

## Patrones aprendidos

- **El check del bot puede no ser del repo.** En `gh pr checks` un bot tercero
  (CodeRabbit) aparece como un check más, y puede quedar `pending` aun cuando la
  CI del repo ya pasó — o quedar `pass` con "Review rate limited" sin revisar de
  verdad. No confundir "check pendiente del bot" con "CI del repo roja": la CI
  del repo se mira en el run del workflow (`gh run list --commit`), no en el
  agregado de `gh pr checks`.
- **`mergeable: MERGEABLE` ≠ listo.** Solo significa "sin conflictos". Para
  "listo" hace falta además que el run del workflow haya concluido en éxito.
- **Flake es "pasó en un rebuild".** Si un run que era inestable resulta verde al
  re-correr una vez, se anota como flake; si vuelve a fallar, deja de serlo.
- **Un hallazgo de bot que repite la entrada es un canal de fuga.** Si un bot pide
  "usa la ruta correcta" y el código ya la usa, no es un fix: se descarta
  mostrando la línea que ya lo hace.

## Cómo agregar un patrón

Añadir una línea con el formato: `- **<qué se aprendió>.** <qué se observó, con
un ejemplo real y el resultado>`. Solo patrones de triage de bots; no notas de
otra índole.
