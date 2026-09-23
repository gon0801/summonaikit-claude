# D-S — residuales A.R2–A.R11 del bloque A (TDD)

Rama `entrega-sin-sello-d-kit-a` desde `origin/master` (86c5988). Trabajo del
2026-09-22. Implementador: glm.

## Por fila

- **A.R2 (ADV-A-02)** — `substr($1,14)` → `substr($1,13)` en el contador de
  bloqueantes (`tools/lib/entrega_contract.sh`). Caso
  `bloqueantes_conteo_exacto_en_el_mensaje`: el mensaje dice "1 en la lista"
  con 1 y "12 en la lista" con 12. Mutación (substr de vuelta a 14) ⇒ caso
  rojo (`mut-ar2-substr14.log`).
- **A.R3 (ADV-A-03)** — un REVOKE sin el sha completo del mismo autor avisa
  "REVOKE visto sin efecto" y no hace nada. Caso
  `revoke_sin_sha_avisa_y_no_hace_nada` (rc 0 + aviso). Mutación (quitar el
  aviso) ⇒ rojo (`mut-ar3-sin-aviso.log`).
- **A.R4 (ADV-A-04)** — regla decidida: un comentario que trae REVOKE no
  aprueba nada, aunque traiga también un APPROVE con bloque válido; el REVOKE
  con sha anula el recibo vigente; revocar y volver a aprobar exige dos
  comentarios. Documentada en los LIMITES DE ATRIBUCION del mismo archivo,
  que es donde hoy se prometia lo contrario. Casos: lado 1
  (`revoke_y_approve_mismo_comentario_no_aprueba`, primer comentario mixto ⇒
  rc 1 "sin recibo") y lado 2 (`revoke_con_sha_tras_recibo_sigue_revocando`,
  rc 1 "revocado"). Mutación con escotilla `entrega_body_trae_revoke` anulada
  ⇒ el mutante aprueba lo que el gate debe rechazar, atrapada en suite
  (`mutacion_revoke_dejado_de_bloquear_atrapada`).
- **A.R5 (ADV-A-05)** — página JSON-válida que no es lista ⇒ rc 3 "la pagina
  no es una lista de comentarios". Caso `pagina_no_array_es_desconocido`. Las
  páginas válidas sin cambios: los casos de loader existentes siguen verdes.
  Mutación (quitar el chequeo) ⇒ rojo (`mut-ar5-sin-lista.log`).
- **A.R6 (lock A8)** — `tools/saikit-merge.sh`: al encontrar el lock ocupado,
  clasifica al dueño. Identidad indeterminable (sin pid o pid no numérico, sin
  host), host ajeno o dueño local vivo ⇒ exit 3 informando la clase, el lock
  no se toca, otros carriles siguen. Dueño local muerto o pid reciclado (el
  proceso del pid es más joven que el lock, comparando `ps -o etime=` con la
  edad de `started_at`) ⇒ recuperación ATÓMICA por reclamo: mv a una tumba (el
  mv es el árbitro entre dos recuperadores), re-verificación del pid dentro de
  la tumba, y mkdir nuevo; el perdedor de la carrera sale 3 sin tocar nada.
  `--liberar-lock` sigue siendo la salida explícita. Costura de test
  `SAIKIT_MERGE_RECUPERAR_PAUSA` (producción = 0). Casos:
  `lock_recupera_dueno_local_muerto`, `lock_recupera_pid_reciclado`,
  `lock_host_ajeno_no_se_toca`, `lock_identidad_indeterminable_no_se_toca`,
  `lock_dos_recuperadores_un_solo_ganador`; `lock_caida_no_libera_ajeno_...`
  reescrito al contrato nuevo (la caída deja huerfano, el tercero lo recupera
  y mergea; la vía explícita se sigue probando con un lock plantado). La
  mutación `recuperacion_sin_arbitro` (mv → cp: desaparece la exclusión) está
  en la tabla MUTS del banco y el banco se audita a sí mismo: sin el árbitro
  nadie recupera y el caso queda rojo.
- **A.R7 (M1, helpers muertos + golden)** — `saikit_secret_re` en
  `tools/lib/redactar.sh` era el único helper sin llamadores (la variable
  `SAIKIT_SECRET_SCAN_RE` se usa directo); retirado. Golden regrabada con
  `bash tools/golden-harness.sh --record` (57 escenarios): **diff vacío**
  contra la línea base anterior — auditado y clasificado: sin cambios, la
  golden ya no llevaba forma vieja; `--check` en verde después del retiro.
- **A.R8 (M3, re-pin de CLAUDECODE)** — NO IMPLEMENTADO. El pin concreto que
  el review pidió no está en ninguna fuente del repo ni del PR #345 (cuerpo,
  comentarios, reviews inline, findings ni rastro de decisiones); las dos
  lecturas posibles tocarían el fallback CLAUDECODE del hook, que tiene
  comportamiento medido y mutaciones propias (G1). Se declara unknown con esta
  razón y la fila queda abierta.
