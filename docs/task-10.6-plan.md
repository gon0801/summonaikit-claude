# Task 10.6 — Plan: reglas permanentes en `SessionStart`

`[Feature]` `[lane:gate]` `[tdd:required]`.

## El problema, medido

El 2026-08-14 una task de medición (6.2) tardó ~7 h. El desglose del transcript
(`e86ddb2c`, 186 llamadas) dice dónde se fue:

| | |
|---|---|
| Modelo pensando | **9 %** |
| Herramientas produciendo | ~2.4 h |
| **Bloqueado esperando** | **2.6 h — 51 % del tiempo de herramientas** |

De esas 2.6 h, ~1.75 h eran evitables: **70 min** por correr la suite completa
3 veces (debía ser 1) y **35 min** esperando una re-review que ya había
terminado.

**Y la regla ya existía.** El contrato inyectado dice, desde la 10.2:

> *One full battery run per task, at the end, is enough evidence for the
> receipt. Re-running the entire suite after every fix wastes the turn.*

Se violó igual. La causa **no** es que falte la regla:

1. `harness_context()` se llama dentro de `start_harness`, o sea **sólo en el
   camino armado**.
2. Esa sesión **nunca armó** — se trabajó con `/goal`, no con `-saikit`; no se
   escribió estado.
3. ⇒ El contrato nunca llegó. La regla estaba en el kit y era invisible.

**Corolario que hay que escribir:** agregar más texto al contrato NO arregla
esto. El kit se calla en turnos sin armar **por diseño** —es el invariante del
sentinel— y esta tarea **no lo toca**.

## Lo que sí falta

Un canal para reglas **permanentes**, que valga en toda sesión de todo repo,
arme o no. `SessionStart` es exactamente eso: no gatea, no exige recibo, no
cuenta ciclos. Sólo deja escrito el invariante una vez por sesión.

## Medición previa (hecha antes de diseñar)

Repo descartable `C:\dev\saikit-probe-session`, `.claude/settings.json` de
proyecto (el perfil **no se tocó**), un turno headless `claude -p`.

| Pregunta | Resultado |
|---|---|
| ¿`SessionStart` en Claude acepta `hookSpecificOutput.additionalContext`? | **Sí** |
| ¿El texto llega al modelo? | **Sí, textual.** Lo citó y lo identificó como *"contexto adicional de un hook de SessionStart"* |

Sin esa medición el diseño sería una hipótesis. Es la lección literal de 6.1→6.4.

## Alcance: **sólo Claude**, y por qué

Los otros tres hosts **no se miden en esta tarea y por lo tanto no se
registran**:

- **zcode / Grok:** no está medido si tienen `SessionStart` ni si acepta
  contexto. `unknown` ≠ "no lo tiene".
- **Codex:** `~/.codex/hooks.json` **sí** tiene `SessionStart` (con
  `matcher: startup`), pero es de **otras herramientas**, no del kit, y su
  contrato de salida en esa fase no se midió. 6.2 midió el de `Stop` y encontró
  que Codex **descarta el stdout cuando el exit no es 0** — precisamente el tipo
  de sorpresa que impide extrapolar de una fase a otra.

Registrar a ciegas en 4 hosts es exactamente el error que 6.2 evitó por un pelo.
Cada host adicional entra por su propia fila, con su medición delante.

## §A — El cambio

### A1. Emisión en `PHASE=session`

Hoy, en `start_harness`, un payload sin sentinel cae en `emit_allow` (silencio).
La fase `session` **nunca trae sentinel** y ya está contemplada ahí.

El cambio es una rama nueva **antes** de ese `emit_allow`, acotada a
`PHASE=session`: emite las reglas permanentes y sale 0.

**Lo que NO cambia, y hay que poder demostrarlo:**

- El gate del sentinel (`SAIKIT_SENTINEL_RE`) queda intacto.
- El desarme sigue acotado a `PHASE=prompt` (línea 838): un `SessionStart` no
  borra estado, como hoy.
- **Cursor sigue armando en `session` con `-saikit` en el texto**
  (`caso_g6_armado_por_target`): la rama nueva sólo corre cuando **no** hay
  sentinel, así que el camino de cursor cae por debajo sin tocarse.
- Ningún turno armado cambia: `harness_context()` no se toca.

### A2. El texto: corto, medido, genérico

