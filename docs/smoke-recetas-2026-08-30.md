# Smoke recetas — 2026-08-30 (Task 16.8, medición viva)

Medición viva de los **seis turnos del recetario** (`recetas/`) del harness
summonaikit. Quien escribió las recetas no es quien las mide: los seis turnos los
tecleó un **operador** en el repo laboratorio `C:/dev/saikit-recetas-lab`. Este
documento cubre la verificación del laboratorio (Parte A) y la evidencia de los
seis turnos extraída de los transcripts (Parte B).

Fecha: 2026-08-30. Transcripts leídos como **UTF-8** (con la codificación
equivocada salen mojibake y las citas quedan sucias):

- `C:/Users/ehven/.claude/projects/C--dev-saikit-recetas-lab/38e1034a-55cd-4604-8d4b-c5ea210be89d.jsonl` — turnos 1, 2, 3
- `C:/Users/ehven/.claude/projects/C--dev-saikit-recetas-lab/c943d622-43c0-4479-ba75-ee0bcf1208c2.jsonl` — turnos 4, 5, 6

## Parte A — Verificación del laboratorio (ESTADO ANTES DE LOS TURNOS)

> **Lectura obligatoria antes de creer esta sección:** describe el estado
> **ANTES** de los turnos. **Después** de que se escribió, el operador tocó el
> lab (ver subsección al final). Esta sección es la línea de base de la medición.

### Lab descartable (ANTES del turno)

- **Repo:** `C:/dev/saikit-recetas-lab` (git init, commit `b87e86f`
  "lab: app chica con /health y lista de tareas incipiente").
- **`app.py`** (~65 líneas): stdlib `http.server` (sin dependencias). `GET /health`
  → 200 `{"status":"ok"}`; lista de tareas incipiente en memoria (`TASKS = []`,
  `add_task(title)`, `delete_task(task_id)`); `POST /tasks` y `DELETE /tasks/<id>`.
- **`test_app.py`**: pytest, `2 passed` (`test_health_ok`, `test_add_and_delete_task`).
- **`.gitignore`** (ignora `__pycache__/`, `*.pyc`, `.pytest_cache/`).

### Hook stageado por override

- **Comando:** `bash tools/stage-override.sh C:/dev/saikit-recetas-lab` → **exit 0**.
- Instaló el hook de la rama `phase-16/16.8` (base `origin/master`, commit
  `743f946`) en `C:/dev/saikit-recetas-lab/.claude/hooks/summonaikit-harness.sh`.
  La rama 16.8 contiene las tasks 16.4+16.5+16.6 (menú de recetas, instalador que
  planta `recetas/`, alias `-saikit:pregunta`/`-saikit:boceto`).
- El hook **GLOBAL** `~/.claude/hooks/summonaikit-harness.sh` quedó **intacto**
  (stage-override lo midió: huella sha256 antes/después idéntica).
