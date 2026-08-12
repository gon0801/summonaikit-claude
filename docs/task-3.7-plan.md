# Task 3.7 — A9+A10: el gate de ceremonia es inerte (plan para revisión)

`[Guardrail]` `[lane:gate]` `[tdd:required]`. Cierra **A9 + A10**, que van
juntos (se enmascaran). **DoD íntegra en `Plans.md:67`.**

`spec_path: docs/spec/00-project-spec.md` — no hay `spec.md` raíz; éste es el
contrato canónico del proyecto y se actualiza al cerrar.

> **Primer paso obligatorio de la DoD: re-medir.** Es lo primero que se hizo, y
> **cambió la forma de la tarea**. Este plan es la re-redacción con lo medido.

> **Revisión 2026-08-11 (segunda pasada).** El plan se verificó contra el código
> vivo y once cosas no cerraban. Están abajo como CORRECCIÓN 1..11 y ya vienen
> aplicadas al cuerpo. Tres eran bloqueantes: una mutación que no muta
> (CORRECCIÓN 4), un caso que pasa con y sin el arreglo (CORRECCIÓN 5) y una
> columna de la tabla de medición que era falsa (CORRECCIÓN 1).

> **Revisión 2026-08-12 (tercera pasada).** Se verificaron además los runners,
> fixtures, baseline y cierre real. Las CORRECCIONES 12..17 de abajo ya están
> aplicadas al cuerpo: eliminan una predicción imposible del escenario 16,
> cierran el drift documental, fijan la semántica multi-settings del matcher,
> respetan el loop de tests del repo y dejan explícito el segundo commit de
> cierre.

---

## La re-medición (2026-08-11, captura real en `C:\dev\saikit-captura`)

Se capturaron los payloads crudos de un turno real con delegaciones a
implementer/verifier/reviewer (12 eventos `PostToolUse`, vía
`tools/capture-payloads.sh`), y el entorno del hook (`bash -c 'export …'` form).
**La premisa original de A9 —“el rol viaja en `agent_type`”— se CONFIRMA. La
conclusión de la Task 2.4 (“el rol viaja en `subagent_type`”) era una
atribución errónea**, y se corrige acá.

### A9 confirmado, con la huella medida

Ojo con lo que la captura mide: `capture-payloads.sh` se registra con matcher
`"*"`, así que ve **todos** los eventos. El gate se registra con matcher
`Bash|Edit|Write|apply_patch|Task` (verificado en `~/.claude/settings.json:174`),
así que ve **menos**. Son dos poblaciones distintas y hay que separarlas:

| grupo | cant. | `tool_name` | dónde lleva el rol | ¿llega al gate? |
|---|---|---|---|---|
| delegación del padre | 3 | **`Agent`** ×3 | `tool_input.subagent_type` (sin `agent_type`) | **no** — el matcher dice `Task`, la herramienta se llama `Agent` |
| internos, herramienta cubierta | 5 | `Bash` ×4, `Write` ×1 | **`agent_type` top-level** | **sí** |
| internos, herramienta NO cubierta | 4 | `Read` ×2, `StructuredOutput` ×2 | **`agent_type` top-level** | **no** — no están en el matcher |

Recuento por rol de los 9 internos (`capturas/017-028`), que es lo que decide si
A9 alcanza: implementer = `StructuredOutput`, **`Write`**, `Read`,
`StructuredOutput` — **un solo evento cubierto**; verifier = **`Bash`**, `Read`,
**`Bash`**; reviewer = **`Bash`**, **`Bash`**. Los tres roles tienen al menos un
evento cubierto, así que A9 cierra **este** turno. Pero el implementer llegó por
uno solo de sus cuatro eventos, y `StructuredOutput`/`Read` son justamente cómo
un subagente lee y devuelve su resultado: el margen es fino, y ése es el hueco de
la CORRECCIÓN 2, medido.

- Los eventos que el gate **sí recibe** llevan el rol en `agent_type` de primer
  nivel. El hook lee `subagent_type` (`:831`, `json_tool_input_string`) ⇒ no lo
  ve ⇒ `agents_seen` queda vacío. **Eso es A9.**
- Los eventos que llevan `subagent_type` (los `Agent`) **no llegan al gate**.
- **Y hay un tercer grupo que el plan de la primera pasada no separó**: los
  internos con herramienta fuera del matcher. Esos tampoco llegan, y son la
  razón por la que la cláusula del matcher **no** se dropa (CORRECCIÓN 2).

**Por qué 2.4 quedó como quedó, sin especular.** El cierre de 2.4 leyó el
**transcript** (.jsonl, que registra las llamadas `Agent` con `subagent_type`) y
concluyó que el rol viajaba por ahí. El hook no lee el transcript para esto: lee
los **payloads de PostToolUse**, y en los payloads que le llegan el rol va en
`agent_type`. Qué pobló exactamente `agents_seen` en 2.4 **no se pudo
reconstruir** y este plan no lo afirma. **No hace falta reconstruirlo**, y esa es
la razón real por la que la discrepancia no bloquea: el arreglo de A9 es un
**fallback**, no un reemplazo. Si en alguna configuración `subagent_type` sí
llega, sigue ganando y no cambia nada. La lectura de `agent_type` solo agrega un
camino donde hoy no hay ninguno. Riesgo de regresión estructuralmente nulo, y
pinneado por caso (`caso_g3_agent_type_generico_no_cuenta`, CORRECCIÓN 6).

### A10 confirmado, con la CAUSA aislada (ya no es `unknown`)

- El host **no propaga el prefijo `VAR=val`** del comando registrado al ambiente
  del hook. Medición directa: registrando `SUMMONAIKIT_HOOK_TARGET=claude bash
  capture-payloads.sh`, el `SUMMONAIKIT_HOOK_TARGET` **no apareció** en el env
  del hook.
- **`PHASE` sobrevive** porque el hook la deriva del payload cuando el env viene
  vacío (`hooks/summonaikit-harness.sh:1144-1152`, fallback a `hook_event_name`).
  Por eso el gate funciona: arma en prompt, marca en tool, cobra recibo en stop.
