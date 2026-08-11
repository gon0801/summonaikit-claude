# Task 3.4 — A4: estado por proyecto y sin revalidar el sentinel (plan para revisión)

> Borrador para revisión cruzada **antes** de ejecutar. `[Guardrail]` `[lane:gate]`
> `[tdd:required]`. DoD íntegra en `Plans.md:64`. Este doc replica la estructura de
> `docs/task-3.3-plan.md`. Lo que está acá es lo que se va a implementar salvo que la
> revisión lo mueva.

## El defecto, con su huella exacta

**A4** (`Plans.md:64`, `docs/spec/00-project-spec.md:73`):

> Estado llaveado por proyecto y sin revalidar el sentinel — un turno `-saikit`
> abandonado sigue cobrando recibo a turnos que no lo pidieron (reproducido en vivo
> el 2026-08-08, obligó a un borrado manual).

La raíz, medida en el código (`hooks/summonaikit-harness.sh`):

1. **El estado se llavea solo por proyecto.** Líneas 39-43:
   ```sh
   STATE_ROOT="$HOOK_DIR/state"
   PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
   STATE_DIR="$STATE_ROOT/$PROJECT_KEY"
   STATE_PATH="$STATE_DIR/harness-state.env"
   ```
   Dos sesiones del mismo repo computan el mismo `PROJECT_KEY` y comparten
   `$STATE_PATH`. El campo `session_id` **viaja en cada payload** (primera clave;
   declarado en `00-project-spec.md:1047` y en `tests/fixtures/README.md:28-45`,
   forma calcada de la captura de la Task 1.4) pero el hook **nunca lo lee**.

2. **El sentinel se valida una sola vez**, al armar (`start_harness`, línea 574):
   ```sh
   if ! printf '%s' "$prompt_text" | grep -Eq "$SAIKIT_SENTINEL_RE"; then
     emit_allow
   fi
   ```
   `PostToolUse` (`:702`) y `Stop` (`:830`) solo comprueban que el **archivo**
   exista; nunca re-validan el sentinel. La rama no-sentinel de arriba `emit_allow`
   **sin tocar el estado**: un turno `-saikit` abandonado deja `harness-state.env`
   en disco y sobrevive a cualquier cantidad de prompts posteriores sin sentinel.

3. **El presupuesto agotado no limpia.** `emit_budget_exhausted` (`:807-827`) solo
   emite JSON y `exit 0`; nunca borra nada. `stop_gate` lo invoca en `:963-964` sin
   `rm`. El test `caso_g5_presupuesto_agotado` no afirma que el estado se borre →
   cláusula 4 hoy incumplida **y** no probada.

**Reproducción previa declarada.** La revisión cruzada de la Task 2.4 ya había
pisado este defecto con el staging (`00-project-spec.md:794-803`): la medición
*arma* el turno y pisaba `harness-state.env` preexistente — **A4 reproducido a
mano** por la herramienta que venía a ayudar. El arreglo de esa vez fue apartar el
estado entero antes de medir; este task cierra la raíz para los turnos reales.

## El arreglo

La DoD (`Plans.md:64`) tiene cuatro cláusulas, que quedan como **cuatro tests
distintos**:

1. **Dos sesiones del mismo repo no comparten estado** → llavear por `session_id`.
2. **Prompt sin sentinel desarma y el Stop siguiente no bloquea** → en la rama
   no-sentinel de `start_harness`, borrar el estado si existe.
3. **Corrección al vuelo NO desarma** → satisfecho por el camino de armado vigente
   (sentinel presente → `write_state`); se agrega test que lo fija.
4. **Presupuesto agotado limpia el estado** → borrar antes de
   `emit_budget_exhausted`.

### Decisión de diseño (la que pide la cláusula 3)

El término "corrección al vuelo" aparece **solo** en `Plans.md:64`; no está
definido en el spec ni en el hook. La DoD contrasta "prompt sin sentinel desarma"
(cláusula 2) con "corrección al vuelo NO desarma" (cláusula 3), y ambos llegan
como `UserPromptSubmit`. Decisión confirmada con Gon:

> **La corrección al vuelo es un prompt que todavía trae `-saikit`** (re-arma, no
> desarma). Un prompt **sin** `-saikit` desarma borrando el estado. Re-armar
> resetea `cycle` a 0 (comportamiento actual, `:589`).

