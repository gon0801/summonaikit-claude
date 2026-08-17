# Fixtures zcode de la línea dorada — declaración de fidelidad (Task 11.8)

**Estado (2026-08-17, tras la Task 11.9): los `*.stop.zcode.json` YA están
alineados a la forma medida.** Qué se hizo, para que nadie lo tenga que
reconstruir: se agregaron los duplicados camel que zcode sí manda (`sessionId`,
`transcriptPath`, `mode`, `stopHookActive`; `hookEventName` ya estaba), los
extras medidos (`timestamp`, `toolCallCount`, `traceId`, `turnId`) y
`responseText`/`responsePreview`; se quitaron `background_tasks` y
`session_crons`, que venían de la forma de Claude (1.4) y el Stop real de zcode
no trae. **NO se agregó `lastAssistantMessage`**: la 11.6 lo midió AUSENTE — y
esa ausencia es justo lo que mantiene ciego al escenario 46. El 46 tampoco
recibió las tres claves de texto: modela un Stop sin ningún canal de texto, que
zcode no produce, y eso sigue declarado en su propio README. `responsePreview`
va igual a `responseText` porque el truncado real (4003 de 4522) solo aparece en
mensajes largos, y los de estos fixtures son cortos.

**Las otras dos fases también quedaron alineadas (Task 11.10):** los 10
`*.prompt.zcode.json` con sus 13 claves medidas (se quitó `prompt_id`) y los 22
`*.tool.zcode.json` con sus 21 (se quitaron `duration_ms` y `effort`).
`toolResultPreview` ahí es SINTÉTICO —los primeros 200 caracteres de la
serialización del `tool_response`— y por eso se declara: el preview real de
3637 chars es del turno capturado, no de estos escenarios. Ese cambio pisaba
las dos zonas de riesgo (el `toolInput` camel duplica `subagent_type` en el
payload crudo, terreno de A1; `toolResultPreview` duplica la salida de la
herramienta, terreno del guard de la 10.15) y **se midió que no movió ningún
veredicto**.

**Lo que queda AFUERA a propósito:** los fixtures zcode de
`tests/fixtures/arnes-falso/`. Son payloads mínimos para ejercitar la
HERRAMIENTA (`golden-harness`) con un hook falso, no un corpus de lo que manda
el host; el candado de forma los excluye y lo dice en el propio test.

Lo de abajo es el estado anterior (Task 11.8) y se conserva porque explica por
qué NO se tocaron antes de tener la medición: `docs/task-11.6-captura.md` registra
la forma real del Stop de zcode: 18 claves de primer nivel, con un matiz que
cambia el trabajo pendiente — **no todas se duplican en camelCase**
(`lastAssistantMessage` NO existe; sí se duplican `hook_event_name`,
`session_id`, `transcript_path`, `permission_mode`, `stop_hook_active`). O sea
que alinear contra la regla general de la 5.1 habría grabado otra adivinanza: se
alinea contra la lista medida. Lo que sigue abajo es el razonamiento con el que
se conservaron hasta esa medición, y se conserva porque explica por qué NO se
tocaron antes.

La captura real de la Task 5.1 (`docs/task-5.1-captura.md`) midió que zcode
emite CADA clave en snake_case **y** camelCase y que su Stop trae además
`responseText`/`responsePreview`. Los fixtures de los escenarios 17-25 traen
solo la forma snake_case con ambos literales de evento: son RECONSTRUCCIÓN de
la Phase 5, no captura. Con ese gap, la suite no puede distinguir hoy un canal
que llega completo de uno que llega truncado.

No se alinean en esta task porque **la Task 11.6 (captura manual con el
operador adelante) todavía no corrió**: alinearlos antes sería adivinar la
forma real y grabar la adivinanza en la línea base. Cuando la 11.6 mida, el
alcance restante de la 11.8 (que se reabre ese día) exige alinear estos
fixtures a lo capturado, con regrabación coordinada por UNA sola sesión, diff
auditado y veredictos movidos DECLARADOS — acá NO se promete "cero veredictos
movidos": cambiar la forma de los fixtures zcode va a mover veredictos y
ocultarlo sería el defecto.

Nota de numeración: no existe escenario 45 — el número queda reservado para
el escenario de la captura de la 11.6, para no elegir el siguiente a ciegas.

Lo que SÍ entró en la 11.8: el escenario `46-zcode-ambos-canales-ciegos`,
que ejercita en la capa dorada la rama de canales ciegos de la Task 11.4
(hasta ahora cubierta solo por gate_cases + mutaciones — lección de la 10.17:
cubierto por mutaciones != cubierto por la capa que graba COMPORTAMIENTO).

**El 46 cae bajo esta misma declaración, y hay que decirlo** (review 11.8 del
lead): es un fixture zcode NUEVO, con la misma reconstrucción snake_case que
sus hermanos, y encima su Stop OMITE `last_assistant_message` — que es
justamente lo que la 5.1 midió PRESENTE en un Stop real de zcode. O sea que el
46 tampoco describe la forma del host: fija la CONDUCTA de la rama (qué hace
el gate con los dos canales ciegos), que es lo que la capa dorada tiene que
grabar. Se declara acá y en su propio README para que nadie lo lea como
evidencia de que zcode manda Stops sin ese campo — si la 11.6 mide que el
campo llega siempre, lo que queda abierto es si esa rama alcanza a zcode
(Task 11.6(a)), no la validez de este escenario como candado de conducta.