- El registro **prefiere el override** (stage-override lo midió ejecutando el
  comando registrado con un `HOME` desechable; exit 0 "MEDIDO: el registro
  prefiere el override del proyecto").
- Verificación independiente del lead: `sha256(hook stageado)` ==
  `sha256(hook de la rama 16.8)` = `6bcc4f9e4619e312`.

### Recetario al lado

Lo copió el instalador de 16.5 durante el staging.

- Archivos en `C:/dev/saikit-recetas-lab/.claude/hooks/recetas/`:
  `00-lider.md`, `MANIFEST.sha256`, `boceto.md`, `bug.md`, `funcion.md`,
  `investigar.md`, `lento.md`, `refactor.md`.
- `MANIFEST.sha256` del lab es **idéntico** al de la fuente
  `C:/dev/summonaikit-claude/recetas/MANIFEST.sha256` (comparado, igual).
- sha256 de las 6 recetas (`boceto`, `bug`, `funcion`, `investigar`, `lento`,
  `refactor`) coincide con su línea del manifiesto: **6 OK, 0 mismatch**.

### Menú que ofrece el hook

El menú que devuelve el hook stageado, al correrlo en el lab con un prompt
`-saikit`, ofrece las 6 recetas (cita literal del contrato):

```
Recipes (recetario): pick ONE that matches the task, read it in full, copy its steps into your todolist before reasoning, and declare it in the receipt as "Understand: ... Receta: <nombre>". A step you skip stays listed as "skip: <razón>". If none matches, follow this contract as usual.
- boceto — Probar una idea con variantes desechables — fast
- bug — Arreglar algo que no funciona — full
- funcion — Construir una función nueva — full
- investigar — Explicar cómo funciona algo — fast
- lento — Hacer algo más rápido — full
- refactor — Reorganizar sin cambiar el comportamiento — full
```

### Lo que el operador cambió DESPUÉS (para no dejar el lab desactualizado)

La Parte A quedó desactualizada porque el operador tocó el lab después de
escribirla. Dato, sin juicio:

- **Planteó los dos síntomas que los turnos 1 y 4 reportan** (commit `d1ac3a8`
  del lab): `/health` **antes** devolvía 200 y no tardaba; **ahora** responde 500
  en 2.0 s. El 500 es un campo del JSON que no existía (`STATS["total"]` leído de
  un dict vacío → `KeyError`); la lentitud es una config releída por request
  (`_cargar_config()` con `time.sleep(2)`). La batería quedó **verde a
  propósito** (`/health` no tenía test), para que el turno del bug tuviera que
  reproducir en la superficie real.
- **Sacó `.claude/` del control de versiones** del lab (commits `edb660f` y
  `4516377`).
- El lab **ya no está como lo describe la Parte A**: tiene **15 commits** (4 de
  set-up + 11 de los turnos) y ramas `master` / `fix/health-500` /
  `feat/tasks-crud` / `perf/health-sin-sleep`. La Parte A es el estado **ANTES**.

## Parte B — Los seis turnos (evidencia de los transcripts)

Cada turno se reporta con **(a) menú en el contrato**, **(b) `Understand: …
Receta:`**, **(c) pasos de la receta al todolist**, **(d) recibo cerrado / GATE**,
y **(e) alcance** (qué se pidió vs. qué se hizo, con cita). Lo no observado se
escribe `unknown` con el motivo; nada se rellena ni se infiere.

**Nota sobre el estilo de las citas:** las citas entre comillas son **verbatim**
del transcript (leído UTF-8). Las **negritas**, `backticks` y la puntuación
dentro de ellas son **énfasis del autor** de este doc para legibilidad y señalar
el dato; no están en los bytes del transcript. Si buscas la cadena exacta, quitá
esos marcadores de formato. La referencia "(línea N)" corresponde al número de
línea del archivo `.jsonl` de la sesión.

**Nota sobre el menú (a):** el menú con las 6 recetas aparece en el contrato
inyectado **una vez por sesión** (línea 62 del transcript de cada sesión), no en
cada turno por separado — el transcript guarda un solo `tool_result` del hook
con el contrato. Ese contrato es el que el modelo tuvo en contexto para los turnos
de la sesión (los seis turnos seleccionaron y declararon su receta, lo que
confirma que el menú estuvo disponible). La cita literal del bloque del menú es
la de la "Parte A — Menú que ofrece el hook" (idéntica en ambas sesiones).

### Turno 1 — `-saikit el endpoint /health devuelve 500` (Receta: **bug**)

- **(a) Menú en el contrato:** sí. El contrato inyectado de la sesión 1 (línea 62)
  ofrece el bloque `Recipes (recetario):` con las 6 recetas (cita en Parte A). Es
  un solo `tool_result` por sesión; el modelo lo tuvo en contexto.
- **(b) `Understand: … Receta: bug`** (cita literal del recibo, línea 315):
  "Reportaste que `/health` devolvía error 500. Lo reproduje yo mismo sobre el
  endpoint HTTP real antes de tocar nada. No tuve que preguntarte nada: el
  síntoma era concreto y la causa quedó clara en la primera lectura. **Receta:
  bug.**"
- **(c) Pasos de la receta al todolist:** **no se observó.** El modelo no usó
  herramienta de todolist (las tools del turno son `Bash`/`Agent`/`Write`; no hay
  `TodoWrite`) y no enumeró los pasos de la receta como lista previa. Lo más
  cercano es que **nombró** la receta y siguió sus pasos narrándolos (cita, línea
  96): "Recipe: **bug** (full lane). First, the lead's job — reproduce it myself
  on the real surface." No hay un todolist con los seis pasos copiados.
- **(d) Recibo:** **cerró** (recibo completo, línea 315). Sin GATE.
- **(e) Alcance:** se pidió `/health` — devuelve 500. Se hizo: reproducción del
  500 sobre HTTP, causa `STATS["total"]` leído de un dict vacío, test en rojo
  (`b126271`) y fix (`da64b96`). Alcance acotado: el modelo **no** tocó el
  `sleep(2)` y lo declaró como aparte (cita, línea 315): "Sigue pendiente lo que
  te avisé desde el principio: `/health` duerme 2 segundos en cada llamada. Es
  lentitud, no el 500 que reportaste, y no la toqué."

### Turno 2 — `-saikit agrega una lista de tareas con crear y borrar` (Receta: **funcion**)

- **(a) Menú en el contrato:** sí (misma sesión, línea 62).
- **(b) `Understand: … Receta: funcion`** (recibo, línea 952): "Pediste una lista
  de tareas con crear y borrar. Al revisar encontré que crear y borrar ya
  existían, que faltaba poder **ver** la lista, y que borrar estaba roto porque
  los números de tarea se reciclaban y podía eliminar la equivocada. No bloqueé
  con preguntas; declaré tres supuestos... **Receta: funcion.**"
- **(c) Pasos al todolist:** **no se observó.** Sin tool de todolist; el modelo
  arrancó el turno sin enumerar los pasos de la receta (cita, línea 333): "New
  task. Before I restate it, one thing needs checking — this repo may already
  have part of what you're asking for."
- **(d) Recibo:** **cerró** (recibo completo, línea 952). Sin GATE. En ese turno
  corrió además el **adversary** (cita, línea 952): "ADVERSARY: 10 findings,
  highest severity high." (es un dato del turno del operador, no de esta tarea).
- **(e) Alcance:** se pidió una lista de tareas con crear y borrar. Se hizo, en
  la rama `feat/tasks-crud`, bastante más: ids con contador monótono
  (`40a2013`), `GET /tasks` + validación de entrada + tope 1 MiB (`6a94742`,
  `52d852b`), cierre de 6 hallazgos y una revisión adversarial con 10 findings
  (`3e262b0`). El operador lo marcó como decisión inventada (cita literal, línea
  958): "1. te inventaste esa decision no es algo que yo tenga q decidir 2.
  nadie te pidio eso 3 si". Es la cita de alcance de este turno.

### Turno 3 — `-saikit limpia app.py sin cambiar lo que hace` (Receta: **refactor**)

- **(a) Menú en el contrato:** sí (misma sesión, línea 62).
- **(b) `Understand: … Receta: refactor`** (recibo, línea 1381): "Pediste limpiar
  `app.py` sin que cambie lo que hace. Sin preguntas: el objetivo era claro y la
  restricción, absoluta. **Receta: refactor.**"
- **(c) Pasos al todolist:** **no se observó.** Sin tool de todolist; el modelo
  arrancó cerrando un tema previo (cita, línea 984): "Two things at once —
  closing the loose end, then the new task." Más tarde sí **citó un paso** de la
  receta (citado en el input de la tool_use Agent que delegó la revisión, línea 1129): "Recipe: `refactor`, whose step 6 reads: ...", pero
  no copió los pasos a un todolist.
- **(d) Recibo:** **cerró** (recibo completo, línea 1381). Sin GATE.
- **(e) Alcance:** se pidió limpiar `app.py` sin cambiar el comportamiento. Se
  hizo: pin de comportamiento con 7 pruebas nuevas (`209ec95`), refactor de
  helpers + `conftest.py` (`23cef9a`, `564e78f`). Contrato cumplido (comparador
  diferencial: "ALL IDENTICAL: 22 cases"). Alcance acotado al refactor.

### Turno 4 — `-saikit /health tarda 2 segundos` (Receta: **lento**)

- **(a) Menú en el contrato:** sí. El contrato inyectado de la sesión 2 (línea
  62) ofrece el bloque `Recipes (recetario):` con las 6 recetas (cita en Parte A).
- **(b) `Understand: … Receta: lento`** (recibo, línea 472): "pediste que
  `/health` dejara de tardar 2 segundos. **Receta: lento.** No pregunté nada
  porque la causa y el arreglo son técnicos y reversibles; medí antes de mirar el
  código."
- **(c) Pasos al todolist:** **no se observó.** Sin tool de todolist; el modelo
  nombró la receta y arrancó la medición (cita, línea 132): "Recipe **`lento`**
  matches (full lane). Let me establish the baseline before forming any
  hypothesis."
- **(d) Recibo:** **cerró** (recibo completo, línea 472). Sin GATE.
- **(e) Alcance:** se pidió que `/health` dejara de tardar 2 s. Se hizo: eliminó
  el `sleep(2)` de `_cargar_config()` y el `import time` huérfano (commit
  `3564728`), más la corrección del docstring mentiroso. Cambio acotado, con
  medición antes/después (2.002 s → 0.00059 s).

### Turno 5 — `-saikit:pregunta cómo funciona /health` (Receta: **investigar**)

- **(a) Menú en el contrato:** sí (misma sesión 2, línea 62).
- **(b) `Understand: … Receta: investigar`** (recibo, línea 585): "preguntaste
  cómo funciona `/health`. **Receta: investigar** (carril fast por el alias
  `-saikit:pregunta`), sin tocar código de producción."
- **(c) Pasos al todolist:** **no se observó.** El modelo nombró el carril fast y
  la receta (cita, línea 506): "Fast lane by alias: `-saikit:pregunta` → recipe
  `investigar`. Read-only, no code changes. Let me read the current state and the
  history of that endpoint."
- **(d) Recibo:** **cerró** (recibo completo, línea 585). Sin GATE. Implement:
  "sin cambio de código". Verify: "no corrí la batería de tests — es una pregunta
  de solo lectura."
- **(e) Alcance:** se pidió cómo funciona `/health`. Se hizo: explicación con
  diagrama (`do_GET` → `health()` → `_cargar_config()` → `_json`), la tabla
  "qué devuelve" y una tabla de "con qué te vas a tropezar" (`GET /health?x=1`
  → 200, `GET /health/` → 404, `POST /health` → 404, `HEAD /health` → 501).
  Alineado al carril fast (lectura, sin tocar código).

### Turno 6 — `-saikit:boceto de la pantalla de tareas` (Receta: **boceto**)

- **(a) Menú en el contrato:** sí (misma sesión 2, línea 62).
- **(b) `Understand: … Receta: boceto`** (recibo, línea 771): "pediste un boceto
  de la pantalla de tareas. **Receta: boceto** (carril fast por el alias
  `-saikit:boceto`, que la línea 54 del contrato de este turno confirma). La
  decisión que el boceto resuelve: qué forma toma la pantalla y dónde vive
  «agregar» respecto de la lista... No pregunté antes de dibujar porque eso es
  precisamente para lo que sirve un boceto: un hecho que se observa mirando algo
  no es pregunta para ti."
- **(c) Pasos al todolist:** **no se observó.** El modelo nombró el carril fast y
  la receta (cita, línea 640): "Line 54 of this turn's contract confirms:
  `-saikit:boceto`, recipe `boceto`, no production code. (My diff a moment ago
  was misleading — the authoritative read is the line itself.)"
- **(d) Recibo:** **cerró** (recibo completo, línea 771). Sin GATE. Implement:
  "boceto desechable en `boceto/index.html`, sin tocar código de producción."
- **(e) Alcance:** se pidió un boceto de la pantalla de tareas. Se hizo: 3
  variantes desechables en `boceto/index.html` (A Lista, B Captura primero, C
  Tabla) + un conmutador de estado, y una recomendación ("Recomiendo A (Lista),
  robándole a B el manejo del error"). Encontró un hueco de datos: `done` no es
  modificable por ningún endpoint (cita, línea 771): "ninguna de las tres tiene
  casilla de **"hecho"**, y es a propósito" (y, en la misma línea, "no existe
  ningún endpoint que pueda cambiarlo"). Alineado al carril fast (sin código de
  producción).

## Lectura de resultados

- **Los 6 turnos cerraron con recibo** (`Receta:` declarada y recibo completo);
  **ningún GATE** bloqueó. No detecté el "cuarto bloque de recibo" que se
  anticipaba: cada sesión tiene 3 receipts, uno por receta, sin duplicados.
- **Todos los turnos nombraron la receta** y siguieron el carril correspondiente
  (los dos de alias bajaron a `fast`). Los turnos 5 y 6 además citaron el contrato
  para confirmar el alias.
- **(c) pasos al todolist: no se observó en ningún turno.** El modelo no usó una
  herramienta de todolist (ningún `TodoWrite`) y no enumeró los pasos de la
  receta como lista previa; nombró la receta y siguió sus pasos narrándolos o por
  delegación. Es el dato que esta task mide y quedó registrado tal cual, sin
  rellenar.
- **Alcance (e):** el turno 2 es el que más se expandió respecto de lo pedido
  (cambió el esquema de ids, agregó `GET /tasks`, validación, tope de tamaño y
  una revisión adversarial con 10 findings), y el operador lo marcó con "te
  inventaste esa decision no es algo que yo tenga q decidir". Los turnos 1, 3, 4
  se mantuvieron acotados; 5 y 6 cumplieron el carril (lectura / boceto).

## Alcance de este documento

Este documento **no** decide qué receta se promueve. Mover una receta a
`recetas/pendientes/` es decisión del **lead** (el brief de la 16.8 anula el paso
4 del plan). Este smoke trae las citas; el veredicto es de quien lo lee.
