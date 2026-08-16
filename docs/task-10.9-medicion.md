# Task 10.9 — Medición de la fase de arranque en los otros tres hosts

Fecha: **2026-08-16**. Protocolo: `docs/task-10.9-plan.md` §A. Repos descartables
(`C:\dev\saikit-probe-109-{zcode,codex,grok}`), un modo por turno, sesión nueva
por turno. Codex y Grok headless; **zcode con el operador adelante**, porque ahí
el headless resultó imposible (ver su sección). Cero payloads crudos, cero
prompts del operador, cero rutas de perfil completas en este documento.

**Estado: los 3 cerrados.** zcode y Codex **aceptan**; Grok **ignora**. El
resultado **no fue uniforme**, que es justo la razón por la que la fila mide en
vez de extrapolar: dos de tres habilitan, y el tercero habría sido texto muerto.

## Integridad del perfil — los tres, byte a byte

Es evidencia, no trámite. `cksum` antes y después de todo:

| Archivo | Antes | Después |
|---|---|---|
| `~/.zcode/cli/config.json` | `1014530218 5458` | **cambiado por el operador**, no por la medición: el `/login` escribe ahí la API key. Verificado por estructura — 0 entradas del probe, grupo ajeno intacto, JSON válido |
| `~/.codex/hooks.json` | `2271698800 2717` | `2271698800 2717` ✓ |
| `~/.codex/config.toml` | `3803647136 6012` | intacto (nunca se escribió) |
| `~/.grok/trusted_folders.toml` | `716294082 491` | `716294082 491` ✓ |
| `~/.grok/config.toml` | `158636524 6059` | `158636524 6059` ✓ |
| `~/.grok/hooks/summonaikit.json` | `464166032 1894` | `464166032 1894` ✓ |
| `~/.grok/hooks/summonaikit-harness.sh` | `2129441864 113112` | `2129441864 113112` ✓ |
| `~/.grok/hooks/imported-from-claude.json.disabled` | `3615174159 894` | `3615174159 894` ✓ |

El de `~/.codex/hooks.json` coincide además con el que registró la 6.2 el
2026-08-14: ese archivo no cambió en dos días de trabajo sobre otros hosts.

Restore del trust de Grok **desde el backup**, no por `grep -v`: el diff previo
confirmó que las únicas 4 líneas nuevas eran las nuestras (lección 7.2 §E4, donde
el restore quirúrgico dejó huérfanos `trusted`/`decided_at` en el TOML).

## Versiones medidas

| Host | Versión | vs. la fase que lo midió antes |
|---|---|---|
| zcode | `zcode-app-cli` 3.7.5-11 (`zcode-runtime 0.16.1`) | igual que 5.1/5.2 |
| Codex | `codex-cli` 0.147.0 | **igual que 6.2** ⇒ sus veredictos siguen vigentes |
| Grok | **1.0.4** | 7.2 midió **1.0.3**; la versión se movió el 2026-08-13 |

## Q1 — ¿existe la fase de arranque? Los tres: **SÍ, y disparó**

No es lectura de documentación: en los tres el probe dejó su `.ok`.

| Host | Literal del evento en el payload | Evidencia |
|---|---|---|
| zcode | `SessionStart` (CamelCase) | `.ok` con `mode=empty event=SessionStart` |
| Codex | `SessionStart` (CamelCase) | la traza del host imprime `hook: SessionStart` |
| Grok | **`session_start`** (snake) | `.ok` con `mode=empty event=session_start` |

La tabla por host que el probe ya traía de 7.1 (Grok manda el VALOR en snake) se
confirma en esta fase también.

## Grok — veredicto CERRADO: `additionalContext` **IGNORADO**

Las tres formas emitieron (`.ok` presente en las tres, o sea que el hook corrió y
llegó a su `printf`) y **ninguna llegó al modelo**:

| Modo | Forma | `.ok` | Token en la respuesta | Token en `~/.grok/sessions/` |
|---|---|---|---|---|
| `session` | `hookSpecificOutput` + `hookEventName: SessionStart` | sí | **no** | **no** |
| `session_snake` | igual con `hookEventName: session_start` | sí | **no** | **no** |
| `session_top` | `additionalContext` top-level | sí | **no** | **no** |

El oráculo se agotó antes de declarar `ignored` — es el hallazgo 5 del
cross-review de la 7.2, aplicado. Las tres llevaban una instrucción observable
("reply with the literal token …"); el modelo respondió las tres veces sin el
token, y el token tampoco aparece en ningún archivo de sesión.

Coincide con lo que la documentación de Grok 1.0.4 declara —*"every other event
is passive: its output is recorded but does not change control flow"*, y
`additionalContext` sólo se documenta para `Stop`— y extiende a `SessionStart` lo
que 7.2 midió en UPS y Stop sobre 1.0.3.