- **A.R9** — (a) el override `SAIKIT_HOOK_VIVO` ya está cableado
  (`tests/run.sh` lo resuelve y lo pasa a los tests; el harness del golden
  tiene `--hook`); lo que faltaba es la documentación en la entrada del
  runner: añadido al encabezado de `tests/run.sh`, con el default real (la
  copia instalada) y la receta determinista. (b) verificado que HOY no queda
  ningún caso que el CI de Linux no corra: los únicos skips vivos son guardas
  de forma MSYS ("sin symlinks reales") cuyo camino Linux corre en CI, y el
  runner nombra los SKIP sin ejecutor — la excepción Windows-bound sigue
  vacía; sin cambio de código, declarado. (c) hecho: coordenadas vacías
  (repo/pr/sha) ⇒ rc 3 "coordenadas vacias" en `entrega_validar` y
  `entrega_recibo_del_pr`; caso `coordenadas_vacias_rechazadas`. Mutación
  (quitar las guardas) ⇒ rojo (`mut-ar9c-sin-guarda.log`).
- **A.R10 (lane:fast)** — comentarios alineados con el parser: el parser
  RECHAZA claves duplicadas (veredicto_contract.sh), así que no hay
  precedencia "vale la primera" que documentar; corregido el comentario de
  `entrega_bloqueantes_no_vacio` y el de `saikit_json_get`. La cobertura
  documental del 55.80% se evalúa y se decide NO ampliar código por el
  porcentaje del bot (lo que dice la propia fila); el enlace a #345 queda en
  este PR.
- **A.R11** — `.github/workflows/quality.yml`: la mitad rápida pasa de 7 a 8
  shards. Medido el run 35553346727: con N=7 el round-robin ponía los dos
  pesados en el MISMO shard 2 (`test_feature_map_merge`, pos 23 y
  `test_install_muse_mutations`, pos 44, ambos ≡ 2 mod 7) y ese job llegó a
  13m32s. Con N=8 caen en shards distintos (7 y 4); la unión sigue siendo la
  partición entera y el candado (`test_runner_guards.sh`, matrix 1/N..N/N
  completa) se mantiene en verde. AGENTS.md actualizado. La duración nueva la
  mide el CI de este PR.

## Evidencia

Por revision del bloque D los logs crudos de corrida locales no se versionan
(rutas de esta maquina, ningun gate los usa). Las mediciones quedan citadas en
el cuerpo del PR y aqui, en una linea por cada una:

- Verde con produccion: test_entrega_contract (26 casos previos + 7 nuevos,
  rc 0), test_saikit_merge (banco completo con A.R6, rc 0),
  test_runner_guards (rc 0) y golden-harness --check.
- Mutaciones atrapadas: substr 13 -> 14 ⇒ caso del conteo rojo; quitar el
  aviso de REVOKE sin sha ⇒ caso rojo; quitar el chequeo de pagina no-array
  ⇒ caso rojo; quitar las guardas de coordenadas ⇒ caso rojo; la mutacion de
  A.R4 (escotilla entrega_body_trae_revoke anulada) y la de A.R6
  (recuperacion_sin_arbitro) corren dentro del banco (tabla MUTS,
  autoauditada).

## Ronda de revision del bloque D (grok)

- Bug: el sed de `recuperacion_sin_arbitro` llevaba el delimitador escapado
  (`\|`), sed salia 1 sin cambiar nada y el banco acreditaba una mutacion que
  no existio. Arreglo doble: el s cierra sin escapes (patron y reemplazo sin
  barra final, que sed matchea como subcadena), y `mut_sed` ahora mira el exit
  del sed y rechaza un mutado vacio antes de acreditar nada. Verificado: la
  mutacion se aplica (mv -> cp -R) y queda atrapada por
  c_lock_dos_recuperadores, con el control sano en verde.
- Bug: `segundos_de_vida` metia etime con ceros a la izquierda en la
  aritmetica; `08`/`09` abortaban (octal invalido) y un pid reciclado en esa
  ventana se clasificaba vivo. Arreglo: prefijo `10#`. Caso nuevo
  `lock_recupera_pid_reciclado_con_etime_08` (ps que contesta `08:00:01`);
  rojo medido antes del arreglo con el error exacto
  (`08: value too great for base`).
- Los .log de corridas locales salieron del repo; las citas de este documento
  y del cuerpo del PR quedan como registro.

## Pruebas focales

`bash tests/test_entrega_contract.sh`, `tests/test_saikit_merge.sh`,
`tests/test_runner_guards.sh` y `tests/golden-harness.sh --check` en rc 0.
La batería completa corre una vez en CI sobre este SHA.

## Ronda de CI (mismo PR)

- Primera corrida del CI: suite 2/8 en rojo por DOS causas, ambas del lado de
  esta rama: (1) el pin de `tools/MANIFEST.sha256` quedó viejo al tocar
  `saikit-merge.sh` (test_pretool_merge lo canda: "pin desactualizado"); (2)
  en un runner cargado, la comparación etime-vs-edad del lock leyó "reciclado"
  un dueño VIVO por jitter de ~1 s y el contendor recuperó un lock que el
  banco esperaba bloqueado. Arreglo: margen de 5 s en esa comparación (el caso
  real de pid reciclado lleva el lock huérfano años; el margen no lo toca) y
  pin regenerado. `test_saikit_merge`, `test_pretool_merge` y
  `test_runner_guards` en rc 0 local tras el ajuste; el CI de este mismo PR
  re-mide todo.