- **`TARGET` no sobrevive**: no hay fallback (`:23` `TARGET="$SUMMONAIKIT_HOOK_TARGET"`).
  Entonces `[ "$TARGET" = "claude" ]` (`:1061`) es siempre falso ⇒ **la rama de
  secuencia nunca corre en producción**.

**Fix confirmado por medición.** Poniendo el `export` **adentro** del `bash -c`
(`bash -c 'export SUMMONAIKIT_HOOK_TARGET=claude; …; bash "$h"'`), `TARGET` SÍ
llega. Pero ese cambio toca el comando del operador en `settings.json` (que
ningún tool del repo genera). En cambio, **Claude Code setea `CLAUDECODE=1`**
(medido en la misma captura), así que el hook puede detectar Claude sin depender
del comando. Esa es la vía que toma este plan: ningún cambio al comando del
operador, todo del lado del hook.

---

# Correcciones de la revisión

## CORRECCIÓN 1 — la columna “¿llega al gate?” era falsa para 4 de los 9

**Decía:** los 9 eventos internos (`Bash`/`Write`/`Read`/`StructuredOutput`)
“matchean el matcher” y llegan al gate.

**Es falso.** El matcher registrado del gate es `Bash|Edit|Write|apply_patch|Task`
(`~/.claude/settings.json:174`). `Read` y `StructuredOutput` no matchean ninguna
alternativa. Los 12 eventos se vieron porque la **captura** se registra con
matcher `"*"` (`tools/capture-payloads.sh`), no porque el gate los reciba.
Confundir la población de la captura con la del gate es lo que sostenía la
CORRECCIÓN 2 al revés.

**Cambia:** la tabla de arriba, partida en tres grupos.

## CORRECCIÓN 2 — la cláusula del matcher NO es moot; no se dropa

**Decía:** “el rol llega por los eventos internos (que matchean), así que exigir
`Agent` en el matcher ya no hace falta. **Se dropa esa cláusula**.”

**No se sostiene, por la CORRECCIÓN 1.** Solo llegan los internos cuya
herramienta está en el matcher. Un subagente que hace su trabajo con
`Read`/`Grep`/`Glob` y devuelve texto —un reviewer read-only es exactamente
eso— **no produce ni un evento que llegue al gate**, ni antes ni después del
arreglo de A9. Su rol nunca se registra. El canal `Agent` sí lo habría atrapado,
porque la delegación ocurre una vez por subagente pase lo que pase adentro.

O sea: A9 cierra el caso común (todo subagente que corra un comando o edite un
archivo), y deja un hueco real en el caso read-only. La DoD no pide cambiar el
registro — pide que **`tools/check-hook-registration.sh` reporte fuerte** si el
matcher no cubre la herramienta de subagentes. Eso es un reporte, no una edición
de `settings.json`: cae **adentro** del límite que este mismo plan declara.

**Cambia:** la cláusula se implementa (Cambio 2, más su caso en
`tests/test_hook_registration.sh`), y el hueco read-only se declara en Límites.

## CORRECCIÓN 3 — efecto colateral no declarado: la señal del review-notice

`$subagent` tiene un **segundo consumidor** que el plan no vio
(`hooks/summonaikit-harness.sh:834-839`):

```sh
rn_order_now="$(rn_bump_counter)"
if [ -n "$subagent" ] && [ "$(canonical_agent_role "$subagent")" = "reviewer" ]; then
  rn_mark_review "$rn_order_now"
fi
```

Llenar `$subagent` desde `agent_type` **también enciende esto**. Hoy `last_review`
solo se marcaba desde los eventos `Agent`, que en producción no llegan: la señal
de orden del review-notice está tan muerta como el gate de secuencia.

**Decisión: se acepta y se declara, no se contiene.** Marcar el último evento
interno del reviewer es *más* correcto que marcar la delegación — fecha cuándo la
revisión efectivamente corrió, no cuándo se pidió. Y el aviso solo dispara si
`last_code_edit > last_review`, que es justo lo que se quiere detectar.

**Cambia:** queda declarado acá y **se graba en el diff de la línea base**: en el
escenario 16, tras el paso 04, `last_review=` pasa a `last_review=3`. Tras el paso
05 no queda archivo: el cierre limpio borra el estado (CORRECCIÓN 12).

## CORRECCIÓN 4 — `mut_target_sin_claudecode` no muta: `[ false ]` es VERDADERO

**Decía:** `sed 's/\[ "$CLAUDECODE" = "1" ]/[ false ]/'`.

`[ false ]` es `test` con un único argumento no vacío ⇒ **verdadero**
(comprobado). La mutación no neutraliza el fallback: lo vuelve **incondicional**,
`TARGET="claude"` siempre. Con eso `caso_g3_target_por_claudecode_fallback`
seguiría **verde**, ningún otro caso G3 reacciona (todos pasan target explícito),
y la batería fallaría con *“ningún caso detectó [...]”*. La mutación pasa las tres
guardias del driver (existe, cambia el hook, `bash -n` OK) y aun así no prueba
nada — exactamente el modo de falla que la batería existe para evitar.

**Cambia a:** `sed 's/"$CLAUDECODE" = "1"/"$CLAUDECODE" = "0"/'`. No toca la
estructura de corchetes, no mete backslashes (la trampa de MSYS2 documentada en
`test_gate_mutations.sh:128-131`), y `CLAUDECODE=1` deja de matchear ⇒ `TARGET`
vuelve a quedar vacío ⇒ el caso nuevo se pone rojo.

## CORRECCIÓN 5 — el caso de A10 pasaba con y sin el arreglo

**Decía:** `lab_run stop auto "$(lab_payload_stop "$_TEXTO_LLANO")"` y luego
`_igual "exit code" "$LAB_RC" "2"`, con el comentario *“sin el arreglo, cerraría
limpio”*.

**Falso.** `_TEXTO_LLANO` no trae recibo, así que el Stop bloquea **igual** por
las etiquetas faltantes, con o sin el arreglo de A10. La afirmación del exit code
no discrimina nada; la única que discriminaba era el `_contiene`. Y el comentario
—que es la declaración de qué prueba el caso— decía algo que no es cierto.