Es consistente con la Core Rule 3 ("el sentinel `-saikit` es la ÚNICA condición de
armado") y con que las cuatro cláusulas sean observables por separado. No se
persigue la variante "preservar el presupuesto al re-armar" (era la opción 3,
descartada): re-declarar `-saikit` reinicia el contador.

### Patrón de referencia

La variante `.codex` del hook ya resuelve el keying por sesión vía
`resolve_state_paths` (comentado en `:322-326`):
> "la variante .codex reescribe STATE_PATH por sesion via resolve_state_paths,
> ANTES de llegar aqui) -- sin esto, dos sesiones de Codex concurrentes en el mismo
> proyecto compartirian un solo contador y se contaminarian entre si."

Y deja asentada una lección cargada (`:328-339`): `RN_PENDING_PATH` debe quedar
**por proyecto** — llavearlo por sesión perdía el aviso en silencio (fallo "codex
NEW (a)"). Este plan la respeta.

---

# Correcciones de la revisión (2026-08-11)

> Revisión de Claude contra el código vivo + **revisión cruzada con kimi**
> (`quality-kit/cross-review.ps1 -Con kimi -Alcance staged`, 1 ronda, exit 0,
> kimi 0.34.0). Las CORRECCIÓN 1 y 2 las encontraron **las dos revisiones por
> separado**; la 8 y la 9 son de kimi; el resto son de la revisión de Claude.
> Todo lo verificado se cita con su línea.
>
> La CORRECCIÓN 3 abrió una decisión de diseño; **resuelta con Gon el 2026-08-11:
> opción A**. Ya no queda nada pendiente: todas las correcciones son ejecutables
> como están escritas.

## CORRECCIÓN 1 — E1 no puede ir en las líneas 36-43 (BLOQUEANTE)

El bloque de E1 llama `json_string_field session_id`, y esa función se define en
`hooks/summonaikit-harness.sh:70-73` — **después** del bloque que E1 reemplaza.
bash no tiene hoisting: se ejecuta de arriba hacia abajo, y en la línea ~40 la
función todavía no existe. Implementarlo literal da
`json_string_field: command not found` en stderr en **cada** evento del hook,
`SESSION_ID` vacío y fallback a `sin-session` para todas las sesiones — el mismo
slot compartido de hoy. **El arreglo quedaría inerte y A4 seguiría abierto**,
disfrazado de cerrado.

Dónde va el bloque: **después de `json_number_field` (`:78`)** y antes de
`read_state_value` (`:300`). El intervalo está verificado como seguro: `INPUT` ya
se leyó en `:22`, y entre `:43` y `:78` no hay un solo consumidor de
`STATE_DIR`/`STATE_PATH`/`LOG_PATH` — las líneas 45-68 son únicamente
`TEST_RUNNER_RE` y su wrapper. Los primeros consumidores reales son
`read_state_value` (`:300`) y `RN_ORDER_PATH`/`RN_PENDING_PATH` (`:340-341`).

`PROJECT_ROOT` (`:30-34`) sí tiene que quedar arriba, donde está: el bloque
movido lo necesita ya resuelto.

## CORRECCIÓN 2 — `session_id` no se lee con `json_string_field`

El plan dice: *"`json_string_field` (`:70-73`, sed top-level) ya sirve"*. **No es
top-level.** `:72` es el lector *greedy* — `s/.*"campo"...` sobre el payload
crudo aplanado — o sea exactamente el lector cuya codicia ES el defecto A1 que
cerró la Task 3.1: con más de una ocurrencia de la clave, gana la **última**. El
lector endurecido es `json_tool_input_string` (`:107`) y acá no aplica, porque
`session_id` es de primer nivel y ese escáner sólo lee dentro de `tool_input`.

Riesgo concreto: si `session_id` aparece como clave JSON **real** en otro lugar
del payload (un objeto estructurado de `tool_response`, o una entrada de
`background_tasks` / `session_crons` — los dos viajan en el payload de Stop), el
estado se llavearía a mitad de turno con un valor que el turno no escribió, y el
turno perdería su propio estado. Es la forma exacta del vector que A1 **sí**
reprodujo. El vector de *contenido de archivo* NO reproduce (medido en la 3.1:
las comillas llegan escapadas), así que esto no es "seguro que pasa" — es **"no
está medido"**, que es justamente la postura que la Task 3.7 dejó escrita como
lección.

Dos salidas; hay que elegir una y declararla:

1. **(recomendada)** Lectura acotada a primer nivel. El idiom ya existe: el
   escáner awk de la 3.1 ya lleva la profundidad de llaves, así que
   generalizarlo a un `json_top_level_string` (clave a `depth == 1`) es un cambio
   chico y es la misma decisión que este repo ya tomó para esta clase de lectura.
   Entra un caso más: un evento que trae otro `session_id` fuera del primer nivel
   **no** mueve el estado.
2. Medir `session_id` sobre los 308 payloads de la captura (igual que la 3.1
   midió `subagent_type`) y, si aparece una sola vez, declarar la premisa con la
   medición en vez de con una suposición.

## CORRECCIÓN 3 — la cláusula 3 no tiene comportamiento observable (resuelta: opción A)

El plan resuelve la cláusula 3 con "sin cambio de código, sólo se agrega el test
que lo fija". El problema es que **no hay test que lo pueda fijar**, y por lo
tanto tampoco mutación que lo pueda atrapar.

El camino de armado hace, en este orden:

```sh
:586  rm -f "$RN_ORDER_PATH"
:589  write_state "$task_hash" "0" "0" "0" ""
:590  printf 'prompt task started: %s\n' "$task_hash" > "$LOG_PATH"
```

Y el desarme de E2 borra `STATE_PATH`, `LOG_PATH` y `RN_ORDER_PATH`. O sea: el
armado **reescribe o borra exactamente los tres archivos que el desarme borra**.
Una corrección al vuelo (`desarmar y volver a armar`) y un re-armado puro
(`no desarmar`) terminan en un estado byte a byte idéntico. `RN_PENDING_PATH` no
rompe el empate: E2 no lo toca, y el armado lo consume igual por
`rn_take_pending` (`:587`).

Consecuencias, las dos verificadas:

- `caso_g1_correccion_al_vuelo_no_desarma`, tal como el plan lo define
  (`lab_hay_estado` cierto tras un prompt con `-saikit`), da **verde con el hook
  sano y verde con un hook que desarma igual**. No discrimina nada.
- `mut_desarmar_ignora_sentinel` no lo puede atrapar nadie. Si se implementa
  poniendo el `rm` incondicional antes del `if`, es una mutación **inerte** (el
  armado rehace todo) y la batería falla con
  `ningun caso detecto que [...]` (`tests/test_gate_mutations.sh:177`). Si se
  implementa invirtiendo la condición del sentinel, eso no es "desarmar": es "no
  armar nunca", y pone rojo a `caso_g1_arma_con_sentinel`, que está **antes** en
  `CASOS_G1` — el `break` de `:169` le da el crédito a ése y la cláusula 3 se
  queda otra vez sin mutación propia.

Es el mismo trámite que la 3.3 vivió con `mut_runner_sin_frontera`: una mutación
que cambia el archivo sin cambiar el comportamiento.

Esto no era un error de redacción sino una decisión de diseño. **Tomada con Gon
el 2026-08-11: opción A.**

> **Opción A (la elegida).** La cláusula 3 se declara **satisfecha de forma
> vacua**, con esta evidencia: `:586`, `:589` y `:590` reescriben o borran
> exactamente los tres archivos que E2 borra, así que "no desarmar" y "desarmar y
> volver a armar" son el mismo estado. Se conserva
> `caso_g1_correccion_al_vuelo_no_desarma` como **guardia de regresión** — el día
> que alguien vuelva parcial el camino de armado, el caso empieza a discriminar —
> pero se declara por escrito que **hoy ninguna mutación lo puede atrapar**, y
> `mut_desarmar_ignora_sentinel` **se saca del catálogo**: dejarlo hace fallar la
> batería con `ningun caso detecto que [...]`, que es un rojo correcto sobre una
> mutación inerte, no sobre una laguna de la suite.

Consecuencia que hay que declarar en el cierre de `Plans.md`, no esconder: **una
de las cuatro cláusulas de la DoD se cierra sin mutación propia**, y la razón es
que su contenido es vacío bajo el diseño confirmado ("re-armar resetea `cycle` a
0"), no que falte un test.

Opción B, descartada y registrada por si vuelve: hacer que la corrección al vuelo
**preserve `cycle`** (la "opción 3" del plan original). Volvería observable la
cláusula (`cycle=1` sobrevive al re-armado) y le daría su mutación, a costa de
cambiar la semántica ya decidida — una corrección al vuelo heredaría el
presupuesto gastado en vez de empezar limpia.

## CORRECCIÓN 4 — `mut_session_sin_llave` le roba el crédito a su propio caso

Verificado sobre `tests/test_gate_mutations.sh:163-169`: la batería corre cada
mutación **sólo contra los casos de su gate** y **corta en el primer rojo**, y
sólo ése queda declarado como el que la atrapa. Eso vuelve el orden de
`CASOS_G1` parte del diseño, no cosmética — la misma lección que la 3.1 dejó
escrita para `CASOS_G3`.

Con `mut_session_sin_llave` (revertir `STATE_DIR` a `PROJECT_DIR`) pasa esto:
`lab_init` descubre `LAB_ESTADO_PATH` **una sola vez, contra el hook vivo**
(`hook_lab.sh:74-75`), y `lab_hook_swap` lo conserva a propósito porque su
comentario asume que la ruta "depende solo de la ruta del proyecto". El mutante
escribe el estado un nivel más arriba, así que `lab_hay_estado` (que mira el
`LAB_ESTADO_PATH` cacheado) da falso y **`caso_g1_arma_con_sentinel` se pone rojo
primero** — está segundo en `CASOS_G1`, mucho antes que el caso nuevo de la
cláusula 1. Resultado: la mutación queda acreditada al caso equivocado y
`caso_g1_dos_sesiones_no_comparten_estado` se queda sin mutación propia.

Arreglo (el mismo que pide la CORRECCIÓN 8): que el lab **descubra** la ruta de
estado del hook que tiene puesto, en vez de cachear la del hook vivo —
`lab_hook_swap` vuelve a correr el probe de descubrimiento después de cada swap.
Con eso, bajo el mutante la ruta plana se descubre bien, `caso_g1_arma_con_sentinel`
sigue verde, y el primer rojo pasa a ser el caso de la cláusula 1, que es a quien
le corresponde.

Detalle que hay que implementar con cuidado: si el probe **no** encuentra estado
(un mutante que rompe el armado del todo, que los hay), `lab_hook_swap` no puede
abortar como hace `lab_init` — tiene que conservar la ruta anterior y dejar que
el caso se ponga rojo, que es justamente lo que la batería viene a comprobar.

Además, las cuatro mutaciones hay que **escribirlas como comandos reales**, no
como descripciones en prosa: el plan de la 3.3 las escribió así y por eso salió a
la luz la corrupción de backslashes de MSYS2. Y hay que anclar cada `sed` a su
sitio: tras E2 y E4 va a haber **tres** líneas `rm -f "$STATE_PATH" ...` casi
idénticas en el hook (E2, E4 y el cierre limpio de `:959`), así que cada mutación
se ancla al comentario único que la precede. Que E2 y E4 caigan en gates
distintos (G1 y G5) las protege de robarse el crédito entre ellas, pero no
protege del `sed` que se lleva puesta la de `:959` por accidente.

Criterio de aceptación de esta corrección: **cada mutación tiene que quedar
acreditada a SU caso** en la declaración que emite la corrida, no a uno anterior.

## CORRECCIÓN 5 — dos comentarios quedan mintiendo, y hay que corregirlos en el mismo cambio

- `hooks/summonaikit-harness.sh:328-339` dice, textual, que `RN_PENDING_PATH` va
  por proyecto *"(STATE_DIR, sin sufijo de sesion)"*. Después de E1 `STATE_DIR`
  **es** por sesión: el plan mueve la ruta a `PROJECT_DIR` pero deja el
  comentario contradiciendo al código. En este repo los comentarios son donde
  vive el razonamiento declarado; dejarlo viejo es exactamente lo que una
  revisión cruzada marca.
- `tests/lib/hook_lab.sh`, comentario de `lab_hook_swap`: *"la ruta de estado ya
  descubierta, que depende solo de la ruta del proyecto"*. Deja de ser cierto, y
  además es la premisa que la CORRECCIÓN 4 rompe.

## CORRECCIÓN 6 — el keying introduce basura sin recolección, y eso hay que declararlo

Hoy hay **un** directorio de estado por proyecto. Después del cambio hay **uno
por sesión, para siempre**: ningún camino hace `rmdir`, y el cierre limpio
(`:959`) borra `STATE_PATH` y `LOG_PATH` pero no el directorio. Una sesión
abandonada deja su `harness-state.env` en un directorio con nombre de `cksum`.

Ojo con la ironía: A4 se abrió porque un estado colgado **obligó a un borrado
manual**, y este arreglo hace ese borrado manual *más difícil* (antes había una
ruta por proyecto; ahora hay N con nombres ilegibles). Mínimo: declararlo como
límite conocido. Mejor: un barrido barato al armar (borrar directorios de sesión
con más de N días), o un nombre de directorio legible — ver CORRECCIÓN 7.

## CORRECCIÓN 7 — por qué se hashea `session_id`, y qué cuesta `cksum`

El plan hashea `session_id` sin decir por qué. La razón es buena y hay que
declararla: **el valor viene del payload**, y meterlo crudo en una ruta es una
primitiva de escritura fuera de lugar — la misma familia que A6 (Task 3.6). El
hash lo neutraliza.

Del otro lado, `cksum` es CRC32: dos sesiones que colisionen comparten estado, o
sea **A4 otra vez**, que es el defecto que esta task cierra. La probabilidad es
baja pero el modo de falla es exactamente el prohibido.

Alternativa que resuelve las dos cosas y además la CORRECCIÓN 6: **sanear en vez
de hashear** — reemplazar `[^A-Za-z0-9_-]` por `_` y truncar. Un `session_id`
real es un UUID, así que el directorio queda legible (descubrible a mano), sin
colisiones y sin traversal. Cualquiera de las dos sirve; lo que no sirve es no
declarar cuál y por qué.

## CORRECCIÓN 8 — el helper del lab descubre, no recalcula (kimi)

`lab_estado_path_para_sesion` queda en el plan con dos implementaciones
alternativas sin decidir ("o, equivalentemente, correr un probe y hacer `find`").
Hay que fijar **probe + `find`**, y descartar por escrito la otra: si el helper
recalcula el `cksum` como lo hace el hook, el test deja de ser independiente de
la implementación y un mismo error de los dos lados da verde. Es además la vía
que ya usa `lab_init` (`:74-75`) y la que la CORRECCIÓN 4 necesita.

Alcance: `lab_sembrar`, `lab_hay_estado` y `lab_estado` (`hook_lab.sh`) leen hoy
el `LAB_ESTADO_PATH` cacheado; con dos sesiones en juego tienen que poder operar
sobre la sesión que el caso pida.

## CORRECCIÓN 9 — dos bordes que faltan declarar

- **El desarme incidental cuesta el presupuesto de ciclos** (kimi). Cualquier
  prompt sin sentinel de la misma sesión borra el estado, incluida una
  interacción incidental a mitad de ciclo (una aclaración, un "dale"): los ciclos
  ya gastados se pierden. Es lo que pide la cláusula 2 y está confirmado con Gon,
  pero no está en "Edge cases declarados" — y sin declararlo vuelve como "bug"
  dentro de tres tasks.
- **cursor arma en `session` y se desarma en el `prompt` siguiente.** El guard
  `PHASE=prompt` de E2 protege el armado de `caso_g6_armado_por_target`, correcto.
  Pero en cursor el turno se arma en la fase `session` y el prompt siguiente del
  usuario naturalmente no trae `-saikit`, así que lo desarma de inmediato. Por la
  DoD es correcto; para cursor deja el armado por sesión casi inservible.
  Declararlo, no dejar que se descubra.

## CORRECCIÓN 10 — el caso de la cláusula 1 tiene dos mitades

`caso_g1_dos_sesiones_no_comparten_estado`, como está escrito, sólo afirma que la
sesión B no ve el estado. Falta la otra mitad: **el estado de A sobrevive al turno
de B**. Sin ella, un hook que borre todo pasa el caso. Es la misma forma de "las
dos mitades" que la 3.2 usó para A2+A8.

---

## Cambios

### 1. `hooks/summonaikit-harness.sh`

**E1 — State path por sesión (cláusula 1).** ⚠️ **Corregido por la CORRECCIÓN 1 y
la CORRECCIÓN 2: el bloque NO va en las líneas 36-43 (ahí `json_string_field`
todavía no existe) sino después de `:78`, y `json_string_field` NO es el lector
correcto para `session_id`.** Introducir `PROJECT_DIR` (lo que hoy es
`STATE_DIR`, per-project) y anidar `STATE_DIR` por sesión debajo:

```sh
# Keep gate state isolated per project AND per session. A single user-level hook
# must not share one state file across repos or across concurrent sessions of the
# same repo (that would cross-contaminate the implement -> verify -> review
# cycle). session_id travels in every payload (Task 1.4 capture) -- key by it.
# Closes A4 (Task 3.4). Patron calcado de la variante .codex (resolve_state_paths).
STATE_ROOT="$HOOK_DIR/state"
PROJECT_KEY="$(printf '%s' "$PROJECT_ROOT" | cksum | cut -d ' ' -f 1)"
PROJECT_DIR="$STATE_ROOT/$PROJECT_KEY"
SESSION_ID="$(json_string_field session_id)"
if [ -z "$SESSION_ID" ]; then
  # session_id ausente -> slot nombrado y descubrible, no un slot unico que
  # colapsaria todo y reintroduciria A4. Edge case: session_id SIEMPRE viene en
  # payloads reales (medido Task 1.4).
  SESSION_ID="sin-session"
fi
SESSION_KEY="$(printf '%s' "$SESSION_ID" | cksum | cut -d ' ' -f 1)"
STATE_DIR="$PROJECT_DIR/$SESSION_KEY"
STATE_PATH="$STATE_DIR/harness-state.env"
LOG_PATH="$STATE_DIR/harness-evidence.log"
```

**Crítico — `RN_PENDING_PATH` (`:341`) pasa de `$STATE_DIR` a `$PROJECT_DIR`:**
```sh
RN_ORDER_PATH="${STATE_PATH%.env}-review-notice.env"   # session-scoped (deriva de STATE_PATH), sin cambio
RN_PENDING_PATH="$PROJECT_DIR/review-notice-pending.log"  # era $STATE_DIR; PER-PROJECT a proposito (:328-339)
```
Como `STATE_DIR` pasa a ser por sesión, dejar `RN_PENDING_PATH` en `$STATE_DIR`
reaparece el fallo "codex NEW (a)". Moverlo a `PROJECT_DIR` **preserva** el
comportamiento per-project que ya tenía (antes `STATE_DIR` era per-project). Los
`mkdir -p "$STATE_DIR"` existentes crean `PROJECT_DIR` como padre, así que la
escritura de `RN_PENDING_PATH` sigue funcionando.

**E2 — Desarmar en prompt sin sentinel (cláusula 2).** En `start_harness`,
reemplazo de las líneas 574-576. Acotado a `PHASE=prompt` (la DoD habla de
"prompt"; un `SessionStart` sin sentinel no debe limpiar estado — cursor arma en
`session` con `-saikit` en el texto, ver `caso_g6_armado_por_target`):

```sh
if ! printf '%s' "$prompt_text" | grep -Eq "$SAIKIT_SENTINEL_RE"; then
  # Sin sentinel: si habia estado armado para ESTA sesion, desarmar (borrar).
  # Antes no se tocaba y un turno -saikit abandonado segnia cobrando recibo a
  # turnos que no lo pidieron (A4). La correccion al vuelo (prompt CON -saikit)
  # no pasa por aca: re-arma mas abajo y conserva el estado.
  if [ "$PHASE" = "prompt" ] && [ -f "$STATE_PATH" ]; then
    rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true
  fi
  emit_allow
fi
```

**E3 — Corrección al vuelo (cláusula 3).** Sin cambio de código, pero **no** por
la razón que decía el plan. Ver **CORRECCIÓN 3**: el armado reescribe exactamente
los archivos que el desarme borra, así que re-armar y desarmar-y-armar son
indistinguibles y la cláusula no tiene contenido observable. Decisión tomada
(opción A): se declara vacua, el caso queda como guardia de regresión y su
mutación sale del catálogo.

**E4 — Presupuesto agotado limpia el estado (cláusula 4).** En `stop_gate`,
reemplazo de las líneas 963-965:

```sh
if [ "$cycle" -ge "$MAX_CYCLES" ] 2>/dev/null; then
  # Presupuesto agotado limpia el estado de ESTA sesion. RN_PENDING_PATH queda
  # (per-project, ver comentario REVIEW-NOTICE). Sin esto, cycle=MAX sobrevivia.
  rm -f "$STATE_PATH" "$LOG_PATH" "$RN_ORDER_PATH" 2>/dev/null || true
  emit_budget_exhausted "$missing"
fi
```

E2 y E4 no tocan `RN_PENDING_PATH`, igual que el cierre limpio (`:944` borra
`RN_ORDER_PATH`, `:959` borra `STATE_PATH`/`LOG_PATH`): el aviso pendiente
sobrevive para el próximo armado.

### 2. `tests/lib/hook_lab.sh` — parametrizar `session_id`

Hoy los 9 constructores (`:162-218`) hardcodean
`"c1a70000-1111-4222-8333-444455556666"`. Reemplazar por
`"${LAB_SESSION_ID:-c1a70000-1111-4222-8333-444455556666}"` para poder correr dos
sesiones distintas del mismo repo.

Agregar un helper `lab_estado_path_para_sesion SESS` para que `lab_sembrar` /
`lab_hay_estado` / `lab_estado` operen sobre la sesión pedida. ⚠️ **La CORRECCIÓN
8 fija la implementación: probe + `find`, NO recalcular el `cksum` del hook.** Y
la **CORRECCIÓN 4** agrega un requisito que este plan no tenía: `lab_hook_swap`
tiene que **re-descubrir** la ruta después de cada swap (hoy la cachea desde
`lab_init`), o `mut_session_sin_llave` pone rojo al caso equivocado.

### 3. `tests/lib/gate_cases.sh` — casos nuevos

En `CASOS_G1` (sentinel/arming), al final para no robarle la declaración a los
casos existentes:

- **`caso_g1_dos_sesiones_no_comparten_estado`** (cláusula 1): armar con sesión A
  → cambiar a sesión B → B no ve estado armado; Stop de B → allow sin bloqueo.
  ⚠️ **CORRECCIÓN 10: falta la otra mitad** — el estado de A tiene que
  **sobrevivir** al turno de B. Sin esa aserción, un hook que borre todo pasa.
- **`caso_g1_prompt_sin_sentinel_desarma`** (cláusula 2): sembrar estado armado →
  prompt sin sentinel (misma sesión) → `! lab_hay_estado`; Stop siguiente → rc 0,
  allow, no bloquea.
- **`caso_g1_correccion_al_vuelo_no_desarma`** (cláusula 3): sembrar estado
  (cycle=1) → prompt **con** `-saikit` (misma sesión) → `lab_hay_estado` cierto
  (re-armado; no desarma). ⚠️ **CORRECCIÓN 3: así escrito da verde con el hook
  sano Y con uno que desarma igual — no discrimina.** Se conserva igual, como
  **guardia de regresión**, y se declara sin mutación que lo ate (opción A).

En `CASOS_G5` (presupuesto):

- **`caso_g5_agotado_limpia_estado`** (cláusula 4): sembrar `cycle=MAX` → Stop
  con `missing` → afirma budget exhausted emitido **y** `! lab_hay_estado`.
  (Alternativa: extender `caso_g5_presupuesto_agotado` con la aserción
  `lab_hay_estado`; se elige sibling para no mover la declaración del existente.)

### 4. `tests/test_gate_mutations.sh` — 3 mutaciones nuevas (eran 4)

Catálogo: **N actuales + 4 nuevas = N+4, N+4 atrapadas** (el número se declara con
lo que emita la corrida, no con esta estimación).

```
G1|session_sin_llave|revertir STATE_DIR a PROJECT_DIR (sin sufijo de sesion)
G1|desarmar_quita_borrado|quitar el rm de la rama no-sentinel
G5|presupuesto_no_limpia|quitar el rm del camino de presupuesto agotado
```

Fuera del catálogo, y por qué (queda escrito para que nadie lo re-proponga):
`G1|desarmar_ignora_sentinel` — no existe forma de escribirla que discrimine, ver
CORRECCIÓN 3.

⚠️ **Corregido por la CORRECCIÓN 4 y la CORRECCIÓN 3:**

- `desarmar_ignora_sentinel` **sale del catálogo** (opción A de la CORRECCIÓN 3,
  decidida): hoy no la puede atrapar nadie y dejarla hace fallar la batería con
  `ningun caso detecto que [...]`. Quedan 3 mutaciones nuevas, no 4.
- `session_sin_llave` sólo discrimina si antes se arregla el cacheo de
  `LAB_ESTADO_PATH` (CORRECCIÓN 4); sin eso acredita a `caso_g1_arma_con_sentinel`.
- Las mutaciones se escriben como **comandos reales**, no en prosa, y cada `sed`
  se ancla al comentario único de su sitio: tras E2 y E4 hay tres líneas
  `rm -f "$STATE_PATH" …` casi idénticas en el hook (E2, E4 y el cierre limpio de
  `:959`).

Criterio de aceptación: cada mutación tiene que quedar acreditada a **su** caso
en la declaración que emite la corrida (E1↔c.1, E2↔c.2, E4↔c.4), no a uno
anterior de la misma lista.

### 5. `tests/golden/baseline.txt` — re-grabar

El keying cambia la profundidad del path de estado para todo escenario armado, y
el desarme/limpieza puede mover outcomes donde haya secuencia "prompt-sin-sentinel
post-armado" o presupuestos (escenario 08). Se re-graba y **se declara el diff**
con lo que emita la corrida, mismo trámite que la 3.3 con el escenario 13.

## Verificación (antes de dar por cerrada)

1. `pre-commit run --all-files` (sin `--no-verify`, regla de hierro #1).
2. `bash tests/run.sh` → 0 FAIL, 0 UNKNOWN.
3. Cross-review **sobre staged antes de commit** (lección de la 3.2), tope 1
   ronda (`C:\Users\ehven\quality-kit\cross-review.ps1`). **Va con `-Con codex`**:
   la ronda de kimi ya se gastó sobre este plan (ver el bloque de Correcciones),
   así que la del código va a otro revisor para no perder la independencia.
4. Install del hook (`tools/install-hook.sh`) — es lo que lleva el arreglo al
   archivo que gatea cada turno.
5. Declaración del diff de la línea base en el cierre.

## No entra en esta tarea (límites declarados)

- **Aislamiento cross-host** = Task 5.3 ("A4 en versión cross-host"). La 3.4 es
  per-session **dentro de un host**.
- La variante `.codex` y su `resolve_state_paths` son **referencia**, no se portea
  textual: este hook recibe su propio keying inline. La variante `.codex` es otro
  archivo, re-aplicado por `saikit-gate-heal.ps1`.
- `RN_PENDING_PATH` se queda por **proyecto** a propósito (lección `:328-339`).
- Re-armar resetea `cycle` a 0 — aceptado (Gon); **no** se cambia a "preservar
  presupuesto" (opción 3, descartada).
- A5 (secrets en `harness-evidence.log`) y A6 (`transcript_path` sin acotar) son
  tasks separadas (3.5, 3.6).

## Orden (TDD)

1. Los 4 casos nuevos + las **3** mutaciones, en **rojo** contra el hook vivo sin
   tocar. Confirmar que cada uno discrimina — y que cada mutación queda acreditada
   a SU caso (CORRECCIÓN 4). El caso de la cláusula 3 es la excepción declarada:
   no se pone rojo con ninguna mutación, y eso está justificado en la CORRECCIÓN 3.
2. Arreglo E1–E4 en el hook.
3. `bash tests/run.sh` → verde.
4. Re-grabar la línea base y declarar el diff.
5. Cross-review (codex, staged, 1 ronda).
6. Commit.
7. `tools/install-hook.sh`.
8. Cierre en `Plans.md` con la DoD verificada punto por punto
   (`cc:TODO` → `cc:完了 [sha]`).

## Edge cases declarados

- `session_id` ausente → slot nombrado `sin-session` (descubrible; no un slot
  único que colapsaría y reintroduciría A4). En payloads reales siempre viene.
- Desarme acotado a `PHASE=prompt` para no romper el armado de cursor en `session`
  (`caso_g6_armado_por_target`: cursor arma con `-saikit` en el texto de sesión).
- ⚠️ **Faltan, y las agregan las CORRECCIONES 6, 7 y 9:** el keying deja un
  directorio por sesión sin recolección (y vuelve el borrado manual *más* difícil
  que antes de A4); el hash de `session_id` existe porque el valor viene del
  payload (traversal, familia de A6) y `cksum` es CRC32, o sea colisionable; un
  prompt incidental sin sentinel a mitad de ciclo pierde el presupuesto ya
  gastado; y en cursor el armado por `session` se desarma en el prompt siguiente.
