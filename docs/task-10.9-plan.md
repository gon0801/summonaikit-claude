# Task 10.9 — Plan: reglas permanentes en los otros tres hosts

`[Test]` `[lane:gate]` `[tdd:required]`. Depende de 10.6.

## Qué hereda esta fila

La 10.6 acotó la emisión de las reglas permanentes a `TARGET=claude` **a
propósito**: era el único host donde se MIDIÓ que `SessionStart` acepta
`hookSpecificOutput.additionalContext` y que el texto llega al modelo. zcode,
Codex y Grok quedaron `unknown` — **no** "no lo tienen".

Esta fila los saca de `unknown`, uno por uno, **con la medición delante**.

## Estado leído antes de medir (2026-08-16, solo lectura)

Leer el bundle no sustituye a medir —es exactamente lo que la 6.2 demostró
insuficiente, donde la hipótesis del diseño cayó en sus dos mitades— pero sí
decide si la medición vale la pena y qué forma emitir primero.

| Host | Versión | ¿Existe fase de arranque? | Evidencia leída |
|---|---|---|---|
| zcode | `zcode-app-cli` 3.7.5-11 (`zcode-runtime 0.16.1`) | **Sí** | `vendor/zcode.cjs`: `runSessionStartHooks("startup")` y `("resume")`, cada uno seguido de `injectHookAdditionalContextIntoMessageHistory(Kr.SessionStart, …)`. El `switch` que acumula `additionalContexts` incluye `case Kr.SessionStart`. Hay schema de salida con `hookEventName: literal(Kr.SessionStart)` y clave de config `SessionStart` |
| Codex | `codex-cli` 0.147.0 | **Sí** | `~/.codex/hooks.json` ya tiene `SessionStart` con dos grupos (`matcher:"startup"` y uno sin matcher), **ambos ajenos** |
| Grok | `grok 1.0.4` | **Sí** | `docs/user-guide/10-hooks.md`: `SessionStart` dispara una vez por sesión, matchers `startup`/`resume`. Declarado **pasivo**: *"its output is recorded but does not change control flow"*. `additionalContext` sólo se documenta para `Stop` |

### Dos hechos que la lectura destapó y hay que escribir

1. **zcode ya cae dentro de la condición actual.** `TARGET` para zcode resuelve
   a `claude` por el fallback `ZCODE_SESSION_ID`/`ZCODE_PROJECT_DIR` (línea 53,
   decisión de la 5.4: las formas de salida medidas en 5.2 son las mismas que
   en Claude). O sea que `PHASE=session && TARGET=claude` **ya emitiría en
   zcode** — lo único que lo impide hoy es que el registro de
   `install-hook.sh --host zcode` sólo cubre 3 fases (`UserPromptSubmit`,
   `PostToolUse`, `Stop`). El guard de la 10.6 dice "sólo Claude" y **no es lo
   que el código hace**: zcode viaja de polizón bajo el mismo valor de `TARGET`.
   Registrar la 4.ª fase en zcode sin medir sería emitir sin veredicto, que es
   justo lo que esta fila viene a impedir.
2. **Grok pasó de 1.0.3 a 1.0.4 el 2026-08-13**, y la 7.2 midió sobre 1.0.3.
   Sus veredictos (`additionalContext` ignorado en 4 formas) describen una
   versión que ya no es la instalada. **Se declara, no se persigue**:
   re-validar la 7.2 entera es fila propia. Acá sólo se mide la fase de
   arranque, en 1.0.4, y el veredicto se anota con su versión.

Codex sigue en 0.147.0, la misma que midió la 6.2 ⇒ sus veredictos siguen
vigentes y se reusan (esquema **estricto**, `additionalContext` en UPS
**aceptado** entrando como mensaje `developer`).

## Mecanismo de registro del probe, por host

