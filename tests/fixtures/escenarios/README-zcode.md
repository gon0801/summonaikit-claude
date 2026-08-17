# Fixtures zcode de la línea dorada — declaración de fidelidad (Task 11.8)

**Estado: se conservan como están, y esto declara por qué.**

La captura real de la Task 5.1 (`docs/task-5.1-captura.md`) midió que zcode
emite CADA clave en snake_case **y** camelCase y que su Stop trae además
`responseText`/`responsePreview`. Los fixtures de los escenarios 17-25 traen
solo la forma snake_case con ambos literales de evento: son RECONSTRUCCIÓN de
la Phase 5, no captura. Con ese gap, la suite no puede distinguir hoy un canal
que llega completo de uno que llega truncado.

No se alinean en esta task porque **la Task 11.6 (captura manual con el
operador adelante) todavía no corrió**: alinearlos antes sería adivinar la
forma real y grabar la adivinanza en la línea base. Cuando la 11.6 mida, la
fila 11.8 exige alinear estos fixtures a lo capturado, con regrabación
coordinada por UNA sola sesión, diff auditado y veredictos movidos DECLARADOS
— acá NO se promete "cero veredictos movidos": cambiar la forma de los
fixtures zcode va a mover veredictos y ocultarlo sería el defecto.

Lo que SÍ entró en la 11.8: el escenario `46-zcode-ambos-canales-ciegos`,
que ejercita en la capa dorada la rama de canales ciegos de la Task 11.4
(hasta ahora cubierta solo por gate_cases + mutaciones — lección de la 10.17:
cubierto por mutaciones != cubierto por la capa que graba COMPORTAMIENTO).
