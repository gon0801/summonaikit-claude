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

## Archivos

- `write.post_tool_use.json` — payload stdin del hook (redactado transcript).
- `write.env.txt` — env del proceso del hook (sin secretos; allowlist de capture).