⇒ **Grok NO habilita emisión.** La regla de decisión del plan §B se aplica tal
cual: `.ok` presente + ninguna señal del oráculo = `ignorada`, y una `ignorada` no
se registra. Emitirle sería texto muerto en cada arranque de ese host.

## Codex — veredicto CERRADO: **ACEPTADA**

Los **dos** oráculos coincidieron, que es lo que la regla de decisión §B exige:

| Oráculo | Resultado |
|---|---|
| ¿corrió? | `.ok` con `mode=session event=SessionStart` |
| transcript | el nonce entra al rollout como `"role":"developer","content":[{"type":"input_text",…}]` — **la misma forma que la 6.2 midió para UPS** |
| instrucción observable | el modelo devolvió el token literal; en el mismo rollout se lee como `"role":"assistant","content":[{"type":"output_text",…}]` |

Una sola de las dos señales habría dejado el veredicto en `unknown`. Están las
dos, y en el mismo archivo.

**La forma emitida es la de Claude, sin cambios, y eso no es pereza:** 6.2 midió
que el esquema de Codex es **estricto** (una clave extra invalida la salida
entera), así que la forma limpia es la única candidata — y es exactamente la que
`emit_standing_rules` ya produce.

⇒ **Codex habilita emisión.** El **registro** no viene con eso: sigue siendo
acción de operador por lo que se explica abajo. El `.ps1` del perfil ya acepta
`-Phase session` y ya exporta `TARGET=codex`, así que la plomería estaba lista;
lo que faltaba era el veredicto.

### El mecanismo que casi lo deja en `unknown`, y que es hallazgo propio

Medir esto costó descubrir primero por qué **no** se podía medir:

> En Codex 0.147.0, registrar un hook **no es editar `hooks.json`**. Cada handler
> necesita además un registro propio en `~/.codex/config.toml`:
>
> ```
> [hooks.state.'<ruta del hooks.json>:<evento_snake>:<indice_grupo>:<indice_hook>']
> trusted_hash = '…'
> enabled = true          # en algunos
> ```
>
> Un grupo sin ese registro **se saltea en silencio**: sin error, sin aviso, sin
> entrada en la traza.

Cómo se llegó, descartando una hipótesis por vez (cada una un turno real):

1. Grupo nuevo en `.hooks.SessionStart`, sin matcher ⇒ **no corre**. Los dos
   grupos ajenos de esa misma fase sí corren.
2. ¿Será el guard `--only-cwd` del probe? Se sacó del comando ⇒ **sigue sin
   correr**. No es el cwd.
3. ¿Será que la fase exige `matcher`? Se le puso `matcher: "startup"` ⇒ **sigue
   sin correr**. No es el matcher.
4. ¿Serán las comillas de la ruta (las entradas ajenas que corren no las llevan)?
   Se reemplazó por un script trampa invocado sin comillas ⇒ **ni siquiera el
   script trampa corre**. No son las comillas.
5. ¿Será la posición en el array? Se movió al frente, con la forma de campos
   idéntica al grupo ajeno que sí corre ⇒ **sigue sin correr**.
6. `config.toml` tiene `[hooks.state]` con una entrada por handler, y hay
   `session_start:0:0` y `session_start:1:0` — los dos ajenos — y **ninguna para
   el índice 2**, que era el nuestro.

Eso también explica el paso 5 y por qué **se revirtió de inmediato**: reordenar
el array cambia los índices, y los índices son parte de la clave del registro de
confianza. Mover nuestro grupo al frente desalineaba el `trusted_hash` de los
hooks del operador. `hooks.json` se restauró desde snapshot y se verificó con un
turno real (`hook: SessionStart` dispara, el modelo responde) además del cksum.

Es la misma familia que el hallazgo de la 6.1 (*«`config.toml` exige
`trusted_hash` por entrada y uno nuevo no corre»*), medido allá para un
`<repo>/.codex/hooks.json` y **confirmado acá para el `hooks.json` GLOBAL**.

**Cómo se desbloqueó, y por qué esa vía es legítima:** el propio Codex trae
`--dangerously-bypass-hook-trust`, documentada como *"Run enabled hooks without
requiring persisted hook trust for this invocation. Intended only for automation
that already vets hook sources"*. Es **por invocación** (no persiste confianza),
el único hook sin confianza era **el nuestro**, y corrió en un repo descartable.
Con eso el `.ok` de `SessionStart` apareció, lo que confirma de paso que el
`trusted_hash` era el único bloqueo.

