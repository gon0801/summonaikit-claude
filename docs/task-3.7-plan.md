# Task 3.7 — A9+A10: el gate de ceremonia es inerte (plan para revisión)

`[Guardrail]` `[lane:gate]` `[tdd:required]`. Cierra **A9 + A10**, que van
juntos (se enmascaran). **DoD íntegra en `Plans.md:67`.**

> **Primer paso obligatorio de la DoD: re-medir.** Es lo primero que se hizo, y
> **cambió la forma de la tarea**. Este plan es la re-redacción con lo medido.

---

## La re-medición (2026-08-11, captura real en `C:\dev\saikit-captura`)

Se capturaron los payloads crudos de un turno real con delegaciones a
implementer/verifier/reviewer (12 eventos `PostToolUse`, vía
`tools/capture-payloads.sh`), y el entorno del hook (`bash -c 'export …'` form).
**La premisa original de A9 —“el rol viaja en `agent_type`”— se CONFIRMA. La
conclusión de la Task 2.4 (“el rol viaja en `subagent_type`”) era una
atribución errónea**, y se corrige acá.

### A9 confirmado, con la huella medida

Los 12 `PostToolUse` se separan en dos grupos limpios:

| grupo | cantidad | `tool_name` | dónde lleva el rol | ¿llega al gate? |
|---|---|---|---|---|
| delegación del padre | 3 | **`Agent`** | `tool_input.subagent_type` | **no** (matcher dice `Task`, herramienta `Agent`) |
| eventos internos del subagente | 9 | `Bash`/`Write`/`Read`/`StructuredOutput` | **`agent_type` top-level** | **sí** (matchean el matcher) |

- Los eventos que el gate **sí recibe** (los internos) llevan el rol en
  `agent_type` de primer nivel. El hook lee `subagent_type` (`:831`,
  `json_tool_input_string`) ⇒ no lo ve ⇒ `agents_seen` queda vacío.
- Los eventos que llevan `subagent_type` (los `Agent`) **no llegan al gate**: el
  matcher registrado es `Bash|Edit|Write|apply_patch|Task`, y la herramienta se
  llama `Agent`.

**Por qué 2.4 se equivocó.** El cierre de 2.4 analizó el **transcript** (.jsonl,
que registra las llamadas `Agent` con `subagent_type`) y concluyó que el rol
viajaba en `subagent_type`. Pero el hook lee los **payloads de PostToolUse**, no
el transcript — y en esos payloads, el rol de los eventos que llegan va en
`agent_type`. `agents_seen` poblado en 2.4 fue probablemente una lectura del
estado de staging con un matcher/registro distinto; la medición de **payloads**
que vale es ésta, y dice `agent_type`.

### A10 confirmado, con la CAUSA aislada (ya no es `unknown`)

- El host **no propaga el prefijo `VAR=val`** del comando registrado al ambiente
  del hook. Medición directa: registrando `SUMMONAIKIT_HOOK_TARGET=claude bash
  capture-payloads.sh`, el `SUMMONAIKIT_HOOK_TARGET` **no apareció** en el env
  del hook.
- **`PHASE` sobrevive** porque el hook la deriva del payload cuando el env viene
  vacío (`hooks/summonaikit-harness.sh:1144-1153`, fallback a `hook_event_name`).
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

## El arreglo

