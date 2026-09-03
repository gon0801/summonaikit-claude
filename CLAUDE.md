<!-- >>> QUALITY-KIT CALIDAD SECTION START -- managed by quality-kit's init-repo.ps1. Do not hand-edit between these markers; re-running init-repo.ps1 will refresh this block cleanly. -->
## Calidad (quality-kit)

Candados de commit instalados (pre-commit):
- base (limpieza de archivos)

Comandos para correr los candados a mano:
- `pre-commit run --all-files` (todos los candados de commit)

Reglas de hierro:
1. Si un candado falla, se arregla el problema real -- JAMAS se usa `--no-verify` ni se saltea un candado.
2. Cada bug arreglado incluye, en el mismo cambio, una prueba que lo habria atrapado.
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