**Cambia a `$_RECIBO_VINETAS`.** Con `lab_sembrar 123456 0 1 1 ""` (todo en orden
salvo `agents_seen`) y recibo completo: **sin** el arreglo el Stop cierra limpio
(exit 0, `TARGET` vacío ⇒ la rama de secuencia no corre); **con** el arreglo
bloquea reclamando los tres roles. Las dos afirmaciones discriminan.

## CORRECCIÓN 6 — el segundo caso nuevo era redundante y no podía acreditarse

**Decía:** agregar `caso_g3_rol_por_agent_type_en_evento_interno` (evento interno
con `agent_type=reviewer` ⇒ registra reviewer), *además* de invertir
`caso_g3_agent_type_no_cuenta` (evento interno con `agent_type=implementer` ⇒
registra implementer).

Son **la misma afirmación con otro string de rol**. Y como la batería de
mutaciones **corta en el primer caso rojo** y el invertido va antes en
`CASOS_G3`, el caso nuevo **nunca** puede quedar acreditado a
`mut_agent_type_no_se_lee`: es peso muerto en la declaración.

**Cambia por `caso_g3_agent_type_generico_no_cuenta`**, que cubre el riesgo que
el arreglo realmente introduce y que hoy no tiene caso: el canal nuevo
(`agent_type`) puede **inventar** un rol o **pisar** uno legítimo.
`caso_g3_agente_generico_no_cuenta` protege eso solo del lado de `subagent_type`.
Dos afirmaciones:

1. `agent_type=general-purpose` en un evento interno ⇒ `agents_seen` vacío
   (`canonical_agent_role` no mapea genéricos).
2. Un `Agent` con `tool_input.subagent_type=implementer` **y** `agent_type=reviewer`
   de primer nivel (la forma real de una delegación anidada: el `agent_type` es
   el del subagente padre) ⇒ gana **implementer**. El fallback es fallback.

## CORRECCIÓN 7 — la lista de referencias al nombre viejo estaba mal

**Decía:** “El nombre viejo se referencia en `CASOS_G3` y en el catálogo de
mutaciones; ambos se actualizan.”

`caso_g3_agent_type_no_cuenta` **no aparece** en el catálogo de mutaciones (el
catálogo es `gate|nombre|descripción`, sin nombres de caso; `mut_subagent_type_greedy`
es un `sed` sobre el hook y no menciona ningún caso). Las referencias reales son
cuatro:

- `tests/lib/gate_cases.sh:28` — el índice de casos del encabezado.
- `tests/lib/gate_cases.sh:405` — `CASOS_G3`.
- `tests/lib/gate_cases.sh:456` — la definición.
- **`Plans.md:67` — la DoD, que nombra el caso literalmente.**

La última importa: renombrar deja la DoD apuntando a un nombre inexistente. Se
declara el renombre en el cierre (no se reescribe el renglón; se anota que
`caso_g3_agent_type_no_cuenta` → `caso_g3_agent_type_cuenta`).

## CORRECCIÓN 8 — `tools/golden-harness.sh` también hereda `CLAUDECODE`

El plan detectó el problema de determinismo en `lab_run` pero no en el otro
runner. `tools/golden-harness.sh:257` arma su env igual —
`env -u SUMMONAIKIT_INTERNAL_GENERATION -u SUMMONAIKIT_HOOK_PHASE -u SUMMONAIKIT_HOOK_TARGET`
— y **tampoco unsetea `CLAUDECODE`**. El escenario 15 corre `phase=auto
target=auto` (`01.auto.auto.json`), así que tras el arreglo su `TARGET` dependería
de si la suite se corre adentro o afuera de Claude Code.

Hoy no cambiaría la salida (verificado: fuera de las ramas `cursor`, el único
consumidor de `TARGET` es el bloque de secuencia del Stop, y el paso 01 del 15 es
un prompt) — pero deja la **línea base dependiente del entorno**, que es
exactamente lo que la línea base existe para impedir.

**Cambia:** `-u CLAUDECODE` también en `golden-harness.sh:257`.

## CORRECCIÓN 9 — faltaba un ítem de la DoD: borrar la captura

La DoD dice, con negritas propias: **“Al cerrar se borra `C:\dev\saikit-captura`”**
— ahí viven los payloads crudos que sostienen A9 y A10, traen texto de un turno
real (por eso no están en el repo) y ésta es la última tarea que los necesita. El
plan no lo mencionaba. Se agrega al orden de cierre, **después** del turno real de
validación (que puede requerir volver a mirarlos) y antes del cierre en `Plans.md`.

## CORRECCIÓN 10 — números de línea

- `json_top_level_string` está en **`:98`**, no en `:90`.
- El fallback de `PHASE` es **`:1144-1152`**, no `1144-1153`.
- Las ramas `cursor` son **`:641`, `:699`, `:913`, `:935`** — faltaba la última.

## CORRECCIÓN 11 — se saca la especulación sobre la Task 2.4

“*probablemente* una lectura del estado de staging con un matcher/registro
distinto” es una hipótesis sin medición, en un plan cuyo primer paso obligatorio
fue medir. Se reemplaza por lo que sí se puede afirmar: no se reconstruyó, y no
hace falta, porque el arreglo es un fallback (ver arriba).

## CORRECCIÓN 12 — el paso 05 no puede conservar `last_review` y borrar el estado

La segunda pasada decía que en los pasos 04 **y 05** de la baseline se vería
`last_review=3`, pero también que el paso 05 pasaría a cierre limpio y borraría
el estado. Las dos cosas no pueden ocurrir a la vez: el cierre limpio elimina
`harness-state.env`, el evidence log y `harness-state-review-notice.env`.

**Cambia:** `last_review=3` se espera sólo tras el paso 04; tras el 05 se espera
`(sin estado)`, igual que en los demás cierres limpios de la baseline.

## CORRECCIÓN 13 — cerrar el código sin cerrar fixtures y spec deja dos verdades

El escenario 16 tiene su propia explicación en
`tests/fixtures/escenarios/16-eventos-dentro-de-subagente/README`, y el catálogo
general repite A9 en `tests/fixtures/README.md`. Re-grabar la baseline copia el
README del escenario como comentarios: si no se actualiza primero, la grabación
diría a la vez “el hook no mira `agent_type`” y mostraría que sí lo mira.