Dos cambios de hook, chicos, y van en orden (A10 primero: sin TARGET, el de A9
es inútil porque la rama donde se aplica no corre).

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
# A9 (Task 3.7): los eventos INTERNOS del subagente (los que matchean el matcher
# y llegan al gate) llevan el rol en agent_type de PRIMER NIVEL, no en
# subagent_type (que solo esta en los eventos Agent, que no matchean). Medido en
# la captura de 3.7: 9 de 12 PostToolUse con agent_type top-level.
if [ -z "$subagent" ]; then subagent="$(json_top_level_string agent_type)"; fi
if [ -n "$subagent" ]; then record_agent "$subagent"; fi
```

`json_top_level_string` ya existe (Task 3.4, `:90`, lee strings de depth==1) y
`canonical_agent_role` (`:774`) ya mapea `implementer`/`verifier`/`reviewer`
directamente. Cero funciones nuevas.

**Por qué esto hace moot la cláusula del matcher.** La DoD original pedía que
`check-hook-registration.sh` “reporte fuerte si el matcher no cubre la
herramienta de subagentes”. Ya no hace falta: el rol llega por los eventos
**internos** (que matchean), no por los `Agent`. Exigir `Agent` en el matcher era
necesario sólo bajo la premise (falsa) de que el rol viajaba en `subagent_type`.
**Se dropa esa cláusula**, declarado.

## Cambios

### 1. `hooks/summonaikit-harness.sh`

**(a)** Línea 23: `TARGET` con fallback `CLAUDECODE=1` → `claude` (A10).
**(b)** Línea 831-833: fallback a `json_top_level_string agent_type` (A9).

Nada más se toca. `canonical_agent_role`, `record_agent`, el bloque de secuencia
(`:1061`), y los lectores `json_*` quedan intactos.

### 2. `tests/lib/gate_cases.sh` — un caso que invierte + uno nuevo (G3)

**`caso_g3_agent_type_no_cuenta` INVIERTE su expectativa** (como `caso_g4_*_a8`
en la 3.2). Hoy afirma que un evento con `agent_type=implementer` **no** cuenta
(era A9 grabado a propósito). Tras el arreglo **sí** cuenta:

```sh
# Antes (A9 grabado): _igual "agents_seen con agent_type=implementer (A9)" "" ""
# Despues (A9 cerrado):
caso_g3_agent_type_no_cuenta() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'implementer' 'npm test')"
  _igual "agents_seen con agent_type=implementer (A9 cerrado)" "$(lab_estado agents_seen)" "implementer"
}
```

Y se **renombra** a `caso_g3_agent_type_cuenta` (el nombre actual miente tras el
arreglo). El nombre viejo se referencia en `CASOS_G3` y en el catálogo de
mutaciones; ambos se actualizan.

**Nuevo `caso_g3_rol_por_agent_type_en_evento_interno`** — el caso que habría
atrapado A9 con su forma medido: un evento interno (Bash en un subagente) con
`agent_type=reviewer` registra el reviewer.

```sh
# DEFECTO A9, el caso que lo habria atrapado. El rol viaja en agent_type de
# primer nivel en los eventos INTERNOS del subagente (los que matchean el
# matcher y llegan al gate). El hook antes leia solo subagent_type (que esta en
# los eventos Agent, que no matchean) -> agents_seen quedaba vacio. Ahora lee
# agent_type y registra el rol.
caso_g3_rol_por_agent_type_en_evento_interno() {
  lab_sembrar 123456 0 0 0 ""
  lab_run tool claude "$(lab_payload_bash_en_subagente 'reviewer' 'npm test')"
  _igual "agents_seen via agent_type top-level (A9)" "$(lab_estado agents_seen)" "reviewer"
}
```

(`lab_payload_bash_en_subagente` ya existe, `hook_lab.sh:231`, y arma exactamente
la forma medida: `agent_type` top-level, `tool_name=Bash`.)

**Nuevo `caso_g3_target_por_claudecode_fallback`** — el caso del arreglo de A10:
sin `SUMMONAIKIT_HOOK_TARGET` pero con `CLAUDECODE=1`, el Stop exige la secuencia
(o sea, `TARGET` resolvió a `claude`).

```sh
# DEFECTO A10, el caso que lo habria atrapado. El host no propaga el prefijo
# VAR=val del comando registrado, asi que SUMMONAIKIT_HOOK_TARGET llega vacio y
# [ "$TARGET" = "claude" ] era siempre falso -> la secuencia nunca se exiga. El
# arreglo detecta Claude por CLAUDECODE=1 (fallback). Aqui NO se setea
# SUMMONAIKIT_HOOK_TARGET (target=auto) pero SI CLAUDECODE=1; el Stop tiene que
# reclamar los roles (TARGET resolvio a claude). Sin el arreglo, cerraria limpio.
caso_g3_target_por_claudecode_fallback() {
  lab_sembrar 123456 0 1 1 ""   # todo en orden salvo agents_seen (vacio)
  LAB_CLAUDECODE=1
  lab_run stop auto "$(lab_payload_stop "$_TEXTO_LLANO")"   # target=auto: no setea SUMMONAIKIT_HOOK_TARGET
  LAB_CLAUDECODE=""
  _igual "exit code (CLAUDECODE=1 => TARGET=claude => secuencia exigi" "$LAB_RC" "2"
  _contiene "motivo (reclama implementer)" "$LAB_OUT" 'Missing implementer subagent run'
}
```

Esto exige que `lab_run` (a) no setee `SUMMONAIKIT_HOOK_TARGET` cuando
`target=auto` (ya lo hace) y (b) pase `CLAUDECODE` controlado.

### 3. `tests/lib/hook_lab.sh` — `CLAUDECODE` controlado

**Hoy `lab_run` no controla `CLAUDECODE`.** Como los tests corren dentro de
Claude Code, el proceso hereda `CLAUDECODE=1` del exterior — y con el fallback
de A10, eso haría que TODO caso con `target=auto` resuelva `TARGET=claude` sin que
nadie lo pida (tests no deterministas). Hay que:

- `lab_run` **unsetea `CLAUDECODE`** por defecto (como ya unsetea
  `SUMMONAIKIT_HOOK_TARGET`/`PHASE`), para que el lab sea determinista.
- Pasa `CLAUDECODE="$LAB_CLAUDECODE"` cuando el caso lo pide (nuevo flag, mismo
  idiom que `LAB_SESSION_ID`).

Sin esto, el arreglo de A10 haría verdes tests que no prueban lo que creen.

### 4. `tests/test_gate_mutations.sh` — 28 → 30 (G3 5 → 7)

```sh
# A9 (Task 3.7): se quita el fallback a agent_type top-level. Los eventos
# internos (que llegan al gate) dejan de registrar el rol. Lo atrapa
# caso_g3_rol_por_agent_type_en_evento_interno (y el invertido
# caso_g3_agent_type_cuenta).
mut_agent_type_no_se_lee() { sed 's/json_top_level_string agent_type//'; }
# A10 (Task 3.7): se neutraliza el fallback CLAUDECODE=1 => TARGET vuelve a
# quedar vacio en produccion y la secuencia no se exige. Lo atrapa
# caso_g3_target_por_claudecode_fallback (el Stop cerraria limpio en vez de
# bloquear).
mut_target_sin_claudecode() { sed 's/\[ "$CLAUDECODE" = "1" ]/[ false ]/'; }
```

```
G3|agent_type_no_se_lee|el rol de los eventos internos (agent_type) deja de leerse
G3|target_sin_claudecode|el fallback CLAUDECODE=1 se anula y TARGET queda vacio en produccion
```

Y **`mut_subagent_type_greedy`** / referencias al nombre viejo
`caso_g3_agent_type_no_cuenta` se actualizan al nuevo `caso_g3_agent_type_cuenta`.

### 5. `tests/golden/baseline.txt` — re-grabar escenario 16

`16-eventos-dentro-de-subagente` **pasa de bloquear a cerrar limpio**: tras A9,
los tres `agent_type` (implementer/verifier/reviewer) pueblan `agents_seen`; tras
A10, `TARGET=claude` así que la secuencia se evalúa (y se satisface). El Stop
cierra limpio (exit 0) en vez de exit 2 con "Missing … subagent run". **Ese diff
es la declaración** de qué cambió. (La baseline del arnés dorado setea
`SUMMONAIKIT_HOOK_TARGET=claude` explícitamente, así que el diff de 16 mide el
A9 puro; el A10 se mide en el caso nuevo, no en la baseline.)

Si **no** cerrara limpio (otro missing), se investiga — no se asume.

## Verificación

1. `pre-commit run --all-files` (sin `--no-verify`, regla de hierro #1).
2. `bash tests/run.sh` → 0 FAIL, 0 UNKNOWN.
3. **30 mutaciones, 30 atrapadas**, las 2 nuevas acreditadas a su caso.
4. Declaración del diff de la línea base (escenario 16: bloquear → cerrar limpio).
5. **El install del hook no es parte de la verificación**: va después del commit.
6. Cross-review con codex sobre staged **sólo si el operador la pide** (regla
 nueva: no se auto-lanza).

## Orden (TDD)

1. Los casos nuevos + las mutaciones, en **rojo** contra el hook sin tocar:
   - `caso_g3_rol_por_agent_type_en_evento_interno` ⇒ `agents_seen` vacío (rojo).
   - `caso_g3_target_por_claudecode_fallback` ⇒ el Stop cierra limpio en vez de
     bloquear (rojo). Requiere el cambio a `lab_run` (unsetear/pasar `CLAUDECODE`).
   - `caso_g3_agent_type_cuenta` (el invertido) ⇒ también rojo (hoy no cuenta).
2. Arreglo en el hook (A10 línea 23, A9 línea 831-833).
3. `SAIKIT_HOOK_VIVO="$PWD/hooks/summonaikit-harness.sh" bash tests/run.sh` → verde.
4. Re-grabar la baseline, declarar el diff del escenario 16.
5. `pre-commit run --all-files`.
6. Commit: `feat(3.7): A9+A10 cerrados — agent_type cuenta y CLAUDECODE resuelve TARGET`.
7. `tools/install-hook.sh` — después del commit.
8. **Turno real de validación (operador adelante):** un `-saikit` con
   delegaciones; el estado debe quedar `agents_seen=implementer,verifier,reviewer`
   y el Stop **exigir** la secuencia (no cerrar limpio si falta). Esto es lo que
   la baseline no puede atestiguar (corre con TARGET explícito).
9. Cierre en `Plans.md`, DoD punto por punto (`cc:TODO` → `cc:完了 [sha]`).

## No entra en esta tarea (límites declarados)

- **No se cambia el comando del operador en `settings.json`.** La vía “limpia”
  para A10 sería poner el `export SUMMONAIKIT_HOOK_TARGET=claude` **dentro** del
  `bash -c` del comando registrado (medido: así TARGET llega). Pero ese comando
  no lo genera ningún tool del repo (`install-hook.sh` instala el archivo, no el
  registro) — tocarlo es una edición manual del operador, fuera del alcance. El
  fallback `CLAUDECODE=1` desbloquea el gate de Claude sin ese cambio.
- **Cursor queda sin TARGET.** `CLAUDECODE=1` no identifica cursor (ni zcode).
  Las ramas `cursor` (`:641`, `:699`, `:913`) siguen inertes en producción hasta
  que se adopte la vía del comando o un detector de cursor. No es objetivo de
  este repo (summonaikit-**claude**).
- **La cláusula del matcher se dropa.** La DoD original pedía que
  `check-hook-registration.sh` reportara si el matcher no cubre `Agent`. Ya no
  aplica: el rol llega por los eventos internos (que matchean), no por los
  `Agent`. Exigir `Agent` sólo tenía sentido bajo la premisa falsa de 2.4.
- **El gate sigue `advisory`.** Quien controla el payload sigue pudiendo nombrar
  el rol que quiera en `agent_type`. Lo que A9+A10 cierran es que el gate
  **corra** (A10) y **vea** el rol real (A9) en un turno legítimo.
- **No se persigue por qué el host descarta el prefijo `VAR=val`.** Es internals
  del host (probablemente corre el comando sin shell que lo parsee, o vía
  `cmd.exe` en Windows). El efecto está medido y el arreglo no depende de la
  causa exacta.