**Consecuencia para el registro en producción, declarada:** un `SessionStart`
nuestro en el perfil real **no va a correr** hasta que Codex acuñe su
`trusted_hash`. Eso es acción de operador dentro de Codex —el hash es su decisión
de confianza, no algo que una herramienta pueda escribir a mano— y es el mismo
patrón que la 10.6 en Claude y la 9.9 con el matcher de `Agent`. El instalador de
este repo no escribe ahí y no debe.

**Y una regla operativa que sale de esto:** los índices son parte de la clave, así
que **no se reordena** el array de una fase. Reordenar desalinea el
`trusted_hash` de los hooks ya registrados — es lo que pasó en el paso 5 y por
eso se revirtió en el acto.

## zcode — veredicto CERRADO: **ACEPTADA**

**Turno real con el operador adelante**, no headless: la medición headless fue
imposible y esa imposibilidad es en sí un dato (ver abajo).

Los **dos** oráculos, en la **misma línea** del rollout de la sesión:

| Oráculo | Resultado |
|---|---|
| ¿corrió? | `.ok` con `mode=session event=SessionStart` |
| transcript | el token está en `.request.messages[5].content`, con `role="system"`, precedido de `SessionStart hook additional context:` y numerado `#1` |
| instrucción observable | `.response.text` = `¡Hola! PROBE-SESSION-… ¿En qué te puedo ayudar hoy?` — el modelo devolvió el token literal |

**La forma de la inyección es la MISMA que 5.2 midió para UPS** (`role: system`,
prefijo `<Fase> hook additional context:`, numeración `#1`); lo único que cambia
es el nombre de la fase en el prefijo. Es la continuidad que hacía falta para no
tener que inventar nada.

⇒ **zcode habilita emisión, y sin rama nueva en el hook.** `TARGET` para zcode
resuelve a `claude` por el fallback de la 5.4, así que la condición existente ya
lo cubre. Lo que cambia es el **registro**: `install-hook.sh --host zcode` pasa
de 3 a 4 fases, y el caso que impedía esa 4.ª fase se invierte (ver abajo).

### La autenticación, y por qué el rodeo importa

Los primeros turnos murieron en
`AiSdkModelAdapterError … "Model provider is missing an API key: zai"`,
`code: provider_not_configured` — con credencial guardada en el perfil. Se
probó primero headless y después **el TUI, que falló idéntico**: eso descartó la
hipótesis cómoda de "es solo el camino headless" y dejó claro que la credencial
guardada no servía en ningún modo. El login del navegador tampoco es vía en
Windows (*"Z.AI browser login requires macOS for the registered zcode:// callback"*);
la que sirve es `/login zai-coding-plan-api-key <key>` dentro del TUI.

**Consecuencia para la integridad del perfil, declarada sin maquillar:** ese
login **escribe la API key en `~/.zcode/cli/config.json`** —lo dice el propio
CLI— que es el mismo archivo donde el probe hace su append. Por eso el cksum de
zcode **no vuelve** a su valor previo, y no sería honesto presentarlo como si lo
hiciera: el archivo cambió por una acción del operador, no por la medición. La
verificación de que la medición no dejó nada se hizo por **estructura**, sin leer
el contenido: 0 entradas con el marker del probe, el grupo ajeno de
`SessionStart` intacto, `hooks.enabled: true`, JSON válido.

### Lo que la lectura del bundle había anticipado

`vendor/zcode.cjs` tiene `runSessionStartHooks("startup")` y `("resume")`, cada
uno seguido de `injectHookAdditionalContextIntoMessageHistory(Kr.SessionStart,…)`,
y el `switch` que acumula `additionalContexts` incluye `case Kr.SessionStart`.
**La lectura acertó** — y aun así no se registró como veredicto hasta el turno
real, por la misma razón que la 6.2: ahí leer el bundle falló en las dos mitades
a la vez. Que esta vez coincidiera no cambia la regla; la habría cambiado un
resultado, no un acierto.

## Estado por host, para la fila de Plans.md

| Host | Q1 fase de arranque | Q2/Q3 llega al modelo | ¿Habilita emisión? |
|---|---|---|---|
| zcode | **sí, disparó** | **ACEPTADA** (2 oráculos coinciden) | **sí** |
| Codex | **sí, dispara** | **ACEPTADA** (2 oráculos coinciden) | **sí** |
| Grok | **sí, disparó** | **ignorada** (3 formas, oráculo agotado) | **no** |

**El resultado no fue uniforme**, y ese es el punto de la fila: tres hosts con
fase de arranque viva y tres respuestas distintas. Extrapolar de uno a otro
—que es lo que la 10.6 se negó a hacer— habría acertado en Codex y fallado en
Grok.

La regla del plan §B se respeta sin excepción: **sin veredicto `aceptada` no se
registra nada.** Grok tiene veredicto y es negativo; zcode no tiene veredicto.
Los dos quedan afuera, por razones distintas y las dos escritas.
