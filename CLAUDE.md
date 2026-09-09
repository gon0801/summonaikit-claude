<!-- >>> QUALITY-KIT CALIDAD SECTION START -- managed by quality-kit's init-repo.ps1. Do not hand-edit between these markers; re-running init-repo.ps1 will refresh this block cleanly. -->
## Calidad (quality-kit)

Este archivo `.pre-commit-config.yaml` tiene agregados propios (detectados por quality-kit) -- no lo pisamos.
Para ver que candados tiene realmente: `pre-commit run --all-files` (o mira `.pre-commit-config.yaml`).

Reglas de hierro:
1. Si un candado falla, se arregla el problema real -- JAMAS se usa `--no-verify` ni se saltea un candado.
2. Cada bug arreglado incluye, en el mismo cambio, una prueba que lo habria atrapado.
8. CI: la bateria completa corre en jobs paralelos cuya union es la bateria (con candado); si un job pasa de ~10 min se shardea, nunca se recorta ni se saltea por tipo de cambio.
   Checks de docs/ledger en un job propio de segundos. Carril: docs/chore/cierre = fast; codigo = gate; medicion/release = +cross-review. Cierres de ledger de un bloque = un PR.

Flujo de verificacion:
- Durante la implementacion, corre solo las pruebas focalizadas del comportamiento modificado.
- Agrupa los hallazgos de revision y corrigelos en una sola ronda por bloque.
- Ejecuta Ruff y las pruebas focalizadas despues del ultimo cambio del bloque.
- Ejecuta la bateria completa una sola vez por bloque, sobre el commit final y preferentemente en CI mediante PR.
- Si commit, push o CI ya validaron tests, Ruff o pre-commit sobre ese SHA, no los repitas manualmente.
- No vuelvas a ejecutar CI si el commit verificado no cambio.
- Una observacion tardia menor queda pendiente; solo seguridad, datos, reglas innegociables o el comportamiento solicitado reabren el ciclo.
- Despues del deploy, ejecuta una sola vez el checklist del repo y no repitas evidencia valida sin un cambio que pueda invalidarla.
<!-- >>> QUALITY-KIT CALIDAD SECTION END -->

Candado extra (repo-hygiene, `install-repo-hygiene.ps1`): `context-docs-budget` —
CLAUDE.md raíz ≤200 líneas, anidados ≤80, AGENTS.md ≤400, sin diarios de sesión.
Sweep manual de basura (reporta, no borra): `python tools/check_context_docs.py . --sweep`.

## Formato del receipt del harness (regla del operador, 2026-09-03)

El `SUMMONAIKIT HARNESS RECEIPT` se entrega SIEMPRE con un parrafo por
punto: **Understand:**, **Implement:**, **Verify:**, **Review:**, **Close:**,
**Retro:** — cada etiqueta abre su propio parrafo, sin mezclar puntos ni
dejar etiquetas sin parrafo. (Cuando corrio adversario o hubo fallback de
rol, sus lineas van con el mismo trato.)