Además, `docs/spec/00-project-spec.md` sigue marcando A9/A10 abiertos y A10 con
causa `unknown`. Es el contrato canónico (`spec_path` de este plan), no una nota
histórica descartable.

**Cambia:** se actualizan los dos README de fixtures junto con la re-grabación;
tras la validación real se actualiza el spec con la causa medida, el fallback y
los límites, y recién entonces se marca Task 3.7 cerrada en `Plans.md`.

## CORRECCIÓN 14 — el test “registro completo = silencio” hoy usa el matcher roto

`escribir_settings_completo` en `tests/test_hook_registration.sh` usa justamente
`Bash|Edit|Write|apply_patch|Task`. Si se agrega el aviso nuevo sin tocar ese
fixture, el primer caso y varios casos de regresión que reutilizan el helper se
ponen rojos por el motivo nuevo. Además, el caso llamado “registro REAL ... sigue
contando” ya no puede exigir silencio: el registro real cuenta las tres fases,
pero debe advertir por `Agent`.

**Cambia:** el fixture “completo/sano” cubre `Agent`; el matcher real sin `Agent`
tiene un fixture/caso separado que exige sólo el aviso de matcher y comprueba que
no se reporten fases ausentes. La agregación queda definida para múltiples grupos
y para `settings.json` + `settings.local.json`: basta **una** entrada observable
que cubra `Agent`; si ninguna cubre pero una fuente o regex no pudo observarse,
el resultado es `unknown`, no ausencia.

## CORRECCIÓN 15 — el loop de verificación violaba la regla de eficiencia del repo

La versión anterior pedía `tests/run.sh` durante el verde y luego dos corridas
completas más con/sin `CLAUDECODE`. Eso contradice la regla local: rojo/verde con
**un archivo**, `tests/run.sh` una sola vez como gate final. También faltaba
copiar el sandbox de `run.sh` (`HOME`, `USERPROFILE`, `TMPDIR` y
`SAIKIT_HOOK_VIVO`), sin el cual se puede probar el hook instalado en vez de la
fuente.

**Cambia:** el desarrollo corre sólo los tres archivos enfocados y el arnés
dorado en sandbox; la invariancia de `CLAUDECODE` se comprueba sobre esos checks
enfocados. `tests/run.sh` queda exactamente una vez al final, seguido por
`pre-commit run --all-files`.

## CORRECCIÓN 16 — el cierre escribía `Plans.md` después del único commit

El orden anterior hacía commit, instalaba, validaba, y recién después modificaba
`Plans.md`; terminaba necesariamente con cambios sin commit (y ahora también hay
que cerrar el spec). No se puede declarar un cierre limpio así.

**Cambia:** hay un commit de implementación antes del install, y un segundo
commit documental de cierre después de la validación real y el borrado de la
captura. El último paso exige `git status --short` limpio salvo cambios ajenos
preexistentes, que se preservan y se declaran.

## CORRECCIÓN 17 — `LAB_CLAUDECODE` debe ser seguro bajo `set -u`

`hook_lab.sh` corre con `set -u`; agregar un flag global sin inicializar y leerlo
como `$LAB_CLAUDECODE` rompe todos los casos que no lo setean. La forma exacta es
`[ -n "${LAB_CLAUDECODE:-}" ] && lab_cmd+=(CLAUDECODE="$LAB_CLAUDECODE")`,
después de `env -u CLAUDECODE`. Así el default es realmente ausente y sólo el
caso de A10 lo repone.

---

# El arreglo

Dos cambios de hook, chicos, y van en orden (A10 primero: sin TARGET, el de A9
es inútil porque la rama donde se aplica no corre), más el reporte del
verificador de registro que pide la DoD.

### A10 — detección de Claude por `CLAUDECODE=1` (fallback cuando TARGET no llega)

`hooks/summonaikit-harness.sh:23`, hoy:

```sh
TARGET="$SUMMONAIKIT_HOOK_TARGET"
```

mañana:

```sh
TARGET="$SUMMONAIKIT_HOOK_TARGET"
# A10 (Task 3.7): el host NO propaga el prefijo VAR=val del comando registrado
# (medido 2026-08-11), asi que SUMMONAIKIT_HOOK_TARGET llega vacio en produccion
# y la rama de secuencia (claude) nunca corria. Claude Code setea CLAUDECODE=1
# (medido); acierta para Claude y para glm (que hace exec claude). No setea
# cursor ni zcode, que quedan con TARGET vacio -- correcto: la secuencia es una
# primitiva de Claude. El comando del operador (export dentro de bash -c) seria
# la via "limpia" para cursor/zcode pero toca settings.json, que ningun tool de
# este repo genera; queda fuera de esta tarea (ver Limites).
if [ -z "$TARGET" ] && [ "$CLAUDECODE" = "1" ]; then TARGET="claude"; fi
```

### A9 — leer `agent_type` top-level cuando `subagent_type` no está

`hooks/summonaikit-harness.sh:831-833`, hoy:

```sh
subagent="$(json_tool_input_string subagent_type)"
if [ -z "$subagent" ]; then subagent="$(json_tool_input_string subagentType)"; fi
if [ -n "$subagent" ]; then record_agent "$subagent"; fi
```

mañana (una línea):

```sh
subagent="$(json_tool_input_string subagent_type)"
if [ -z "$subagent" ]; then subagent="$(json_tool_input_string subagentType)"; fi
# A9 (Task 3.7): los eventos INTERNOS del subagente llevan el rol en agent_type
# de PRIMER NIVEL, no en subagent_type (que solo esta en los eventos Agent, que
# el matcher no cubre). Medido en la captura de 3.7. Es FALLBACK, no reemplazo:
# si subagent_type llega, gana. Un agent_type sin rol (general-purpose, Explore)
# no registra nada porque canonical_agent_role no lo mapea.
# OJO: $subagent tiene un segundo consumidor abajo (rn_mark_review, :836), asi
# que esto tambien enciende la senal de orden del review-notice. Es deliberado
# y esta declarado en el plan (CORRECCION 3).
if [ -z "$subagent" ]; then subagent="$(json_top_level_string agent_type)"; fi
if [ -n "$subagent" ]; then record_agent "$subagent"; fi
```

