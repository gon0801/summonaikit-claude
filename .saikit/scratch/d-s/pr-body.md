## D-S — residuales A.R2–A.R11 del bloque A

Bloque D del plan entrega-sin-sello. Implementado por: **glm**. PR en borrador para la revisión cruzada con `-Excluir glm`. No cierra filas en `Plans.md` (lo hace el lead tras el merge) y no reabre la entrega A.

### Contrato de entrega (`tools/lib/entrega_contract.sh`, `veredicto_contract.sh`)

- **A.R2** — el contador del mensaje de bloqueantes contaba mal por un off-by-one (`substr($1,14)` sobre `bloqueantes[<i>]` se comía el índice <10: "0 en la lista" habiendo entradas). Corregido a `substr($1,13)`; caso que afirma "1 en la lista" con 1 y "12 en la lista" con 12.
- **A.R3** — un REVOKE posterior del mismo autor SIN el sha completo avisa `REVOKE visto sin efecto: ... el recibo sigue vivo` y no cambia nada (antes era silencio total y el operador creía haber revocado). Caso con rc 0 + aviso; el REVOKE válido sigue igual (caso existente en verde).
- **A.R4** — regla decidida y documentada en los LIMITES DE ATRIBUCION del propio archivo (donde hoy se prometía lo contrario): **un comentario que trae REVOKE no aprueba nada**, aunque también traiga un APPROVE con bloque válido; el REVOKE con sha anula el recibo vigente; revocar y volver a aprobar exige dos comentarios. Caso de cada lado (primer comentario mixto ⇒ rc 1 "sin recibo"; mixto tras recibo ⇒ rc 1 "revocado") + mutación atrapada (escotilla `entrega_body_trae_revoke` anulada ⇒ el mutante aprueba lo que el gate debe rechazar).
- **A.R5** — una página JSON-válida que no es una LISTA de comentarios (por ejemplo un error de la API) salía como "sin recibo"; ahora es rc 3 `la pagina no es una lista de comentarios`. Caso incluido; las páginas de lista válidas no cambian (todo el grupo loader sigue en verde).
- **A.R10** (`[lane:fast]`) — comentarios alineados con el parser: el parser RECHAZA claves duplicadas, así que no existe la precedencia "vale la primera" que describían los comentarios de `entrega_bloqueantes_no_vacio` y `saikit_json_get`. La cobertura documental que reporta CodeRabbit (55.80%) se evalúa según la fila: no se amplía código por el porcentaje del bot. Contexto del bloque: PR #345.

### Lock de integración (A.R6, `tools/saikit-merge.sh`)

Recuperación de dueño LOCAL muerto con exclusión atómica, como pedía el A8. Al encontrar el lock ocupado, el script clasifica al dueño:

- **identidad indeterminable** (sin pid, pid no numérico, sin host) ⇒ no borra, informa la clase y sale 3: otros carriles siguen;
- **host ajeno** ⇒ ídem, nombra el host;
- **dueño local vivo** ⇒ no se roba un merge en curso (igual que ayer);
- **dueño local muerto** o **pid reciclado** (el proceso del pid es más joven que el lock: comparación `ps -o etime=` contra la edad de `started_at`) ⇒ recuperación **atómica por reclamo**: `mv` a una tumba (el mv es el árbitro entre dos recuperadores), re-verificación del pid dentro de la tumba, y mkdir nuevo; el perdedor de la carrera sale 3 sin tocar nada.

`--liberar-lock` sigue siendo la salida explícita. Costura de test `SAIKIT_MERGE_RECUPERAR_PAUSA` (0 en producción), mismo precedente que `SAIKIT_MERGE_SOSTENER_SEG`. Casos: muerto, pid reciclado, host ajeno, identidad indeterminable y dos recuperadores (exactamente un ganador); `lock_caida_no_libera_ajeno_recuperacion_explicita` quedó reescrito al contrato nuevo. La mutación `recuperacion_sin_arbitro` (mv → cp: sin exclusión) vive en la tabla MUTS del banco, que se audita a sí mismo.

### Golden y helpers (A.R7)