| Host | Vía | Por qué no hay una repo-local |
|---|---|---|
| zcode | append en `~/.zcode/cli/config.json` (USER-config) | el override `<repo>/.zcode/config.json` **no corre** en 3.7.5-11: `normalizeProjectConfig` le saca la clave `hooks` y emite `config_project_hooks_ignored` (medido 5.1) |
| Codex | append de UN grupo `SessionStart` en `~/.codex/hooks.json` | el shim de la 6.2 sólo se despacha donde nuestro `.ps1` YA está registrado (UPS/PostToolUse/Stop); en `SessionStart` no hay nada nuestro. Y un `<repo>/.codex/hooks.json` nuevo no corre: `config.toml` exige `trusted_hash` por entrada (medido 6.1, misma versión) |
| Grok | `<repo>/.grok/hooks/saikit-probe.json` + folder trust | **sí es repo-local**: el nombre del evento es la clave top-level del JSON de proyecto y `SessionStart` está en la lista aceptada |

Los dos appends a perfil (zcode y Codex) están **aprobados por el operador el
2026-08-16** con la misma condición: backup fechado, `--quitar` al terminar y
**cksum idéntico antes/después**. Los grupos ajenos no se tocan.

## §A — Protocolo de medición

Un modo por turno, sesión nueva por turno, repo descartable, headless donde el
host lo permita.

### Oráculos (heredados de 5.2 / 6.2 / 7.2)

1. **¿Corrió?** — `probe-ran/<nonce>.ok` que escribe el propio probe. Sin ese
   archivo ⇒ `unknown`, **nunca** "no corrió" (Core Rule 2).
2. **¿Llegó al modelo?** — dos señales independientes, y tienen que coincidir:
   - **Transcript**: el nonce aparece en el request que el host le manda al
     modelo. Por host: `~/.zcode/cli/rollout/model-io-sess_*.jsonl` (5.2),
     `~/.codex/sessions/…/rollout-*.jsonl` (6.2), archivos de sesión bajo
     `~/.grok/sessions/` (7.2). **Lectura, nunca escritura.**
   - **Oráculo observable**: el `additionalContext` lleva una instrucción que
     el modelo debe obedecer (devolver el literal del nonce). Es la
     materialización del hallazgo 5 del cross-review de la 7.2: **no se declara
     `ignored` sin validar el oráculo**.

   **Si las dos señales se contradicen ⇒ `unknown`, no `aceptada`.**

### Modos

| modo | stdout | exit | para qué |
|---|---|---|---|
| `empty` | (vacío) | 0 | control: fija cuántos `.ok` y qué transcript deja un arranque sin salida |
| `session` | `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"PROBE-SESSION-<nonce>…"}}` | 0 | **la forma que el hook emite hoy** (10.6) |
| `session_snake` | igual con `"hookEventName":"session_start"` | 0 | Grok manda el valor en snake en el PAYLOAD (7.1); hay que descartar que también lo exija en la SALIDA |
| `session_top` | `{"additionalContext":"PROBE-SESSTOP-<nonce>…"}` top-level | 0 | variante oráculo (7.2 C/D): descarta que el rechazo sea del envoltorio y no del canal |

Orden por host, para no gastar turnos de más:

- **zcode**: `empty` → `session`. Si `session` acepta, se cierra ahí.
- **Codex**: `empty` → `session`. El esquema es estricto (6.2), así que la
  forma limpia es la única candidata; si falla, `session_top`.
- **Grok**: `empty` → `session` → `session_snake` → `session_top`. La lectura
  dice que probablemente se ignore, y **declarar `ignored` exige agotar el
  oráculo**.

### Integridad del perfil (obligatoria, es evidencia)

`cksum` antes y después, y el número va al documento de resultados:

- zcode: `~/.zcode/cli/config.json`
- Codex: `~/.codex/hooks.json`
- Grok: `~/.grok/hooks/*`, `~/.grok/config.toml`, `~/.grok/trusted_folders.toml`

La lección de la 7.2 §E4 se aplica tal cual: el restore "quirúrgico" por
`grep -v` deja huérfanos en TOML; se restaura desde el backup y se verifica por
cksum, no por inspección visual.

## §B — Regla de decisión

Un host habilita emisión **sólo si** las dos señales del oráculo 2 coinciden en
que el texto llegó. Cualquier otra combinación deja el host como está:

