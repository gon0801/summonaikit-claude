# 20.22 — Adopción por proyecto del autopilot (preparación, sin activación)

Fila `[Optional]` `[lane:release]` `[tdd:skip:medición]`. Entregable: la
DECISIÓN preparada, no la activación. No se corrió el setup, no se escribió
ninguna config, no hubo mutación remota fuera del PR docs-only de esta
evidencia.

## Identidad de ESTA evidencia

| Campo | Valor |
|---|---|
| Fecha | 2026-09-13 |
| Checkout kit (esta evidencia) | `76e92bb7a757ae45f6faa5d242a0b3bcbbf2cba9` (HEAD == origin/master, árbol limpio) |
| Hook | sha256 `37e55640003afaff6d4a54cf6495afc73bec5799b86323fb7a317889fec78680` (4345 líneas, sin drift) |
| Drift del checkout | DRIFT declarada: el pin de referencia era `e0f7a25`; master avanzó con merges docs-only (20.20, cierre 20.15–20.17 #311). Hook SIN drift. |

## Estado: la ausencia de config es ESTADO, no bug

Verificado en este checkout: `.saikit/` existe (decisiones, findings,
scratch, triage-patrones.md, veredictos) y `.saikit/autopilot.json` NO
existe (`test -f` negativo). Este repo (kit `summonaikit-claude`) permanece
opt-in: sin config, el merge del autopilot no corre.

No confundir con el lab/descartable (`gon0801/saikit-descartable`), que SÍ
tiene uno — `merge=true, despliega=no, sin_verify_app=si, rama=main` — usado
en 20.10 y 20.14. Esa config vive en OTRO repo y no se tocó (tope ≤15 PRs de
fase intacto: cero mutación remota allí en esta fila).

## Las cinco decisiones de adopción (leídas de `tools/saikit-setup-autopilot.sh`)

El tool pregunta (o recibe por flag) exactamente cinco cosas y escribe el
JSON que `tools/saikit-merge.sh` lee SOLO de `origin/<rama>`. Para ESTE
proyecto (kit, rama `master` por default) quedan PREPARADAS así — propuesta
del implementer, pendiente de autorización explícita del proyecto:

| # | Pregunta del tool | Clave JSON | Propuesta preparada | Razón |
|---|---|---|---|---|
| 1 | ¿Mergear solo con tu sí explícito? (si/no) | `merge` | `false` (default seguro) | el kit es el repo fuente: ningún merge automático sin sí del operador |
| 2 | ¿Mergear a la rama publica la app? (si-publica/no/no-se) | `merge_despliega` | `"unknown"` (default `no-se`) | el kit publica herramienta, no app desplegable; nadie lo declaró todavía, y `unknown` no es `false` |
| 3 | ¿URL https para checar que la app sigue viva? (vacío = ninguna) | `salud_url` | `null` | no hay URL de salud del kit; vacío = ninguna |
| 4 | ¿Sin prueba de la app, mergeo solo? (si/no) | `sin_verify_app` | `false` (default seguro) | sin verificación no hay merge solo |
| 5 | ¿Aviso por Telegram cuando el post-merge mire el run? (si/no) | `telegram` | `false` (default seguro) | sin canal de aviso configurado en este proyecto |

Defaults no preguntados que el tool fijaría: `rama=master`,
`revert_si_rojo=true` (nota del tool: bajo la 18.5 reducida ese campo queda
inerte — no hay revert automático que lo consuma, solo el aviso con el
comando listo).

Efecto de merge explícito ANTES de habilitar: con `merge=false`, habilitar
la config NO cambia ningún comportamiento (el gate sigue exigiendo sí
explícito); publicar una config con `merge=true` SÍ habilitaría merges del
autopilot en este repo — por eso la config publicada exige autorización
explícita de ESTE proyecto, que NO ha sido dada.

## Rollback REVERSIBLE (antes de habilitar, ya definido)

1. La config vive en UN archivo versionado: `.saikit/autopilot.json`.
2. Revertir = borrar el archivo (o revertir el commit que lo publicó) vía
   PR normal; el merge tool lee SOLO de `origin/<rama>`, así que el rollback
   se verifica contra origin (`git show origin/master:.saikit/autopilot.json`
   debe volver a no existir).
3. Lock: el setup toma lock atómico por `mkdir` en
   `$(git rev-parse --git-common-dir)/saikit-autopilot.lock`; un lock ajeno
   se REPORTA y BLOQUEA (exit 3), nunca se borra solo — solo
   `bash tools/saikit-setup-autopilot.sh --liberar-lock` lo quita.
4. Sin consentimiento permanece opt-in: este plan NO activa nada.

## Decisión: APLAZADA (preparada, no implementada)

Se APLAZA la adopción en este repo: la tabla de arriba es la respuesta
preparada a las cinco preguntas y el rollback queda definido, pero
`.saikit/autopilot.json` NO se escribe (esa habilitación exige autorización
explícita que NO ha sido dada). Esto se registra como DECISIÓN, no como
implementación completada.

## Qué quedó `unknown` o FAIL (con razón)

- `unknown`: las respuestas DEFINITIVAS a las cinco preguntas — las
  propuestas de la tabla son del implementer; solo el operador/proyecto las
  convierte en config con autorización explícita.
- `unknown`: si el proyecto querrá `merge=true` algún día (sin demanda
  medida; el kit se mergea hoy por PR manual del lead).
- Ningún FAIL. Cero mutación remota fuera del PR docs-only del kit.

## Veredicto de la fila

Destino/opciones/efecto de merge explícitos antes de habilitar; config
publicada solo con autorización del proyecto (no dada); verificación contra
origin y rollback definidos; sin consentimiento permanece opt-in, sin
activación por este plan. DoD completa. Lista para cierre del lead.
