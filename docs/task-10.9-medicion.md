# Task 10.9 — Medición de la fase de arranque en los otros tres hosts

Fecha: **2026-08-16**. Protocolo: `docs/task-10.9-plan.md` §A. Repos descartables
(`C:\dev\saikit-probe-109-{zcode,codex,grok}`), un modo por turno, sesión nueva
por turno, todo headless. Cero payloads crudos, cero prompts del operador, cero
rutas de perfil completas en este documento.

**Estado: PARCIAL.** Un veredicto cerrado (Grok), dos mediciones bloqueadas por
causas distintas y ambas declaradas abajo. Ningún host habilita emisión con esto.

## Integridad del perfil — los tres, byte a byte

Es evidencia, no trámite. `cksum` antes y después de todo:

| Archivo | Antes | Después |
|---|---|---|
| `~/.zcode/cli/config.json` | `1014530218 5458` | `1014530218 5458` ✓ |
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

## Codex — BLOQUEADO por mecanismo, y el mecanismo quedó medido

**No se pudo medir Q2/Q3, y la razón es un hallazgo por derecho propio:**

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

**Qué haría falta para desbloquear:** que Codex acuñe el `trusted_hash` de la
entrada nueva, que es acción de operador dentro de Codex (no la puede escribir a
mano una herramienta: el hash es su decisión de confianza). Hasta entonces Codex
queda **`unknown`** — no "no lo tiene": su `SessionStart` existe y dispara.

## zcode — BLOQUEADO por autenticación

- **Q1 medido y positivo:** el hook de `SessionStart` disparó (`.ok` con
  `event=SessionStart`), con el probe registrado como 3.ª fase del user-config.
- **Q2/Q3 no medidos:** los turnos fallaron antes de llegar al modelo.
  `zcode-2026-08-16.jsonl` lo dice de frente:
  `AiSdkModelAdapterError … "Model provider is missing an API key: zai"`,
  `code: provider_not_configured`, `envKey: ANTHROPIC_API_KEY`.
  Hay credencial guardada en el perfil, pero el proveedor no resuelve en una
  sesión headless nueva.

**Lo que la lectura del bundle dice, y sigue sin sustituir a la medición:**
`vendor/zcode.cjs` tiene `runSessionStartHooks("startup")` y `("resume")`, cada
uno seguido de `injectHookAdditionalContextIntoMessageHistory(Kr.SessionStart,…)`,
y el `switch` que acumula `additionalContexts` incluye `case Kr.SessionStart`. O
sea que el camino de inyección existe en el código. **No se registra como
veredicto**: la 6.2 ya mostró que leer el bundle puede fallar en las dos mitades
a la vez. zcode queda **`unknown`** hasta el turno que lo mida.

## Estado por host, para la fila de Plans.md

| Host | Q1 fase de arranque | Q2/Q3 llega al modelo | ¿Habilita emisión? |
|---|---|---|---|
| zcode | **sí, disparó** | `unknown` (auth) | **no** |
| Codex | **sí, dispara** | `unknown` (trusted_hash) | **no** |
| Grok | **sí, disparó** | **ignorada** (3 formas, oráculo agotado) | **no** |

Ninguno habilita todavía, y por tres razones distintas. La regla del plan §B se
respeta sin excepción: **sin veredicto `aceptada` no se registra nada.**