`json_top_level_string` ya existe (Task 3.4, `:98`, lee strings de depth==1) y
`canonical_agent_role` (`:774`) ya mapea `implementer`/`verifier`/`reviewer`
directamente. Cero funciones nuevas.

### La cláusula del matcher — se implementa, no se dropa

Ver CORRECCIÓN 2. `tools/check-hook-registration.sh` hoy solo verifica que las
**fases** (`UserPromptSubmit`, `PostToolUse`, `Stop`) estén registradas contra el
hook (`:121`, `ESPERADAS`). Se agrega: cuando el grupo que ejecuta el hook es de
`PostToolUse`, se lee su `matcher` y se reporta fuerte si no cubre `Agent`.

Postura del tool, que no cambia: **fail-open y no acusar lo que no se pudo
mirar**. `matcher` ausente o `"*"` ⇒ cubre. Cualquier otra cosa se prueba como
regex del host contra el literal `Agent`; si el regex no compila ⇒ `unknown`, no
ausencia. Exit 0 siempre.

---

# Cambios

### 1. `hooks/summonaikit-harness.sh`

**(a)** Línea 23: `TARGET` con fallback `CLAUDECODE=1` → `claude` (A10).
**(b)** Líneas 831-833: fallback a `json_top_level_string agent_type` (A9).

Nada más se toca. `canonical_agent_role`, `record_agent`, el bloque de secuencia
(`:1061`), el bloque del review-notice (`:834-839`) y los lectores `json_*` quedan
intactos — el review-notice cambia de **comportamiento** por el dato que ahora
recibe, no de código (CORRECCIÓN 3).

### 2. `tools/check-hook-registration.sh` — reporte del matcher (DoD)

Se registra, junto con la fase, el `matcher` de **cada** grupo cuyo comando
ejecuta el hook. La decisión se agrega sobre ambos settings y todos sus grupos:

1. `covered`: al menos una entrada observable de `PostToolUse` que ejecuta el
   hook tiene matcher ausente, `"*"`, o un regex válido que matchea `Agent`.
   Resultado: silencio respecto del matcher.
2. `uncovered`: hay entradas observables de `PostToolUse`, ninguna cubre
   `Agent`, todos sus matchers se pudieron compilar y todos los settings
   relevantes se pudieron leer. Resultado: reporte fuerte (exit 0, fail-open).
3. `unknown`: ninguna entrada observable cubre, pero algún matcher no compila o
   algún settings no se pudo leer y podría contener una entrada que cubra.
   Resultado: `unknown`; nunca se afirma ausencia.
4. Si falta la fase `PostToolUse`, manda el reporte de fase faltante; no se apila
   además un segundo diagnóstico de matcher sobre una fase que no existe.

El reporte fuerte de `uncovered` es:

```
[summonaikit] REGISTRO DEL HOOK: el matcher de PostToolUse no cubre `Agent`.
              matcher observado: Bash|Edit|Write|apply_patch|Task
              Efecto: un subagente que solo use herramientas fuera del matcher
              (Read/Grep/Glob) no genera ningun evento para el gate y su rol no
              se registra, aunque haya corrido. Se arregla en settings.json:
              agregar `Agent` al matcher de PostToolUse.
```

**Cambios en `tests/test_hook_registration.sh`:**

- `escribir_settings_completo` pasa a usar un matcher sano que incluya `Agent`,
  para que “registro completo => silencio” siga significando completo de verdad.
  Se agrega un helper separado (`escribir_settings_real_sin_agent`, o parámetro
  equivalente) con el matcher real `Bash|Edit|Write|apply_patch|Task`; no se hace
  pasar el fixture sano por “real”.
- El caso existente “registro REAL ... sigue contando” deja de exigir silencio:
  usa ese helper real, exige el aviso de matcher, pero también que NO aparezcan
  `INCOMPLETO`, `el gate NO corre` ni fases faltantes.
- Se agregan estos casos enfocados:

```
caso "matcher de PostToolUse que no cubre Agent => reporta FUERTE y exit 0"
caso "matcher '*' cubre y calla"
caso "un matcher cubierto entre varios => calla"
caso "base sin Agent + local con Agent => calla"
caso "base sin Agent + local ilegible => unknown, no ausencia"
```

y uno de regresión de la postura: `caso "matcher que no compila como regex =>
unknown, no ausencia"`. Los casos que usan un matcher roto o settings ilegible
también afirman que no aparece el texto fuerte “no cubre `Agent`”.

### 3. `tests/lib/gate_cases.sh` — un caso invierte + dos nuevos (G3, 9 → 11)

**`caso_g3_agent_type_no_cuenta` INVIERTE su expectativa** (como `caso_g4_*_a8`
en la 3.2) y se **renombra** a `caso_g3_agent_type_cuenta`. Hoy afirma que un
evento con `agent_type=implementer` **no** cuenta (era A9 grabado a propósito);
tras el arreglo **sí** cuenta:

```sh
# A9, CERRADO por la Task 3.7. Antes decia lo contrario y era el defecto grabado
# a proposito: el rol de los eventos INTERNOS del subagente viaja en agent_type
# de primer nivel, y el hook solo leia subagent_type (que vive en los eventos
# Agent, que el matcher no cubre) -> agents_seen quedaba vacio con los tres
# subagentes corridos. El escenario 16 de la linea base graba el turno entero;
# este caso graba la pieza suelta.
caso_g3_agent_type_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'implementer' 'npm test')"
  _igual "agents_seen con agent_type=implementer (A9 cerrado)" "$(lab_estado agents_seen)" "implementer"
}
```

**Nuevo `caso_g3_agent_type_generico_no_cuenta`** (CORRECCIÓN 6) — el canal nuevo
no puede inventar un rol ni pisar el legítimo:

```sh
# El canal que abre A9 (agent_type top-level) necesita las MISMAS dos guardias
# que ya tiene el de subagent_type, y no las hereda gratis:
#   1. un agent_type generico no inventa rol (gemelo de
#      caso_g3_agente_generico_no_cuenta, que solo cubre subagent_type);
#   2. es FALLBACK: con los dos presentes gana subagent_type. La forma del
#      segundo payload es real -- una delegacion ANIDADA trae el agent_type del
#      subagente padre y el subagent_type del hijo.
caso_g3_agent_type_generico_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'general-purpose' 'ls')"
  _igual "agent_type generico no inventa rol" "$(lab_estado agents_seen)" ""
  lab_run tool claude "$(lab_payload_agent_anidado 'implementer' 'reviewer')"
  _igual "subagent_type gana sobre agent_type" "$(lab_estado agents_seen)" "implementer"
}
```

**Nuevo `caso_g3_target_por_claudecode_fallback`** (con la CORRECCIÓN 5 aplicada)
— el caso del arreglo de A10:

```sh
# DEFECTO A10, el caso que lo habria atrapado. El host no propaga el prefijo
# VAR=val del comando registrado, asi que SUMMONAIKIT_HOOK_TARGET llega vacio y
# [ "$TARGET" = "claude" ] era siempre falso -> la secuencia nunca se exigia. El
# arreglo detecta Claude por CLAUDECODE=1 (fallback). Aqui NO se setea
# SUMMONAIKIT_HOOK_TARGET (target=auto) pero SI CLAUDECODE=1.
# El RECIBO VA COMPLETO A PROPOSITO: es lo unico que hace discriminar al caso.
# Con recibo, sin el arreglo el Stop cierra LIMPIO (exit 0) porque la rama de
# secuencia no corre; con el arreglo bloquea reclamando los tres roles. Con
# texto llano bloquearia igual por el recibo faltante y el caso no probaria nada.
caso_g3_target_por_claudecode_fallback() {
  lab_sembrar 123456 0 1 1 ""   # todo en orden salvo agents_seen (vacio)
  LAB_CLAUDECODE=1
  lab_run stop auto "$(lab_payload_stop "$_RECIBO_VINETAS")"
  LAB_CLAUDECODE=""
  _igual "exit code (CLAUDECODE=1 => TARGET=claude => secuencia exigida)" "$LAB_RC" "2"
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'
}
```

**Orden en `CASOS_G3`, load-bearing** (la batería corta en el primer caso rojo,
misma razón documentada para G4 en `gate_cases.sh:524-526`):

```
… caso_g3_agente_generico_no_cuenta
  caso_g3_agent_type_cuenta               <- posicion 5, la del viejo: se lleva mut_agent_type_no_se_lee
  caso_g3_agent_type_generico_no_cuenta   <- nuevo, detras (verde bajo todas las mutaciones G3: no roba credito)
  caso_g3_gana_el_de_tool_input_no_el_ultimo
  caso_g3_eco_fuera_de_tool_input_no_cuenta
  caso_g3_nombres_del_host_mapean
  caso_g3_turno_completo_por_eventos_permite
  caso_g3_target_por_claudecode_fallback  <- nuevo, al final: es el unico que reacciona a mut_target_sin_claudecode
```

Trazado a mano (leyendo cada `sed` contra el payload de cada caso, **no
ejecutado** — eso lo confirma el paso 1 del orden TDD): ninguno de los dos casos
nuevos se pone rojo bajo las cinco mutaciones G3 que ya existen
(`reviewer_siempre_visto`, `orden_no_se_exige`, `secuencia_tambien_en_cursor`,
`subagent_type_greedy`, `tool_input_no_se_acota`), así que no le roban el crédito
a nadie. Si al correr la batería alguno lo hace, se reubica en `CASOS_G3` y se
declara el porqué.

**Referencias al nombre viejo que se actualizan** (CORRECCIÓN 7):
`gate_cases.sh:28` (índice del encabezado), `:405` (`CASOS_G3`), `:456` (la
definición). **No** hay ninguna en el catálogo de mutaciones. La cuarta,
`Plans.md:67`, se resuelve declarando el renombre en el cierre.

### 4. `tests/lib/hook_lab.sh` — `CLAUDECODE` controlado + un payload

**Hoy `lab_run` no controla `CLAUDECODE`.** Como los tests corren dentro de
Claude Code, el proceso hereda `CLAUDECODE=1` del exterior — y con el fallback de
A10 eso haría que TODO caso con `target=auto` resuelva `TARGET=claude` sin que
nadie lo pida (tests no deterministas). Hay que:

- `lab_run` **unsetea `CLAUDECODE`** por defecto: `-u CLAUDECODE` en el
  `env` de `:129`, junto a los tres que ya unsetea.
- Lo repone sólo cuando el caso lo pide, con expansión segura bajo `set -u`:
  `[ -n "${LAB_CLAUDECODE:-}" ] && lab_cmd+=(CLAUDECODE="$LAB_CLAUDECODE")`.

Sin esto, el arreglo de A10 haría verdes tests que no prueban lo que creen.

**Nuevo `lab_payload_agent_anidado`** — un `Agent` con `tool_input.subagent_type`
y `agent_type` de primer nivel a la vez (delegación anidada). Es el payload de la
segunda afirmación de `caso_g3_agent_type_generico_no_cuenta`.

### 5. `tools/golden-harness.sh` — `CLAUDECODE` también acá (CORRECCIÓN 8)

`-u CLAUDECODE` en el `env` de `:257`. Mismo motivo que en `lab_run`, y con más
razón: el escenario 15 corre `target=auto` y la línea base tiene que ser
reproducible corriendo adentro o afuera de Claude Code.

### 6. `tests/test_gate_mutations.sh` — 28 → 30 (G3 5 → 7)

```sh
# A9 (Task 3.7): se neutraliza el fallback a agent_type top-level. Los eventos
# internos que llegan al gate dejan de registrar el rol. Lo atrapa
# caso_g3_agent_type_cuenta (el invertido), que va antes en CASOS_G3.
mut_agent_type_no_se_lee() { sed 's/json_top_level_string agent_type/true/'; }
# A10 (Task 3.7): CLAUDECODE=1 deja de matchear => TARGET vuelve a quedar vacio
# en produccion y la secuencia no se exige. Lo atrapa
# caso_g3_target_por_claudecode_fallback (el Stop cierra limpio en vez de
# bloquear). NO se muta a `[ false ]`: `test` con un unico argumento no vacio da
# VERDADERO, o sea que volveria el fallback incondicional y ningun caso
# reaccionaria (ver CORRECCION 4). Cambiar el valor comparado no toca la
# estructura de corchetes ni mete backslashes (la trampa de MSYS2 de :128-131).
mut_target_sin_claudecode() { sed 's/"$CLAUDECODE" = "1"/"$CLAUDECODE" = "0"/'; }
```