El único helper sin llamadores era `saikit_secret_re` en `tools/lib/redactar.sh` (la variable `SAIKIT_SECRET_SCAN_RE` se usa directo): retirado. Golden regrabada con `bash tools/golden-harness.sh --record` (57 escenarios): **diff vacío** contra la baseline anterior, auditado y clasificado — sin cambios, la golden ya no llevaba forma vieja; `--check` verde tras el retiro.

### Hook bajo prueba y coordenadas (A.R9)

- (a) El override `SAIKIT_HOOK_VIVO` ya estaba cableado en `tests/run.sh` y en el harness del golden; lo añadido es su documentación en la entrada del runner, con el default real (la copia instalada del operador) y la receta determinista de desarrollo.
- (b) Verificado que hoy NO queda ningún caso que el CI de Linux deje de correr: los únicos skips vivos son guardas de forma MSYS cuyo camino Linux corre en CI, y el runner nombra los SKIP sin ejecutor. Sin cambio de código; declarado.
- (c) Hecho: coordenadas vacías (repo/pr/sha) ⇒ rc 3 `coordenadas vacias` en `entrega_validar` y `entrega_recibo_del_pr` (con sha vacío, `grep -Fq ""` matchea cualquier cuerpo). Caso `coordenadas_vacias_rechazadas`.

### CI (A.R11)

La mitad rápida pasa de 7 a 8 shards (`SAIKIT_SHARD=i/8`). Medido en el run 35553346727: con N=7 el round-robin ponía los dos pesados en el MISMO shard 2 (`test_feature_map_merge`, pos 23; `test_install_muse_mutations`, pos 44; ambos ≡ 2 mod 7) y ese job llegó a 13m32s. Con N=8 caen en shards distintos (7 y 4). Sin omitir tests y sin gate nuevo: la unión sigue siendo la partición entera y el candado (`test_runner_guards.sh`: matrix 1/N..N/N completa + unión exacta) pasa en verde con el cambio. La duración nueva la mide el CI de este PR. AGENTS.md actualizado.

### Rojo primero y mutaciones

Evidencia en `.saikit/scratch/d-s/`: `verde-test_entrega_contract.log` (26 casos previos + 7 nuevos, rc 0), `verde-test_saikit_merge.log` (banco completo con A.R6, rc 0), `verde-test_runner_guards.log` (rc 0) y las mutaciones por arreglo: `mut-ar2-substr14.log`, `mut-ar3-sin-aviso.log`, `mut-ar5-sin-lista.log`, `mut-ar9c-sin-guarda.log` — cada arreglo revertido deja su caso en rojo; las mutaciones de A.R4 y A.R6 corren dentro del banco (tabla MUTS, autoauditada). Tres commits por área (contrato de entrega, lock, CI/docs); una cross-review cubre el bloque entero.

### Lo que no implementé, y por qué

- **A.R8 (re-pin de CLAUDECODE): no implementado.** El pin concreto que pidió el review M3 no está en ninguna fuente recuperable: ni en el cuerpo, comentarios ni reviews inline del PR #345, ni en `.saikit/findings/`, ni en el rastro de decisiones. Las dos lecturas posibles tocarían el fallback `CLAUDECODE` del hook, que tiene comportamiento medido y mutaciones propias (G1); cambiarlo a ciegas es inventar el requerimiento. La fila queda abierta con esta declaración.
- **A.R9(b)** no llevó código porque el estado del repo ya lo cumple (verificado arriba, sin caso huérfano hacia CI Linux).
- **Cobertura documental (A.R10)**: decisión declarada de no ampliar código por el porcentaje del bot, como la propia fila manda.

### Ronda de CI

La primera corrida de CI dejó dos rojos en suite 2/8, ambos de esta rama y corregidos en el último commit: (1) el pin de `tools/MANIFEST.sha256` quedó viejo al tocar `saikit-merge.sh` (lo canda `test_pretool_merge`); (2) en un runner cargado, la comparación etime-vs-edad del lock leyó "reciclado" un dueño vivo por jitter de ~1 s — la clasificación ahora exige una diferencia mayor a 5 s (el caso real de pid reciclado lleva el lock huérfano años, el margen no lo toca). Re-medido local: `test_saikit_merge`, `test_pretool_merge` y `test_runner_guards` en rc 0. La segunda corrida de CI de este SHA es la válida para el bloque.
