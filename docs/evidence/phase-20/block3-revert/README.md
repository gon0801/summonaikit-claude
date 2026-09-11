# Reversión del bloque 3 (20.15–20.17)

Fuente: revisión de Claude en la ventana `summonaikit-claude — Revisar pendientes` (2026-09-11).

## Qué se saca de master

- PR #303 (`2ed91ca`): launcher + recibo. `close_type` no producía `clean`; "recibo" se infería de `agents_seen` (un solo implementer bastaba); el escritor grababa el tipo que le pasaran (recibo fabricable); sin timeout, sin "rc=0 sin recibo ≠ éxito", sin aislamiento, sin mutantes.
- PR #304 (`6bbd4ee`): test vivo que hace `exit 0` si no hay binario (CI verde sin medir); trata `rc=0 sin recibo` como ok; "async" era un prompt Bash, no delegación.
- PR #305 (`4157c4c`): reescribió la DoD en el ledger. El contrato no se toca; el cierre va en la celda de estado. Se restaura la DoD original y `cc:TODO`.

PR #302 queda cerrado sin mergear (el contrato/launcher del spike no entra a master).

## Brief para rehacer (después de mergear esta reversión)

### 20.15 — spike de verdad
1. Medir cómo el launcher conoce su propia sesión. Claude `-p --output-format json` devuelve `session_id` (ya usado en 20.9/20.10).
2. Derivar `STATE_PATH` igual que el hook: `$HOST` + `cksum` de la ruta + `SESSION_KEY`. Sin glob.
3. Medir Grok: hoy no está medido.
4. Reproducir teardown **sin Stop** en vivo. No citar 18.27 como evidencia.

### 20.16 — DoD original
- Recibo completo de ejecución propia permite éxito.
- Ausencia observada / incompleto / timeout **no** son éxito aunque host rc=0.
- Captura no observable → `unknown`.
- Sin recibos fabricados ni relanzamiento silencioso.
- Mutantes y aislamiento (dos sesiones concurrentes; el código viejo habría salido rojo).

### 20.17 — DoD original
- Cadena host/hook/supervisor/estado para positivo **y** falta de recibo.
- Invocación directa sigue fuera de garantía.
- Éxito no se atribuye a r2 histórico; `unknown` no cierra.
- Skip-if-no-binary **no** puede contar como PASS en CI.