| Resultado | Qué se hace |
|---|---|
| `.ok` + transcript + modelo obedece | **aceptada** ⇒ se habilita la emisión para ese host, con la forma medida |
| `.ok` + ninguna de las dos señales | **ignorada** ⇒ NO se habilita; se declara con su evidencia |
| `.ok` + señales en desacuerdo | **`unknown`** ⇒ NO se habilita |
| sin `.ok` | **`unknown`** ⇒ NO se habilita, y se dice que no se pudo observar |

**Habilitar no es sólo tocar el guard.** Por host:

- **zcode**: el guard ya lo cubre (`TARGET=claude`). Lo que cambia es el
  REGISTRO: `install-hook.sh --host zcode` pasa de 3 a 4 fases. Sin medición
  previa ese registro sería emisión a ciegas.
- **Codex**: el guard necesita `TARGET=codex`, y el registro es **acción de
  operador** sobre `~/.codex/hooks.json` — mismo patrón que la 10.6 en Claude y
  que la 9.9 con el matcher de `Agent`. El instalador no escribe ahí.

  **CORREGIDO tras medir (2026-08-16): editar `hooks.json` NO alcanza.** Codex
  0.147.0 exige además un registro de confianza por handler en
  `~/.codex/config.toml`:

  ```toml
  [hooks.state.'<ruta del hooks.json>:<evento_snake>:<indice_grupo>:<indice_hook>']
  trusted_hash = '…'
  ```

  Un grupo sin ese registro **se saltea en silencio**, así que un operador que
  siga sólo la primera mitad de esta fila creería haber registrado la fase y no
  correría nada. El `trusted_hash` lo **acuña el host**, no una herramienta: es
  su decisión de confianza. Y como la clave incluye el **índice del grupo**,
  **los índices existentes no se pueden mover**: reordenar el array desalinea el
  `trusted_hash` de los hooks ya registrados.
- **Grok**: el guard necesita `TARGET=grok` y `grok_json_canonico` gana un grupo
  `SessionStart` (pasa de 5 a 6 eventos).

## §C — Cómo se prueba (hook)

Los casos viven en la batería de comportamiento y cada uno tiene su mutación.
Sólo se escriben los casos de los hosts que la medición habilite; los que
resulten `ignored`/`unknown` se atan por su **negativa**, que es igual de
verificable:

| Caso | Qué fija |
|---|---|
| `caso_g1_session_inyecta_reglas_<host>` | un `SessionStart` sin sentinel en ese host emite la forma medida, sale 0 y **no escribe estado** |
| `caso_g1_session_no_inyecta_en_<host>` | para un host con veredicto `ignored`/`unknown`: la fase `session` sigue muda ahí (es la regresión que impide habilitar por accidente) |
| `caso_g1_no_arma_sin_sentinel` | **regresión**: `PHASE=prompt` sin sentinel sigue mudo en todos los hosts |
| `caso_g6_armado_por_target` | **regresión**: cursor con `-saikit` en `session` sigue armando |
| registro | `--host zcode` deja la 4.ª fase y `--quitar-zcode` la saca; los grupos ajenos sobreviven |

## §D — Línea base

Predicción declarada por adelantado: **divergen únicamente los escenarios de
`SessionStart` de los hosts que se habiliten; cero veredictos movidos** (exit
codes, `decision`, `agents_seen`). Si diverge algo más, el guard toca de más —
misma señal que usaron la 6.3 y la 10.6.

La 10.8 cerró el hueco que la 10.6 declaró (la línea base no cubría
`SessionStart`), así que esta vez **sí hay red** en esa fase.

## §E — Riesgos

| Riesgo | Mitigación |
|---|---|
| El append al perfil de zcode/Codex queda a medias y rompe el arranque del operador | backup fechado antes de tocar, `--quitar` idempotente, cksum verificado al final. Los dos hosts se miden **de a uno**, no en paralelo |
| Grok exige folder trust y queda concedido | se revoca al terminar y se verifica con `grok inspect` (patrón 7.2 §E4) |
| El texto de las reglas crece al sumar hosts | no crece: es el MISMO `standing_rules()`. Esta fila cambia a quién se le emite, no qué se emite |
| Emitir en un host cuyo `additionalContext` se ignora | no se habilita sin veredicto `aceptada`; el costo de equivocarse es texto muerto en cada arranque de ese host |