```
G3|agent_type_no_se_lee|el rol de los eventos internos (agent_type) deja de leerse
G3|target_sin_claudecode|el fallback CLAUDECODE=1 se anula y TARGET queda vacio en produccion
```

`mut_agent_type_no_se_lee` deja `subagent="$(true)"` — `bash -n` pasa y devuelve
vacío (comprobado), así que cruza las tres guardias del driver.

### 7. READMEs de fixtures + `tests/golden/baseline.txt` — cerrar y re-grabar el 16

Antes de grabar, actualizar:

- `tests/fixtures/escenarios/16-eventos-dentro-de-subagente/README`: pasa de
  describir A9 abierto a describir el fallback ya cerrado, el canal `Agent` que
  sigue fuera del matcher y el hueco read-only que reporta el verificador.
- `tests/fixtures/README.md:72-78`: la captura sigue siendo evidencia histórica,
  pero el estado actual queda marcado como cerrado por Task 3.7.

La baseline incorpora esos comentarios actualizados; no debe conservar frases
en presente como “el hook no mira `agent_type`” o “Defecto A9” sin “cerrado”.

Verificado que **el 16 es el único escenario con `agent_type` de primer nivel** en
sus fixtures (los otros hits del grep son `subagent_type`, que lo contiene como
substring). El diff esperado, y **eso es la declaración**:

- **pasos 02-04**: `agents_seen` pasa de vacío a `implementer`, luego
  `implementer,verifier`, luego `implementer,verifier,reviewer`.
- **paso 04**: `last_review=` pasa a `last_review=3` en
  `harness-state-review-notice.env` — el efecto colateral declarado en la
  CORRECCIÓN 3. `last_code_edit=1 < 3`, así que el aviso no dispara.
- **paso 05**: exit 2 con los tres *“Missing … subagent run”* pasa a **exit 0**,
  stdout/stderr vacíos y la sección de estado pasa a **`(sin estado)`** (el
  `05.stop.claude.json` trae recibo completo, verificado). No puede quedar un
  `last_review=3` después de este paso: el cierre limpio borra ese archivo.

La línea base del arnés setea `SUMMONAIKIT_HOOK_TARGET=claude` explícitamente
(`target=claude` en cada paso del 16), así que **este diff mide A9 puro**; A10 se
mide en el caso nuevo, no acá.

Si el paso 05 **no** cerrara limpio (otro missing), se investiga — no se asume.

### 8. `docs/spec/00-project-spec.md` + `Plans.md` — cierre canónico

Esto ocurre **después** del turno real, no antes:

- En el spec, marcar A9 y A10 `CERRADO (Task 3.7)`; actualizar A10 de causa
  `unknown` a la medición real (el prefijo del comando no llega al env, pero
  `CLAUDECODE=1` sí) y registrar el fallback elegido.
- Mantener como historia las mediciones de Tasks 1.4/2.4, pero agregar una nota de
  cierre que impida leerlas como estado vigente. No reescribir la historia.
- Declarar los límites que siguen: matcher real sin `Agent`, subagente read-only,
  gate advisory y targets no-Claude sin detector.
- En `Plans.md:67`, cambiar a `cc:完了 [sha]` sólo con la validación real hecha,
  el spec alineado y la captura borrada; declarar el renombre del caso.

---

# Verificación

1. `bash -n` sobre cada `.sh` tocado.
2. Rojo/verde enfocado, cada archivo dentro de un sandbox equivalente al de
   `tests/run.sh`: `HOME`, `USERPROFILE`, `TMPDIR`/`TMP`/`TEMP` desechables y
   `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh"`. Archivos:
   - `tests/test_gate_behavior.sh`
   - `tests/test_gate_mutations.sh`
   - `tests/test_hook_registration.sh`
3. `bash tools/golden-harness.sh --check` después de re-grabar; 0 divergencias no
   declaradas.
4. **30 mutaciones, 30 atrapadas**, con las 2 nuevas acreditadas a **su** caso
   (`agent_type_no_se_lee` → `caso_g3_agent_type_cuenta`;
   `target_sin_claudecode` → `caso_g3_target_por_claudecode_fallback`).
5. Declaración del diff de la línea base: comentarios del fixture actualizados;
   pasos 02-04 con roles; sólo paso 04 con `last_review=3`; paso 05 limpio y
   `(sin estado)`.
6. Invariancia enfocada con y sin `CLAUDECODE`: correr
   `tests/test_gate_behavior.sh` y `tools/golden-harness.sh --check` en el mismo
   sandbox una vez con `CLAUDECODE=1` y otra con `env -u CLAUDECODE`. El resultado
   y la baseline deben ser idénticos. **No** se duplica `tests/run.sh` para esto.
7. Gate completo **una sola vez**:
   `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/run.sh` →
   0 FAIL, 0 UNKNOWN.
8. Candados: antes del commit de implementación usar staged-only o
   `pre-commit run --files <tocados>`; después de actualizar spec/Plans, ejecutar
   el gate final `pre-commit run --all-files` **una sola vez**. Nunca
   `--no-verify`.
9. **El install del hook no es parte de la verificación**: va después del commit
   de implementación.
10. Por ser un cambio delicado del gate, **sugerir** una única ronda de revisión
    cruzada con `C:\Users\ehven\quality-kit\cross-review.ps1`; ejecutarla sólo si
    el operador la autoriza. Máximo una ronda, salvo hallazgo de severidad alta.

# Orden (TDD)

