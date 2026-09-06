# 18.26 — payload real del write del reviewer hijo (Grok)

Capturado 2026-09-06 con `tools/capture-payloads.sh --host grok` en repo
descartable `/private/tmp/saikit-1826-cap-*`, Grok 1.0.13 headless
(`-p --always-approve`), trust temporal en `trusted_folders.toml` restaurado
a vacío al terminar.

## Hallazgo

El write del hijo **sí trae atribución verificable**: `subagentType: "reviewer"`
de primer nivel (mismo canal que midió 7.1 para internos). También trae
`toolName: "write"`, `toolInput.file_path` y `toolInput.content`.

La sesión del evento es la del **hijo** (distinta del padre). El
`user_prompt_submit` del hijo **no** contiene `-saikit`, así que el harness
no arma estado y el early-exit de `record_tool_evidence` sale antes del sello.

El smoke de 18.9 diagnosticó «sin atribución»; la medición de esta fila
corrige eso: la atribución existe; falta sostener el sello cuando el hijo
escribe sin sesión armada.

## Límite del vínculo entre sesiones

La captura identifica al hijo y su rol, pero no incluye un identificador del
padre. Eso no demuestra que ninguna versión o canal de Grok pueda aportar
ese vínculo; con la evidencia disponible, la asociación es `unknown`.

El intento de elegir otra sesión por mtime, `verified:` o `task_hash`
(`02e15c4`) mezclaba evidencia: un reviewer independiente podía agregar su
sello y `agents_seen=reviewer` a una sesión ajena. Ese camino se retira.
El sello se conserva exclusivamente en la sesión emisora (`lane=seal_boot`),
sin armar la ceremonia ni modificar estados o logs de otras sesiones.

**El recorrido medido de autopilot en Grok queda con merge manual del
operador.** El sello local no reúne por sí solo la evidencia de blast que
D18 exige en la misma sesión. No se copian logs, no se atribuye el reviewer
al padre por heurística y no se relajan las validaciones de `saikit-merge.sh`.
Para habilitar ese recorrido automático hace falta medir un vínculo
padre-hijo verificable y probar el consumo conjunto; no se declara resuelto
por el solo hecho de que el hash exista.

Regresión: `verdict_unarmed_no_toca_sesion_verificada` y
`verdict_unarmed_no_toca_sesion_armada` ejecutan el hook copiado con las
señales de host Grok. Comparan byte a byte estado y log de la sesión ajena
antes y después de Write/Stop, y exigen el sello en la sesión emisora.
La mutación `sello_cruza_sesion` redirige la escritura a otra sesión y debe
ser atrapada por el primer caso.

## Archivos

- `write.post_tool_use.json` — payload stdin del hook (redactado transcript).
- `write.env.txt` — env del proceso del hook (sin secretos; allowlist de capture).
