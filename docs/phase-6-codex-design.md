# Phase 6 — Codex como tercer host

Fecha: 2026-08-12

Diseño aprobado. El ledger de tareas sale de acá y vive en `Plans.md`; el delta
de producto aprobado para esta fase ya vive en `docs/spec/00-project-spec.md`.
Cada tarea agrega allí sólo los hechos que mida al cerrar.

Ubicación del archivo: `docs/` plano, como el resto de los planes de este repo
(`task-N.N-plan.md`). No se creó `docs/superpowers/specs/` para no abrir un
árbol nuevo en un layout deliberado.

## Purpose

Que un turno `-saikit` en Codex CLI gatee igual que uno en Claude Code: mismos
arreglos, misma ceremonia de roles, mismo recibo. Hoy Codex corre otra variante
del kit, con los once defectos abiertos y la ceremonia inerte.

**Esto reabre un Non-Goal original.** El delta aprobado ya quedó incorporado al
spec: la fase lo revierte **solo para `.codex`**. `.cursor` y `.agents` siguen
fuera y su divergencia sigue declarada.

## Premisas medidas (2026-08-12, no supuestas)

Estas mediciones son la base del alcance. Si alguna cae, la fase se re-planifica.

### Los dos archivos

| | Claude (nuestro) | Codex (vivo) |
|---|---|---|
| Ruta | `~/.claude/hooks/summonaikit-harness.sh` | `~/.codex/hooks/summonaikit-harness.sh` |
| Líneas / bytes | 1275 / 69327 | 849 / 55609 |
| sha256 | `7dbe1566…c093e98` | `4e6a92fa…7902db0f` |
| Marcador de propiedad | sí (línea 2) | **no** |
| Arreglos A1–A11 | todos | **ninguno** |
| Escrito por última vez | el instalador de este repo | 2026-08-08 15:20:51, heal de quality-kit |

El de Codex trae los dos parches por anclas de quality-kit (20 ocurrencias de
`SAIKIT-SENTINEL-GATE` / `SAIKIT-REVIEW-NOTICE`).

### La cadena de registro de Codex

```
~/.codex/hooks.json  →  summonaikit-harness.ps1  →  ~/.codex/hooks/summonaikit-harness.sh
                        (acá nace SUMMONAIKIT_HOOK_TARGET=codex)
```

Codex CLI 0.147.0, `hooks = true` en `config.toml`. El `.ps1` setea la variable
como env real del proceso, no como prefijo `VAR=val` del comando registrado —
que es el mecanismo que A10 midió que **no** se propaga. **Codex es el único
host donde el `TARGET` llega.**

El `.ps1` ya trae fallback a `<repo>/.codex/hooks/`: el mecanismo de staging por
override de proyecto existe y no hay que inventarlo.

### La ceremonia nunca corrió en Codex

El fork de Codex tiene su rama de ceremonia en `if [ "$TARGET" = "claude" ]`
(su línea 756). Con el `.ps1` mandando `TARGET=codex`, esa condición es falsa
siempre. Es A10 otra vez por el mecanismo inverso: en Claude el `TARGET` no
llegaba, en Codex llega y la rama no lo acepta.

Consecuencias medidas:

- Los 5 perfiles de rol están instalados (`~/.codex/agents/{closer,implementer,
  retro,reviewer,verifier}.toml`) y el gate nunca los pidió. **El equivalente de
  la Task 5.6 ya está hecho en Codex**, en formato `.toml`.
- `~/.codex/hooks/state/` está **vacío**. No distingue "cerró limpio" de "nunca
  armó".
- El historial trae **un** turno `-saikit` (`ts 1785821807`).
- El `ROLE FALLBACK` que el vendor escribió como escotilla vive dentro de esa
  rama muerta: **nunca se ejecutó, en ningún host**.

### Qué tiene cada variante que la otra no

Solo en el sabor Codex:

| | Qué es | Veredicto |
|---|---|---|
| `harness_context_lite` / `-harness-lite` | contrato alterno para cambios mecánicos | se deja ir |
| `resolve_state_paths` | estado por sesión | se deja ir — superado por A4 (Task 3.4) |
| MODEL CHECK (`:439`) | computa por env si la sesión es el modelo de la cuenta Claude | se deja ir |
| `ROLE FALLBACK` (5 ocurrencias) | **escotilla dentro del gate** | **se absorbe** |
| `AUDIT MODE` (1) | protocolo de contrato para tareas sin cambios | fuera de alcance, declarado |

Solo en el nuestro: `assistant_text_payload`/`assistant_text_transcript` (A2+A8),
`json_tool_input_string`/`json_top_level_string` (A1+A9), `redact_secrets` (A5),
`transcript_en_perfil` (A6).

**No es un merge bidireccional.** Se midió: el hook vivo de Claude pre-adopción
—el backup `summonaikit-harness.sh.vendor.20260810-161037.bak`, los 40333 bytes
exactos que la Task 2.1 adoptó— tiene **cero** ocurrencias de `-harness-lite`,
`harness_context_lite` y `MODEL CHECK`. Y el heal de quality-kit lo dice en su
propio comentario (línea 306): *"Ancla RN-G (SOLO .codex, opcional): … dentro de
`harness_context_lite` (modo `-harness-lite`), que `.claude`/`.cursor`/`.agents`
no tienen."* Son del sabor Codex del vendor, no algo que se haya perdido del
nuestro.

El MODEL CHECK es la excepción: es una **edición a mano** en el archivo de Codex
(comentario en español, no lo aplica el heal — el heal apenas sabe que existe
para rutear su ancla RN-H). Nada lo re-aplica y nada lo prueba.

### Por qué el MODEL CHECK no se absorbe