1. Preparar una sola vez el sandbox de test con el mismo env de `tests/run.sh` y
   `SAIKIT_HOOK_VIVO` apuntando a la **fuente**. Los casos nuevos + mutaciones van
   en **rojo** contra el hook sin tocar:
   - `caso_g3_agent_type_cuenta` (el invertido) ⇒ hoy `agents_seen` vacío (rojo).
   - `caso_g3_target_por_claudecode_fallback` ⇒ hoy el Stop cierra limpio en vez
     de bloquear (rojo). Requiere primero el cambio a `lab_run`
     (unsetear/pasar `CLAUDECODE`) y el payload nuevo del lab.
   - `caso_g3_agent_type_generico_no_cuenta` ⇒ **verde desde el principio**, y es
     correcto: es un caso de regresión del canal que se abre, no de defecto. Se
     declara así para que no se lea como una mutación sin atrapador.
   - Los casos de `check-hook-registration.sh` ⇒ rojos (hoy no mira el matcher).
   En esta fase se corren sólo `test_gate_behavior.sh`,
   `test_gate_mutations.sh` y `test_hook_registration.sh`, nunca `tests/run.sh`.
2. Arreglo en el hook (A10 línea 23, A9 líneas 831-833).
3. Reporte del matcher en `tools/check-hook-registration.sh`, actualización del
   helper sano y de las expectativas existentes en `test_hook_registration.sh`.
4. `-u CLAUDECODE` en `tools/golden-harness.sh:257`.
5. Verde sobre los tres archivos enfocados, en el sandbox del paso 1.
6. Actualizar los dos README de fixtures; re-grabar la línea base; revisar y
   declarar el diff del escenario 16; `golden-harness.sh --check` verde.
7. Comprobar invariancia enfocada con/sin `CLAUDECODE` (Verificación 6).
8. Correr `tests/run.sh` **una sola vez** (Verificación 7).
9. Correr staged-only `pre-commit run` o `pre-commit run --files <tocados>` y
   crear el commit de implementación:
   `feat(3.7): A9+A10 cerrados — agent_type cuenta y CLAUDECODE resuelve TARGET`.
10. `tools/install-hook.sh` — después de ese commit.
11. **Turno real de validación (operador adelante):** un `-saikit` con
    delegaciones; el estado debe quedar `agents_seen=implementer,verifier,reviewer`
    y el Stop **exigir** la secuencia (no cerrar limpio si falta). Esto es lo que
    la línea base no puede atestiguar (corre con TARGET explícito). Además se mira
    `tools/check-hook-registration.sh` en ese turno: tiene que reportar el matcher.
12. **Borrar `C:\dev\saikit-captura`** (CORRECCIÓN 9, ítem literal de la DoD).
    Va acá y no antes: el turno de validación puede requerir volver a mirar los
    payloads. Resolver primero la ruta absoluta exacta; si el sandbox exige
    aprobación, pedirla. No marcar la DoD cumplida si el borrado no ocurrió.
13. Actualizar `docs/spec/00-project-spec.md` y cerrar `Plans.md` punto por punto
    (`cc:TODO` → `cc:完了 [sha]`), declarando el renombre
    `caso_g3_agent_type_no_cuenta` → `caso_g3_agent_type_cuenta` que la DoD
    nombra literalmente.
14. Gate final, ahora que **todos** los archivos están en su forma definitiva:
    `pre-commit run --all-files` una sola vez.
15. Commit documental de cierre: `docs(3.7): registrar validación real y cerrar A9+A10`.
16. `git status --short`: limpio. Si había cambios ajenos preexistentes, no se
    incluyen ni revierten; se dejan exactamente como estaban y se declaran.

# No entra en esta tarea (límites declarados)

- **No se cambia el comando del operador en `settings.json`.** La vía “limpia”
  para A10 sería poner el `export SUMMONAIKIT_HOOK_TARGET=claude` **dentro** del
  `bash -c` del comando registrado (medido: así TARGET llega). Pero ese comando
  no lo genera ningún tool del repo (`install-hook.sh` instala el archivo, no el
  registro) — tocarlo es una edición manual del operador, fuera del alcance. El
  fallback `CLAUDECODE=1` desbloquea el gate de Claude sin ese cambio. **Mismo
  criterio para el matcher**: la cláusula de la DoD se cumple *reportando*, no
  editando el registro (Cambio 2).
- **Hueco conocido: el subagente read-only.** Tras A9, el rol llega por los
  eventos internos cuya herramienta está en el matcher (`Bash|Edit|Write|
  apply_patch|Task`). Un subagente que solo use `Read`/`Grep`/`Glob` y devuelva
  texto no produce ningún evento para el gate y **su rol no se registra**. Es el
  costo de no tocar el registro, y es exactamente lo que el reporte nuevo de
  `check-hook-registration.sh` pone delante del operador. No se cierra en esta
  tarea (CORRECCIÓN 2).
- **Cursor queda sin TARGET.** `CLAUDECODE=1` no identifica cursor (ni zcode).
  Las ramas `cursor` (`:641`, `:699`, `:913`, `:935`) siguen inertes en
  producción hasta que se adopte la vía del comando o un detector de cursor. No
  es objetivo de este repo (summonaikit-**claude**).
- **El review-notice cambia de comportamiento, y es deliberado.** Su señal de
  orden estaba tan muerta como el gate de secuencia y A9 la enciende
  (CORRECCIÓN 3). Queda declarada en el diff de la línea base. No se agranda el
  alcance: no se agregan casos de comportamiento para el review-notice, que hoy
  solo vive en la línea base.
- **El gate sigue `advisory`.** Quien controla el payload sigue pudiendo nombrar
  el rol que quiera en `agent_type`. Lo que A9+A10 cierran es que el gate
  **corra** (A10) y **vea** el rol real (A9) en un turno legítimo.
- **No se persigue por qué el host descarta el prefijo `VAR=val`.** Es internals
  del host (probablemente corre el comando sin shell que lo parsee, o vía
  `cmd.exe` en Windows). El efecto está medido y el arreglo no depende de la
  causa exacta.
- **No se reconstruye qué pobló `agents_seen` en la Task 2.4.** No se pudo, no se
  especula, y no bloquea: el arreglo es un fallback y `subagent_type` sigue
  ganando si llega (CORRECCIÓN 11).