Sólo entran reglas con un número atrás. Nada de consejos.

1. **Una corrida de la batería completa por tarea, al final.** El rojo/verde va
   sobre UN archivo de test. *(70 min medidos)*
2. **No te quedes bloqueado esperando un job en background.** Seguí trabajando;
   la notificación llega sola. *(2.6 h medidas en esperas, 14 de ellas de
   exactamente 10 min)*
3. **Antes de esperar a un revisor externo, fijate si ya terminó** en vez de
   re-consultar en bucle. *(35 min medidos)*

Genéricas a propósito: el kit corre en repos que no tienen `tests/run.sh`.

### A3. Registro — **corregido al implementar**

El plan decía "el instalador gana la 4.ª fase". **Es falso y se corrige acá:**
`tools/install-hook.sh` NO registra nada en `~/.claude/settings.json` — sólo
instala el ARCHIVO por reemplazo, y su única rama de registro es `--host zcode`
(append-only al user-config de zcode, Task 5.4).

Entonces el registro de `SessionStart` en Claude es **acción de operador**,
mismo patrón que la Task 9.9 (agregar `Agent` al matcher de `PostToolUse`).

`tools/check-hook-registration.sh` sí cambia: aprende a **afirmar la 4.ª fase
por separado**, y como **advisory**, no como fase requerida. Meterla en
`ESPERADAS` (línea 146) haría que **todo install existente** se reporte como
roto, cuando el gate funciona perfectamente sin ella: las reglas permanentes son
una mejora, no un requisito del gate. Se conserva `exit 0` siempre y
`unknown` ≠ ausente.

## §B — Cómo se prueba

| Caso | Qué fija |
|---|---|
| `caso_session_inyecta_reglas` | un `SessionStart` sin sentinel emite forma 1 con las reglas y sale 0 |
| `caso_session_no_crea_estado` | ese mismo turno **no** escribe `harness-state.env` |
| `caso_session_no_desarma` | con estado armado presente, un `SessionStart` no lo borra |
| `caso_g6_armado_por_target` | **regresión**: cursor con `-saikit` en `session` sigue armando |
| `caso_prompt_sin_sentinel_sigue_mudo` | **regresión**: `PHASE=prompt` sin sentinel sigue sin emitir |
| registro | `--host claude` deja la 4.ª fase; el verificador la reporta separada |

**Mutaciones:** `mut_session_sin_reglas` (saca la rama ⇒ el caso de inyección
rojo) y `mut_session_pisa_gate` (deja la rama correr también sin acotar a
`session` ⇒ la regresión de `prompt` roja).

## §C — Línea base

El contrato inyectado **no cambia**, así que los escenarios armados no deberían
moverse. Lo que sí aparece es una salida nueva en la fase `session`.

**Predicción declarada por adelantado:** divergen únicamente los escenarios que
ejercitan `SessionStart`; **cero veredictos movidos** (exit codes, `decision`,
`agents_seen`). Si diverge algo más, la rama toca de más — y esa es la señal,
igual que la predicción corta de la 6.3 lo fue.

**MEDIDO: `test_golden_baseline` da OK con CERO divergencia**, y no hay que
leerlo como "el cambio no toca nada". La razón real es que **ningún escenario de
la línea base ejercita la fase `SessionStart`** — o sea que la línea base **no
cubre** el camino nuevo. Se declara como hueco, no como éxito: los casos de
`gate_cases.sh` y sus dos mutaciones son hoy la única red de esta rama. Un
escenario de `SessionStart` en la línea base queda pendiente y entra por su
propia fila; grabarlo acá exigiría regrabar el bloque completo, que es
exactamente lo que choca con la sesión paralela en curso.

## §D — Riesgos

| Riesgo | Mitigación |
|---|---|
| Choque con la sesión paralela (está en `feat/9.10-runner-bash`, mismo archivo) | Regiones distintas; el regrabado de la línea base va **último**, sobre master fresco |
| El texto crece con el tiempo y contamina cada sesión | Sólo entra una regla si tiene un número medido detrás. Es la misma disciplina del `CLAUDE.md` |
| `SessionStart` con matcher no cubre `resume`/`clear` | Se registra **sin matcher**, como `UserPromptSubmit` y `Stop`. Que dispare en `clear` está observado en vivo |
