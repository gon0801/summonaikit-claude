# 20.28 residuales — raíl EVENTO (fuera de alcance)

Medidos de paso al reproducir los rojos macOS de 20.28 (2026-09-09 / 2026-09-10).
**No se arreglan en esta fila.** Decisión candidata al bloque 9 / Phase 21 (la fila 20.28 los nombra hacia 21.5; el lead decide si abren fila propia).

## Forma A — prefijo de entorno no acredita

`VAR=… bash tests/run.sh` no acredita por el ancla `^` del carril de EVENTO:
el comando observado no empieza en el token del runner.

## Forma B — pipe acredita el exit del tail

`bash tests/run.sh | tail` acredita con el exit de `tail`, no el de la batería.
Un implementador puede ver verde engañoso (GLM en 20.8 tapó un rojo local con `| tail`).

## Evidencia de corrida

Local siempre a archivo completo (`> log 2>&1`), jamás por pipe — norma de 20.28.