Es el parche de un agujero que el contrato de Codex abre y el nuestro no. Ese
contrato dice: *"Skip this call ONLY when the MODEL powering this session is the
Claude account model."* Esa cláusula le da al modelo una condición para saltarse
la revisión cruzada, y glm la usó mal (se creyó Claude por el "You are Claude
Code" del system prompt). El MODEL CHECK computa la identidad por environment y
pisa la autoidentificación.

Medido: nuestro hook tiene **cero** referencias a `ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN` y `ANTHROPIC_API_KEY`, y **ninguna** instrucción de
revisión cruzada en el contrato. Sin cláusula de salteo no hay nada de qué
mentir. Traer el MODEL CHECK solo sería importar la cura sin la enfermedad. La
revisión cruzada la pide el `CLAUDE.md` global del operador (regla 3, tope de 1
ronda), sin condición de modelo y en todos los hosts.

### El seam con quality-kit ya está construido

El skip por marcador del heal es **host-agnostic por diseño** (sus líneas 62-69):
*"si algún `.codex`/`.cursor`/`.agents` llegara a portar el marcador … se saltea
entero sin evaluar anclas."* Criterio: marcador en **cualquier** línea. No hace
falta tocar quality-kit.

## Decisiones

### D1 — Segunda copia en `~/.codex/hooks/`, wrapper intacto

La Task 5.3 fijó *"una sola copia del hook vive en `~/.claude/hooks`; el estado
se separa por `HOST`, no duplicando el archivo"*, y el instalador lo hace
cumplir rechazando `--dest` bajo `~/.zcode`.

Codex no es el mismo caso. La copia **ya existe** y es carga estructural del
`.ps1`, que es lo único que hace llegar el `TARGET`. Las alternativas eran:

- **(a)** segunda copia en `~/.codex/hooks/`, `.ps1` y `hooks.json` intactos;
- **(b)** una copia, repointando el `.ps1` a `~/.claude/hooks/`.

**Se elige (a).** Lo que 5.3 prohibió fue *inventar* una copia para separar
estado cuando el llaveado por `HOST` ya lo hacía. Adoptar una copia que ya
existe cuesta menos que adoptar el wrapper —que en (b) necesitaría marcador
propio, tres estados y lugar en la suite, una superficie de propiedad nueva en
PowerShell.

La intención de 5.3 se conserva por otra vía: **el instalador es el único
escritor de ambas rutas** y las compara byte a byte contra la misma fuente, así
que no pueden divergir sin que lo grite.

**Consecuencia que confirma la elección:** `PROFILE_DIR` sale de
`dirname "$HOOK_DIR"`. Con el archivo en `~/.codex/hooks/`, la contención de A6
apunta a `~/.codex`, que es donde Codex guarda `sessions/`. Con (b) hubiera
apuntado a `~/.claude` y el `transcript_path` de Codex habría quedado fuera del
perímetro: fail-open permanente. La (a) lo resuelve sin escribir código.

**Cambio declarado:** el mensaje de rechazo del `--dest` (*"Una sola copia del
hook vive en ~/.claude/hooks"*) pasa a ser falso y se reescribe. Regla nueva:
**el destino lo decide `--host`, y cada host declara su ruta.** `~/.zcode` sigue
rechazado (ahí sí sería copia inventada); `~/.codex` se habilita **solo** con
`--host codex`.

### D2 — `HOST=codex` por señal explícita, primero en el orden

Hoy (`hooks/summonaikit-harness.sh:65`):

```bash
if   [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then HOST=zcode
elif [ "${CLAUDECODE:-}" = "1" ];                          then HOST=claude
else                                                             HOST=other
fi
```

Queda:

```bash
if   [ "$SUMMONAIKIT_HOOK_TARGET" = "codex" ];             then HOST=codex
elif [ -n "${ZCODE_SESSION_ID:-}${ZCODE_PROJECT_DIR:-}" ]; then HOST=zcode
elif [ "${CLAUDECODE:-}" = "1" ];                          then HOST=claude
else                                                             HOST=other
fi
```

**El orden no es estético.** El operador corre Codex desde adentro de Claude (el
agente `codex:codex-rescue`, la skill `codex:rescue`, el `cross-review.ps1` de
su regla global). En ese caso el hook de Codex hereda `CLAUDECODE=1` del proceso
padre y se creería Claude — el mismo error de identidad que el MODEL CHECK
tapaba en el contrato, pero en el estado. La señal explícita tiene que ganar.

Tres propiedades que se declaran:

1. **Es allowlist, no passthrough.** Solo el literal `codex` mapea a
   `HOST=codex`. Cualquier otro valor de `SUMMONAIKIT_HOOK_TARGET` sigue cayendo
   por las ramas de abajo hasta `other`. Core Rule 2: un valor que no reconozco
   no es evidencia de nada.
2. **Sin regresión medible.** En Claude el `TARGET` llega vacío (A10), en zcode
   también, y en cursor el prefijo `VAR=val` probablemente tampoco llega. Los
   tres siguen cayendo donde caían.
3. **Es la primera vez que `HOST` sale de una variable nuestra** y no de una
   señal que inyecta el host. Se anota porque cambia la naturaleza de la
   evidencia: el `.ps1` es nuestro vecino, no el runtime de Codex. Si la 6.1
   encuentra una variable que Codex inyecte por sí mismo, esa es mejor señal y
   la rama se reescribe con ella.

El estado queda en `state/codex/<project_key>/…` sin código adicional: sale del
llaveado que la 5.3 ya construyó.

### D3 — La ceremonia acepta `codex`, **condicionada a la 6.1**

`hooks/summonaikit-harness.sh:1172` pasa de `[ "$TARGET" = "claude" ]` a
`case "$TARGET" in claude|codex)`.

**El cambio es de una línea y no se hace antes de la medición.** Si los eventos
de subagente de Codex no traen el rol, prender la rama convierte el gate de
inerte en inservible — el error exacto que el spec declara para el orden A9/A10:
*"van juntos o el gate pasa de inerte a inservible"*.

Si la 6.1 mide que el rol no llega, la rama **no se prende** y eso queda escrito
como límite, no como pendiente.

### D4 — Se absorbe `ROLE FALLBACK`, en los dos hosts

Es la única de las cinco que es **código en la condición del gate**, no texto de
contrato: `grep -Eiq 'ROLE FALLBACK: *IMPLEMENTER'` (y sus dos hermanas) permiten
declarar en el recibo `ROLE FALLBACK: <ROL> (razón)` **en lugar del despacho**,
para cuando el subagente se cae por infraestructura (429, límite de uso, error de
herramienta).

Nuestro hook no tiene ninguna escotilla ahí. Se absorbe por dos razones:

1. La ceremonia está por correr **por primera vez** en Codex; sin escotilla un
   429 deja el turno trabado sin salida.
2. Es un agujero que **Claude ya tiene hoy**. Esta fase lo descubre, no lo crea.

Va con su caso en la suite y su mutación.

### D5 — `AUDIT MODE` queda fuera

Es texto de contrato puro y no toca el gate. Sin él, una tarea de auditoría pasa
por la ceremonia normal: no hay agujero que cierre. Queda como divergencia
conocida, traíble en su propia tarea si la medición dice que hace falta.

## Arquitectura resultante

Una fuente (`hooks/summonaikit-harness.sh`), tres hosts, dos rutas instaladas:

| Host | Ruta instalada | Señal de `HOST` | `TARGET` | Ceremonia |
|---|---|---|---|---|
| Claude | `~/.claude/hooks/…` | `CLAUDECODE=1` | fallback a `claude` | sí |
| zcode | `~/.claude/hooks/…` (misma copia) | `ZCODE_SESSION_ID`/`ZCODE_PROJECT_DIR` | fallback a `claude` | sí |
| **Codex** | **`~/.codex/hooks/…` (segunda copia)** | **`SUMMONAIKIT_HOOK_TARGET=codex`** | **`codex` (real)** | **sí, si 6.1 lo habilita** |
| cursor | no instalado | ninguna ⇒ `other` | `cursor` si el prefijo `VAR=val` llega (**no medido**), si no vacío | no |

## Medición primero (6.1 y 6.2)

Ninguna toca el hook de producto, el instalador ni el perfil global; las dos
corren en un repo descartable con el operador adelante. Pueden extender las
herramientas de captura/probe y sus tests dentro del repo. Valen aunque el resto
de la fase se cancele, igual que 5.1/5.2.

### 6.1 — Payloads reales de Codex CLI 0.147.0

Un turno `-saikit`, las 3 fases. Cinco preguntas, cada una con una decisión
colgando:

| Pregunta | Qué decide |
|---|---|
| ¿Cómo se llama la herramienta de subagentes y **en qué campo viaja el rol**? | Si D3 se prende |
| ¿El matcher de `hooks.json` (`…\|Task\|exec\|local_shell_call\|shell_command\|commandExecution`) atrapa la delegación? | Lo mismo, la otra mitad de A9 |
| ¿`transcript_path` apunta adentro de `~/.codex/sessions/`? | Si la contención de A6 funciona o queda fail-open (como en zcode) |
| ¿`SUMMONAIKIT_HOOK_TARGET=codex` está de verdad en el env del hook? | D2 entera |
| Forma de los campos (snake_case / camelCase / anidamiento) | Si los lectores `json_*` sirven tal cual |

**Condición no negociable:** los fixtures de la línea base se construyen desde
estos payloads, no reconstruidos. Es la lección literal de la 1.4 — los 54
fixtures reconstruidos ni siquiera eran JSON válido y escondieron A9, A10 y A11.

### 6.2 — Contrato de salida

Las 4 formas (`hookSpecificOutput.additionalContext`, `decision:block`,
`continue:false`+`stopReason`, `systemMessage`) más `exit 2` en el `Stop`, un
turno cada una. Se reusa `tools/probe-zcode-output.sh`, que la 5.2 escribió para
esto.

**Hipótesis de trabajo, declarada como tal:** el fork de Codex usa nuestra misma
forma de bloqueo (`{"decision":"block","reason":…}` + `exit 2` + stderr) y su
`emit_allow` no imprime nada para no-cursor. O sea que el vendor cree que el
esquema de Claude sirve en Codex. Es una creencia, no una medición.

## Instalador y registro

**`--host codex`** escribe en `~/.codex/hooks/summonaikit-harness.sh` con los
tres estados de siempre (nuestro / vendor conocido / desconocido) y la misma
escritura atómica (`bash -n` sobre el temporal, `cmp` contra la fuente, `mv`
dentro del mismo directorio).

1. **El manifiesto gana la entrada de Codex** (`4e6a92fa…7902db0f`, 55609
   bytes). No es trámite: cada línea afirma *"este contenido exacto ya lo
   miramos y archivarlo no destruye nada"*, y acá se miró de verdad. Sin esa
   línea el instalador clasifica el destino como *desconocido* y se planta, que
   es lo correcto.
   **Límite declarado:** ese hash es estable mientras quality-kit no cambie sus
   parches. Si los cambia, el destino pasa a *desconocido* y el instalador se
   planta — fail-closed, correcto, pero hay que saberlo.
2. **`--restore-vendor` funciona para Codex** una vez que el hash está en el
   manifiesto, con las mismas negativas: sin backup del vendor ⇒ exit 6, destino
   desconocido no se pisa ni para deshacer, backup fuera del manifiesto no se
   restaura.
3. **`check-hook-registration.sh` tiene un problema nuevo, no una forma nueva.**
   Para Claude y zcode verifica que el settings **nombre al hook**. En Codex el
   registro nombra al **`.ps1`**, y el `.ps1` nombra al hook. La afirmación se
   vuelve indirecta. Se resuelve partiéndola en **dos afirmaciones separadas**:
   (a) el registro nombra al wrapper, (b) el wrapper existe y nombra al hook.
   Colapsarlas en una escondería cuál de las dos se rompió. Se mantiene el
   contrato del archivo: exit 0 siempre, comunica por texto, todo lo que no se
   pudo mirar es `unknown` y nunca "el registro falta".

**Riesgo de integración, declarado:** el heal de quality-kit va a saltear nuestro
archivo en `.codex` (verificado). Pero su propio comentario dice *"en producción
ningún target restante lo porta, así que `$skippedOwned` casi siempre queda
vacío"*. Instalar el nuestro lo vuelve no-vacío por primera vez. Si alguno de sus
443 asertos depende de eso, se pone rojo — y sería culpa nuestra. Se chequea
explícitamente **antes** de instalar.

## Testing

**Línea base dorada.** zcode tomó los escenarios 17–25; Codex toma del **26** en
adelante, uno por gate con su mitad que pasa y su mitad que bloquea. Construidos
desde los payloads de la 6.1.

Sale gratis: la función `normalizar` de `tools/golden-harness.sh` ya entiende
`state/<host>/<key>/` con clase de caracteres `[a-z]+` (la 5.3 la escribió así a
propósito, no con alternancia). `codex` entra sin tocarla.

**Mutaciones.** Hoy son 43, las 43 atrapadas. Tres nuevas, porque un caso verde
no dice por qué está verde:

| Mutación | Qué rompe | Quién tiene que atraparla |
|---|---|---|
| `mut_host_codex_sin_rama` | revierte `HOST=codex` (D2) | el caso de aislamiento de estado codex↔claude |
| `mut_ceremonia_sin_codex` | vuelve a `[ "$TARGET" = "claude" ]` (D3) | el caso de ceremonia en target codex |
| `mut_role_fallback_quitada` | saca la escotilla del gate (D4) | el caso nuevo de `ROLE FALLBACK` |

**El diff de la línea base que D4 va a mover, declarado por adelantado:** los
veredictos **no** deberían moverse —ningún escenario existente escribe
`ROLE FALLBACK:` en el recibo— pero el **texto del contrato inyectado sí
cambia**, así que `02-armado-contrato` y los escenarios que capturan la inyección
van a divergir. Esa divergencia **es** el cambio. Si aparece en algún otro lado,
es señal de que la escotilla toca más de lo que dice.

**Cobertura restante:** `test_install_hook.sh` y `test_restore_vendor.sh` ganan
los tres estados con `--host codex`; `test_hook_registration.sh` gana las dos
afirmaciones separadas del wrapper; `tests/fixtures/arnes-falso/escenarios/04-codex/`
espeja al `03-zcode`. Los fixtures nuevos pasan por `test_fixtures_json.sh`
(parseo real **más** fidelidad de rutas: ningún campo de path puede decodificar a
un carácter de control — ese guardia nació porque el primer arreglo de la 1.4
dejó un fixture válido y silenciosamente falso).

## La forma de la fase

| | Tarea | Toca Codex | Valor si se cancela el resto |
|---|---|---|---|
| 6.1 | Capturar payloads reales de Codex | no (repo descartable) | dice si la ceremonia es siquiera posible ahí |
| 6.2 | Medir el contrato de salida | no (repo descartable) | dice si el bloqueo funciona |
| 6.3 | Absorber `ROLE FALLBACK` | **no — solo Claude** | cierra un agujero que Claude ya tiene hoy |
| 6.4 | `HOST=codex` (D2) + rama de ceremonia (D3) | no (código + tests) | — |
| 6.5 | Manifiesto + `--host codex` + verificador del registro | no (código + tests) | — |
| 6.6 | Línea base del target + instalar + turno real | **sí** | — |

El perfil Codex no se instala ni se reemplaza hasta la 6.6.

**Dependía de que la Phase 5 cerrara, y cerró.** Verificado 2026-08-13: las seis
tareas (5.1–5.6) están en `cc:完了` y en `master`, con medición viva registrada
en 5.4 (harness en las 3 fases de zcode, `TARGET` por `ZCODE_*`, budget). Los
últimos commits son `90beabe` (5.5, línea base y escenarios del target zcode) y
`34fa256` (deploy log, PR #9).

Las dos piezas que esta fase reusa quedaron construidas: la **línea base por
target** (5.5), que la 6.6 extiende con los escenarios 26+, y la **segunda forma
de registro** en el instalador (5.4), que la 6.5 extiende con la tercera.
**Phase 6 no tiene bloqueantes.**

## Puesta en producción

**Directo al perfil, con `--restore-vendor` listo** (decisión del operador). No
hay staging en repo descartable para la 6.6, aunque el mecanismo existe (el
`.ps1` prefiere `<repo>/.codex/hooks/`). La red de seguridad es el backup fechado
que el instalador archiva antes de reemplazar, más `--restore-vendor`, que exige
que el hash del backup figure en el manifiesto.

## Non-Goals y límites declarados

- **`.cursor` y `.agents` quedan fuera.** Su divergencia sigue declarada. Se
  anota un hallazgo nuevo para cuando les toque: el registro de cursor usa el
  prefijo `SUMMONAIKIT_HOOK_TARGET=cursor … bash -c '…'`, la forma que A10 midió
  que Claude Code **no** propaga. Si el runner de Cursor se comporta igual —**no
  medido, es analogía**— su `TARGET` tampoco llega y las 4 ramas `cursor` de
  nuestro hook son código muerto.
- **No se absorbe `AUDIT MODE`** (D5), ni `-harness-lite`, ni el MODEL CHECK, ni
  `resolve_state_paths`.
- **No se toca el `.ps1` ni `~/.codex/hooks.json`.** El registro de Codex queda
  como está.
- **No se toca quality-kit.** Su skip por marcador ya cubre `.codex`.
- **El gate sigue siendo advisory.** Nada de esta fase lo convierte en un control
  de seguridad: quien controla el texto del turno sigue pudiendo nombrar un rol
  en el `tool_input`, citar un runner sin correrlo, u omitir un subagente de solo
  lectura.
- **Los perfiles de rol de Codex no se tocan.** Los 5 `.toml` ya están y son del
  operador. No se instala nada en `~/.codex/agents/`, a diferencia de lo que la
  5.6 hace para zcode.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| La 6.1 mide que el rol no llega ⇒ la ceremonia no se puede exigir en Codex | D3 no se prende y queda escrito como límite. El resto de la fase (arreglos A1–A11, aislamiento de estado) sigue valiendo |
| La 6.2 mide que Codex ignora `decision:block` y `exit 2` ⇒ el gate es decorativo ahí | Se declara con su evidencia y se decide si hace falta una forma de salida propia, como la 5.2 decidió para zcode |
| Un aserto de quality-kit depende de `$skippedOwned` vacío | Chequeo explícito antes de instalar (§ Instalador) |
| El heal de quality-kit cambia sus parches ⇒ el hash del manifiesto queda viejo | Fail-closed: el instalador clasifica *desconocido* y no toca nada. Declarado, no mitigado |
| Correr Codex desde adentro de Claude confunde el `HOST` | D2, con la señal explícita primero en el orden, y su mutación |
